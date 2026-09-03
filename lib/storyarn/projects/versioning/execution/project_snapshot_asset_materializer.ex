defmodule Storyarn.Projects.Versioning.ProjectSnapshotAssetMaterializer do
  @moduledoc """
  Plans, stages, and adopts the complete logical asset catalog of one project
  snapshot restore.

  The provider phase consumes only verified restore-staging objects and creates
  deterministic, collision-safe destination keys before the database
  transaction starts. The adoption phase performs no provider I/O: it inserts
  every logical asset first, applies original/web/variant relationships only
  after every destination identity exists, and returns the historical-to-new
  identity map used by the project graph materializer.
  """

  import Bitwise
  import Ecto.Query, warn: false

  alias Storyarn.Commercial
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageCompensation
  alias Storyarn.Projects.Assets.StorageKeyLock
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.Versioning.Adapters.Storage.Hashing, as: StorageHash
  alias Storyarn.Projects.Versioning.Builders.AssetHashResolver
  alias Storyarn.Projects.Versioning.SnapshotObjectFormat
  alias Storyarn.Repo

  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @logical_id_regex ~r/\Aasset-[0-9]{6}\z/
  @workspace_snapshot_import_staging_prefix_regex ~r/\Aworkspace-snapshot-imports\/v1\/[1-9][0-9]*\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  defmodule Plan do
    @moduledoc false

    @enforce_keys [
      :project_id,
      :restore_identity,
      :staging_prefix,
      :assets,
      :blobs,
      :source_refs,
      :logical_bytes,
      :staging_bytes
    ]
    defstruct @enforce_keys
  end

  @type plan :: %Plan{}

  @doc """
  Builds an immutable materialization plan from an already validated manifest.

  `staging_keys` must contain exactly one collision-safe key for every unique
  blob declared by the manifest. Current project assets and their storage keys
  are deliberately not inputs to this function.
  """
  @spec prepare(pos_integer(), String.t() | pos_integer(), map(), map(), String.t(), map()) ::
          {:ok, plan()} | {:error, term()}
  def prepare(project_id, restore_identity, manifest, project_object, staging_prefix, staging_keys)
      when is_integer(project_id) and project_id > 0 and is_map(manifest) and is_map(project_object) and
             is_binary(staging_prefix) and is_map(staging_keys) do
    assets = manifest["assets"]
    objects = manifest["objects"]
    source_refs = project_object["asset_catalog_refs"]

    with :ok <- validate_restore_identity(restore_identity),
         :ok <- SnapshotObjectFormat.validate_manifest(manifest),
         :ok <- SnapshotObjectFormat.validate_project(project_object),
         :ok <- SnapshotObjectFormat.validate_source_refs(source_refs, assets),
         :ok <- AssetHashResolver.validate_pre_materialized_catalogs(project_object, source_refs, assets),
         {:ok, blobs} <- blob_objects(objects),
         :ok <- validate_staging_keys(blobs, staging_prefix, staging_keys),
         {:ok, planned_assets} <-
           plan_assets(
             project_id,
             restore_identity,
             assets,
             staging_keys,
             source_refs,
             project_object,
             staging_prefix
           ) do
      {:ok,
       %Plan{
         project_id: project_id,
         restore_identity: to_string(restore_identity),
         staging_prefix: staging_prefix,
         assets: planned_assets,
         blobs: plan_blobs(project_id, blobs, staging_keys),
         source_refs: source_refs,
         logical_bytes: Enum.reduce(assets, 0, &(&1["size_bytes"] + &2)),
         staging_bytes: Enum.reduce(blobs, 0, &(&1["size_bytes"] + &2))
       }}
    else
      {:error, _reason} = error -> error
    end
  end

  def prepare(_project_id, _restore_identity, _manifest, _project_object, _staging_prefix, _staging_keys),
    do: {:error, :invalid_snapshot_asset_materialization_source}

  defp validate_restore_identity(identity) when is_binary(identity) and identity != "", do: :ok
  defp validate_restore_identity(identity) when is_integer(identity) and identity > 0, do: :ok
  defp validate_restore_identity(_identity), do: {:error, :invalid_snapshot_asset_materialization_source}

  @doc """
  Copies and verifies every final provider object outside the database
  transaction. The caller owns `tracker` through commit or rollback.
  """
  @spec stage_destination_objects(plan(), reference()) :: :ok | {:error, term()}
  def stage_destination_objects(%Plan{} = plan, tracker) when is_reference(tracker) do
    if Repo.in_transaction?() do
      {:error, :snapshot_asset_staging_inside_transaction}
    else
      lock_destinations? = not workspace_snapshot_import_staging_prefix?(plan.staging_prefix)

      with :ok <- stage_protected_blobs(plan.blobs, tracker, lock_destinations?) do
        stage_logical_assets(plan.assets, tracker, lock_destinations?)
      end
    end
  end

  def stage_destination_objects(_plan, _tracker), do: {:error, :invalid_snapshot_asset_staging_request}

  @doc false
  @spec planned_storage_keys(plan()) :: [String.t()]
  def planned_storage_keys(%Plan{} = plan) do
    (Enum.map(plan.blobs, & &1.destination_key) ++
       Enum.map(plan.assets, & &1.destination_key))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Adopts a staged catalog inside the final restore transaction.

  Returns both the logical identity map and the historical database-ID map.
  No provider read or write occurs in this phase.
  """
  @spec adopt_locked(plan(), Project.t(), pos_integer() | nil, reference()) ::
          {:ok, %{assets: [Asset.t()], logical_id_map: map(), source_id_map: map()}} | {:error, term()}
  def adopt_locked(%Plan{project_id: project_id} = plan, %Project{id: project_id} = project, actor_id, tracker)
      when (is_nil(actor_id) or (is_integer(actor_id) and actor_id > 0)) and is_reference(tracker) do
    with :ok <- validate_adoption_scope(project) do
      Assets.with_import_capacity(
        project,
        plan.logical_bytes,
        fn -> adopt_catalog_locked(plan, project, actor_id, tracker) end
      )
    end
  end

  def adopt_locked(_plan, _project, _actor_id, _tracker), do: {:error, :invalid_snapshot_asset_adoption_request}

  defp validate_adoption_scope(project) do
    cond do
      not Repo.in_transaction?() -> {:error, :snapshot_asset_adoption_requires_transaction}
      not Commercial.workspace_lock_held?(project.workspace_id) -> {:error, :storage_accounting_lock_required}
      true -> :ok
    end
  end

  defp adopt_catalog_locked(plan, project, actor_id, tracker) do
    with {:ok, assets, logical_id_map} <- insert_assets(plan.assets, project, actor_id),
         {:ok, source_id_map} <- source_id_map(plan.source_refs, logical_id_map),
         {:ok, assets} <-
           apply_relationships(
             plan,
             assets,
             logical_id_map,
             source_id_map,
             project
           ),
         :ok <- retain_adopted_objects(plan, tracker) do
      {:ok,
       %{
         assets: assets,
         logical_id_map: logical_id_map,
         source_id_map: source_id_map
       }}
    end
  end

  @doc false
  @spec verify_adopted_locked(plan(), map()) :: :ok | {:error, term()}
  def verify_adopted_locked(%Plan{} = plan, logical_id_map) when is_map(logical_id_map) do
    assets_by_id =
      from(asset in Asset,
        where: asset.project_id == ^plan.project_id and is_nil(asset.deleted_at),
        order_by: [asc: asset.id],
        lock: "FOR UPDATE"
      )
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    expected_ids = logical_id_map |> Map.values() |> MapSet.new()

    with true <- MapSet.new(Map.keys(assets_by_id)) == expected_ids,
         {:ok, source_id_map} <- source_id_map(plan.source_refs, logical_id_map) do
      verify_planned_assets(
        plan.assets,
        assets_by_id,
        logical_id_map,
        source_id_map
      )
    else
      false -> {:error, :snapshot_asset_inventory_mismatch}
      {:error, _reason} = error -> error
    end
  end

  def verify_adopted_locked(_plan, _logical_id_map), do: {:error, :invalid_snapshot_asset_verification}

  defp verify_planned_assets(planned_assets, assets_by_id, logical_id_map, source_id_map) do
    Enum.reduce_while(planned_assets, :ok, fn planned, :ok ->
      case verified_planned_asset(
             planned,
             assets_by_id,
             logical_id_map,
             source_id_map
           ) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp verified_planned_asset(planned, assets_by_id, logical_id_map, source_id_map) do
    asset_id = logical_id_map[planned.logical_id]

    case Map.fetch(assets_by_id, asset_id) do
      {:ok, asset} ->
        if adopted_asset_matches?(asset, planned, source_id_map),
          do: :ok,
          else: postverify_error(planned.logical_id)

      :error ->
        postverify_error(planned.logical_id)
    end
  end

  defp postverify_error(logical_id), do: {:error, {:snapshot_asset_postverify_failed, logical_id}}

  defp blob_objects(objects) when is_list(objects) do
    blobs = Enum.filter(objects, &match?(%{"kind" => "asset_blob"}, &1))

    if length(blobs) == length(objects) - 1,
      do: {:ok, Enum.sort_by(blobs, & &1["path"])},
      else: {:error, :invalid_snapshot_blob_inventory}
  end

  defp blob_objects(_objects), do: {:error, :invalid_snapshot_blob_inventory}

  defp validate_staging_keys(blobs, staging_prefix, staging_keys) do
    expected = Map.new(blobs, &{&1["path"], expected_staging_key(staging_prefix, &1["path"])})

    if staging_prefix_valid?(staging_prefix) and staging_keys == expected and
         Enum.all?(Map.values(staging_keys), &Storage.canonical_key?/1) do
      :ok
    else
      {:error, :snapshot_staging_inventory_mismatch}
    end
  end

  defp staging_prefix_valid?(prefix) do
    Storage.canonical_key?(prefix) and not String.ends_with?(prefix, "/") and
      (String.contains?(prefix, "/storage-reservations/v1/restore-staging/") or
         Regex.match?(@workspace_snapshot_import_staging_prefix_regex, prefix))
  end

  defp expected_staging_key(staging_prefix, path) do
    if String.starts_with?(staging_prefix, "workspaces/"),
      do: staging_prefix <> "/blobs/" <> Path.basename(path),
      else: staging_prefix <> "/" <> path
  end

  defp plan_assets(project_id, restore_identity, assets, staging_keys, source_refs, project_object, staging_prefix) do
    source_ids_by_logical_id = Map.new(source_refs, fn {source_id, logical_id} -> {logical_id, source_id} end)
    persisted_catalog = Map.get(project_object, "asset_metadata", %{})

    assets
    |> Enum.reduce_while({:ok, []}, fn asset, {:ok, planned} ->
      with {:ok, logical_id} <- logical_id(asset),
           {:ok, uuid} <- deterministic_uuid(restore_identity, logical_id),
           {:ok, source_key} <- Map.fetch(staging_keys, asset["blob_path"]),
           {:ok, source_id} <- Map.fetch(source_ids_by_logical_id, logical_id),
           {:ok, persisted, persisted_metadata} <- exact_persisted_asset_metadata(persisted_catalog, source_id) do
        destination_key = destination_asset_key(project_id, uuid, asset, staging_prefix)

        entry = %{
          logical_id: logical_id,
          filename: Map.get(persisted, "filename", asset["filename"]),
          content_type: asset["content_type"],
          size: asset["size_bytes"],
          sha256: asset["sha256"],
          content_size: asset["size_bytes"],
          content_type_for_storage: asset["content_type"],
          metadata: persisted_metadata,
          source_key: source_key,
          destination_key: destination_key,
          destination_blob_key:
            BlobStore.blob_key(
              project_id,
              asset["sha256"],
              BlobStore.ext_from_content_type(asset["content_type"])
            )
        }

        {:cont, {:ok, [entry | planned]}}
      else
        :error -> {:halt, {:error, :snapshot_staging_inventory_mismatch}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, planned} -> {:ok, Enum.reverse(planned)}
      {:error, _reason} = error -> error
    end
  end

  defp exact_persisted_asset_metadata(catalog, source_id) when is_map(catalog) do
    with {:ok, persisted} when is_map(persisted) <- Map.fetch(catalog, source_id),
         filename when is_binary(filename) <- persisted["filename"],
         {:ok, metadata} when is_nil(metadata) or is_map(metadata) <- Map.fetch(persisted, "persisted_metadata") do
      {:ok, Map.put(persisted, "filename", filename), metadata}
    else
      _missing_or_invalid -> {:error, :invalid_snapshot_asset_persisted_catalog}
    end
  end

  defp exact_persisted_asset_metadata(_catalog, _source_id), do: {:error, :invalid_snapshot_asset_persisted_catalog}

  defp destination_asset_key(project_id, uuid, asset, staging_prefix) do
    filename =
      if workspace_snapshot_import_staging_prefix?(staging_prefix) do
        extension = BlobStore.ext_from_content_type(asset["content_type"])
        "#{asset["sha256"]}.#{extension}"
      else
        Assets.sanitize_filename(asset["filename"])
      end

    "projects/#{project_id}/assets/#{uuid}/#{filename}"
  end

  defp plan_blobs(project_id, blobs, staging_keys) do
    Enum.map(blobs, fn blob ->
      %{
        path: blob["path"],
        content_type: blob["content_type"],
        size: blob["size_bytes"],
        sha256: blob["sha256"],
        source_key: Map.fetch!(staging_keys, blob["path"]),
        destination_key:
          BlobStore.blob_key(
            project_id,
            blob["sha256"],
            BlobStore.ext_from_content_type(blob["content_type"])
          )
      }
    end)
  end

  defp logical_id(%{"logical_id" => logical_id}) when is_binary(logical_id) do
    if Regex.match?(@logical_id_regex, logical_id),
      do: {:ok, logical_id},
      else: {:error, :invalid_snapshot_asset_logical_id}
  end

  defp logical_id(_asset), do: {:error, :invalid_snapshot_asset_logical_id}

  defp deterministic_uuid(restore_identity, logical_id) do
    digest = :crypto.hash(:sha256, "storyarn.snapshot.restore.asset.v1:#{restore_identity}:#{logical_id}")
    <<a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, _rest::binary>> = digest
    bytes = <<a, b, c, d, e, f, (g &&& 0x0F) ||| 0x50, h, (i &&& 0x3F) ||| 0x80, j, k, l, m, n, o, p>>

    case Ecto.UUID.load(bytes) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :snapshot_asset_identity_invalid}
    end
  end

  defp stage_protected_blobs(blobs, tracker, lock_destinations?) do
    Enum.reduce_while(blobs, :ok, fn blob, :ok ->
      case stage_protected_blob(blob, tracker, lock_destinations?) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, {:snapshot_blob_staging_failed, blob.path, reason}}}
      end
    end)
  end

  defp stage_protected_blob(blob, tracker, false) do
    with :ok <- verify_object(blob.source_key, blob.size, blob.sha256) do
      # The durable workspace-import plan retains these bytes across retries;
      # reuse a verified destination without issuing another fenced write.
      case verify_object(blob.destination_key, blob.size, blob.sha256) do
        :ok -> :ok
        {:error, _reason} -> stage_protected_blob_locked(blob, tracker)
      end
    end
  end

  defp stage_protected_blob(blob, tracker, true) do
    with :ok <- verify_object(blob.source_key, blob.size, blob.sha256) do
      StorageKeyLock.with_storage_key_lock(
        blob.destination_key,
        fn -> stage_protected_blob_locked(blob, tracker) end
      )
    end
  end

  defp stage_protected_blob_locked(blob, tracker) do
    with {:ok, created?} <- copy_protected_blob(blob, tracker),
         :ok <- maybe_track_blob(tracker, blob.destination_key, created?) do
      verify_protected_destination(blob, tracker, created?)
    end
  end

  defp verify_protected_destination(blob, tracker, created?) do
    case verify_object(blob.destination_key, blob.size, blob.sha256) do
      :ok ->
        :ok

      {:error, _reason} = error ->
        if created?, do: StorageCompensation.track_force_delete(tracker, blob.destination_key)
        error
    end
  end

  defp copy_protected_blob(blob, tracker) do
    case Storage.copy_if_absent_or_stream(
           blob.source_key,
           blob.destination_key,
           blob.size,
           blob.content_type
         ) do
      {:ok, created?} when is_boolean(created?) ->
        {:ok, created?}

      {:error, {:conditional_copy_cleanup_required, created?, cleanup_key, _reason} = reason}
      when is_boolean(created?) and is_binary(cleanup_key) ->
        if created?, do: StorageCompensation.track_force_delete(tracker, blob.destination_key)
        StorageCompensation.track_force_delete(tracker, cleanup_key)
        {:error, reason}

      {:error, {:storage_write_cleanup_required, cleanup_key, _write_reason, _cleanup_reason} = reason}
      when is_binary(cleanup_key) ->
        StorageCompensation.track_force_delete(tracker, cleanup_key)
        {:error, reason}

      {:error, _reason} = error ->
        # A lost provider response can hide a successful publish. Track the
        # protected destination conservatively; never force-delete a key that
        # may have existed before this restore.
        StorageCompensation.track(tracker, blob.destination_key)
        error
    end
  end

  defp stage_logical_assets(assets, tracker, lock_destinations?) do
    Enum.reduce_while(assets, :ok, fn asset, :ok ->
      case stage_logical_asset(asset, tracker, lock_destinations?) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:snapshot_asset_staging_failed, asset.logical_id, reason}}}
      end
    end)
  end

  defp stage_logical_asset(asset, tracker, false) do
    with :ok <- verify_object(asset.source_key, asset.content_size, asset.sha256) do
      case verify_object(asset.destination_key, asset.content_size, asset.sha256) do
        :ok -> StorageCompensation.track_force_delete(tracker, asset.destination_key)
        {:error, _reason} -> do_stage_logical_asset(asset, tracker)
      end
    end
  end

  defp stage_logical_asset(asset, tracker, true) do
    with :ok <- verify_object(asset.source_key, asset.content_size, asset.sha256) do
      StorageKeyLock.with_storage_key_lock(asset.destination_key, fn ->
        do_stage_logical_asset(asset, tracker)
      end)
    end
  end

  defp do_stage_logical_asset(asset, tracker) do
    with {:ok, _created?} <-
           Storage.copy_if_absent_or_stream(
             asset.source_key,
             asset.destination_key,
             asset.content_size,
             asset.content_type_for_storage
           ),
         :ok <- StorageCompensation.track_force_delete(tracker, asset.destination_key),
         :ok <- verify_object(asset.destination_key, asset.content_size, asset.sha256) do
      :ok
    else
      {:error, {:conditional_copy_cleanup_required, created?, cleanup_key, _reason} = reason} ->
        if created?, do: StorageCompensation.track_force_delete(tracker, asset.destination_key)
        StorageCompensation.track_force_delete(tracker, cleanup_key)
        {:error, reason}

      {:error, {:storage_write_cleanup_required, cleanup_key, _write_reason, _cleanup_reason} = reason} ->
        StorageCompensation.track_force_delete(tracker, cleanup_key)
        {:error, reason}

      {:error, _reason} = error ->
        error
    end
  end

  defp maybe_track_blob(tracker, key, true), do: StorageCompensation.track(tracker, key)
  defp maybe_track_blob(_tracker, _key, false), do: :ok

  defp verify_object(key, expected_size, expected_sha256)
       when is_integer(expected_size) and expected_size >= 0 and is_binary(expected_sha256) do
    with true <- Regex.match?(@sha256_regex, expected_sha256),
         {:ok, %{size: ^expected_size, etag: etag}} <- Storage.stat(key),
         {:ok, chunks} <- Storage.stream(key, 0, expected_size, etag: etag),
         {:ok, ^expected_sha256} <- StorageHash.sha256_chunks(chunks) do
      :ok
    else
      false -> {:error, :invalid_snapshot_blob_checksum}
      {:ok, %{size: actual_size}} -> {:error, {:snapshot_blob_size_mismatch, expected_size, actual_size}}
      {:ok, actual_sha256} -> {:error, {:snapshot_blob_checksum_mismatch, expected_sha256, actual_sha256}}
      {:error, _reason} = error -> error
    end
  end

  defp insert_assets(planned_assets, project, actor_id) do
    attrs_list =
      Enum.map(planned_assets, fn planned ->
        attrs = %{
          filename: planned.filename,
          content_type: planned.content_type,
          size: planned.size,
          key: planned.destination_key,
          url: Storage.get_url(planned.destination_key),
          metadata: initial_metadata(planned.metadata),
          blob_hash: planned.sha256,
          snapshot_content_size: planned.content_size
        }

        attrs
      end)

    case Assets.import_snapshot_assets_locked(project, actor_id, attrs_list) do
      {:ok, assets} ->
        logical_id_map =
          planned_assets
          |> Enum.zip(assets)
          |> Map.new(fn {planned, asset} -> {planned.logical_id, asset.id} end)

        {:ok, assets, logical_id_map}

      {:error, {:snapshot_asset_batch_entry_failed, index, reason}} ->
        planned = Enum.at(planned_assets, index)
        {:error, {:snapshot_asset_insert_failed, planned.logical_id, reason}}

      {:error, reason} ->
        {:error, {:snapshot_asset_insert_failed, :batch, reason}}
    end
  end

  defp apply_relationships(%Plan{} = plan, assets, logical_id_map, source_id_map, project) do
    with :ok <- validate_unmapped_relationship_ids(plan, source_id_map),
         {:ok, updates} <- relationship_updates(plan.assets, assets, logical_id_map, source_id_map) do
      persist_relationship_updates(project, plan.assets, updates)
    end
  end

  defp relationship_updates(planned_assets, assets, logical_id_map, source_id_map) do
    assets_by_id = Map.new(assets, &{&1.id, &1})

    planned_assets
    |> Enum.reduce_while({:ok, []}, fn planned, {:ok, updates} ->
      reduce_relationship_update(planned, updates, assets_by_id, logical_id_map, source_id_map)
    end)
    |> case do
      {:ok, updates} -> {:ok, Enum.reverse(updates)}
      {:error, _reason} = error -> error
    end
  end

  defp reduce_relationship_update(planned, updates, assets_by_id, logical_id_map, source_id_map) do
    asset_id = Map.fetch!(logical_id_map, planned.logical_id)
    asset = Map.fetch!(assets_by_id, asset_id)

    case exact_restored_metadata(planned.metadata, source_id_map) do
      {:ok, metadata, lock_ids} ->
        {:cont, {:ok, [{asset, metadata, lock_ids} | updates]}}

      {:error, reason} ->
        {:halt, {:error, {:snapshot_asset_relationship_failed, planned.logical_id, reason}}}
    end
  end

  defp persist_relationship_updates(project, planned_assets, updates) do
    case Assets.update_imported_snapshot_assets_exact_locked(project, updates) do
      {:ok, updated} ->
        {:ok, updated}

      {:error, {:snapshot_asset_batch_entry_failed, index, reason}} ->
        planned = Enum.at(planned_assets, index)
        {:error, {:snapshot_asset_relationship_failed, planned.logical_id, reason}}

      {:error, reason} ->
        {:error, {:snapshot_asset_relationship_failed, :batch, reason}}
    end
  end

  defp validate_unmapped_relationship_ids(%Plan{staging_prefix: staging_prefix, assets: planned_assets}, source_id_map) do
    if workspace_snapshot_import_staging_prefix?(staging_prefix),
      do: reject_existing_unmapped_relationship_ids(planned_assets, source_id_map),
      else: :ok
  end

  defp workspace_snapshot_import_staging_prefix?(staging_prefix),
    do: Regex.match?(@workspace_snapshot_import_staging_prefix_regex, staging_prefix)

  defp reject_existing_unmapped_relationship_ids(planned_assets, source_id_map) do
    captured_ids = MapSet.new(Map.keys(source_id_map))

    unmapped_ids =
      planned_assets
      |> Enum.flat_map(&relationship_ids(&1.metadata))
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(captured_ids, &1))
      |> Enum.sort()

    case unmapped_ids do
      [] ->
        :ok

      ids ->
        existing_ids =
          Asset
          |> where([asset], asset.id in ^ids)
          |> order_by([asset], asc: asset.id)
          |> lock("FOR UPDATE")
          |> select([asset], asset.id)
          |> Repo.all()

        if existing_ids == [],
          do: :ok,
          else: {:error, {:snapshot_asset_unmapped_existing_relationship_ids, existing_ids}}
    end
  end

  defp relationship_ids(nil), do: []

  defp relationship_ids(metadata) when is_map(metadata) do
    direct = Enum.map(~w(original_asset_id web_asset_id), &Map.get(metadata, &1))

    variants =
      case Map.get(metadata, "variant_asset_ids") do
        values when is_map(values) -> Map.values(values)
        _absent_or_invalid -> []
      end

    Enum.flat_map(direct ++ variants, fn value ->
      case captured_asset_id(value) do
        {:ok, id} -> [id]
        :error -> []
      end
    end)
  end

  defp relationship_ids(_metadata), do: []

  defp exact_restored_metadata(nil, _source_id_map), do: {:ok, nil, []}

  defp exact_restored_metadata(metadata, source_id_map) when is_map(metadata) do
    {metadata, lock_ids} =
      Enum.reduce(~w(original_asset_id web_asset_id), {metadata, []}, fn key, {metadata, lock_ids} ->
        case Map.fetch(metadata, key) do
          {:ok, value} ->
            {value, remapped_ids} = remap_captured_asset_id(value, source_id_map)
            {Map.put(metadata, key, value), remapped_ids ++ lock_ids}

          :error ->
            {metadata, lock_ids}
        end
      end)

    case Map.fetch(metadata, "variant_asset_ids") do
      {:ok, variants} when is_map(variants) ->
        {variants, variant_lock_ids} =
          Enum.reduce(variants, {%{}, []}, fn {profile, value}, {variants, lock_ids} ->
            {value, remapped_ids} = remap_captured_asset_id(value, source_id_map)
            {Map.put(variants, profile, value), remapped_ids ++ lock_ids}
          end)

        {:ok, Map.put(metadata, "variant_asset_ids", variants), Enum.uniq(lock_ids ++ variant_lock_ids)}

      _absent_or_malformed ->
        {:ok, metadata, Enum.uniq(lock_ids)}
    end
  end

  defp exact_restored_metadata(_metadata, _source_id_map), do: {:error, :invalid_snapshot_asset_persisted_metadata}

  defp remap_captured_asset_id(value, source_id_map) do
    case captured_asset_id(value) do
      {:ok, source_id} ->
        case Map.fetch(source_id_map, source_id) do
          {:ok, destination_id} -> {destination_id, [destination_id]}
          :error -> {value, []}
        end

      :error ->
        {value, []}
    end
  end

  defp captured_asset_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp captured_asset_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _invalid -> :error
    end
  end

  defp captured_asset_id(_value), do: :error

  defp initial_metadata(metadata) when is_map(metadata) do
    Map.drop(metadata, ["original_asset_id", "web_asset_id", "variant_asset_ids"])
  end

  defp initial_metadata(nil), do: nil

  defp source_id_map(source_refs, logical_id_map) do
    Enum.reduce_while(source_refs, {:ok, %{}}, fn {encoded_source_id, logical_id}, {:ok, result} ->
      with {source_id, ""} <- Integer.parse(encoded_source_id),
           true <- source_id > 0,
           {:ok, destination_id} <- Map.fetch(logical_id_map, logical_id) do
        {:cont, {:ok, Map.put(result, source_id, destination_id)}}
      else
        _invalid -> {:halt, {:error, :invalid_snapshot_asset_source_refs}}
      end
    end)
  end

  defp retain_adopted_objects(plan, tracker) do
    Enum.each(plan.assets, fn asset ->
      StorageCompensation.retain_after_commit(tracker, asset.destination_key)
    end)

    Enum.each(plan.blobs, fn blob ->
      StorageCompensation.retain_after_commit(tracker, blob.destination_key)
    end)

    :ok
  end

  defp adopted_asset_matches?(asset, planned, source_id_map) do
    case exact_restored_metadata(planned.metadata, source_id_map) do
      {:ok, metadata, _lock_ids} ->
        asset.filename == planned.filename and
          asset.content_type == planned.content_type and
          asset.size == planned.size and
          asset.key == planned.destination_key and
          asset.blob_hash == planned.sha256 and
          asset.metadata == metadata

      {:error, _reason} ->
        false
    end
  end
end
