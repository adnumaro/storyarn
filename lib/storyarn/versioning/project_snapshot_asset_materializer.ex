defmodule Storyarn.Versioning.ProjectSnapshotAssetMaterializer do
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

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Assets.StorageHash
  alias Storyarn.Assets.StorageKeyLock
  alias Storyarn.Billing
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.SnapshotObjectFormat

  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @logical_id_regex ~r/\Aasset-[0-9]{6}\z/

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
         {:ok, planned_assets} <- plan_assets(project_id, restore_identity, assets, staging_keys) do
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
      with :ok <- stage_protected_blobs(plan.blobs, tracker) do
        stage_logical_assets(plan.assets, tracker)
      end
    end
  end

  def stage_destination_objects(_plan, _tracker), do: {:error, :invalid_snapshot_asset_staging_request}

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
      not Billing.workspace_lock_held?(project.workspace_id) -> {:error, :storage_accounting_lock_required}
      true -> :ok
    end
  end

  defp adopt_catalog_locked(plan, project, actor_id, tracker) do
    with {:ok, assets, logical_id_map} <- insert_assets(plan.assets, project, actor_id),
         {:ok, assets} <- apply_relationships(plan.assets, assets, logical_id_map, project),
         {:ok, source_id_map} <- source_id_map(plan.source_refs, logical_id_map),
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

    if MapSet.new(Map.keys(assets_by_id)) == expected_ids do
      verify_planned_assets(plan.assets, assets_by_id, logical_id_map)
    else
      {:error, :snapshot_asset_inventory_mismatch}
    end
  end

  def verify_adopted_locked(_plan, _logical_id_map), do: {:error, :invalid_snapshot_asset_verification}

  defp verify_planned_assets(planned_assets, assets_by_id, logical_id_map) do
    Enum.reduce_while(planned_assets, :ok, fn planned, :ok ->
      case verified_planned_asset(planned, assets_by_id, logical_id_map) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp verified_planned_asset(planned, assets_by_id, logical_id_map) do
    asset_id = logical_id_map[planned.logical_id]

    case Map.fetch(assets_by_id, asset_id) do
      {:ok, asset} ->
        if adopted_asset_matches?(asset, planned, logical_id_map),
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
    expected = Map.new(blobs, &{&1["path"], staging_prefix <> "/" <> &1["path"]})

    if staging_prefix_valid?(staging_prefix) and staging_keys == expected and
         Enum.all?(Map.values(staging_keys), &Storage.canonical_key?/1) do
      :ok
    else
      {:error, :snapshot_staging_inventory_mismatch}
    end
  end

  defp staging_prefix_valid?(prefix) do
    Storage.canonical_key?(prefix) and
      not String.ends_with?(prefix, "/") and
      String.contains?(prefix, "/storage-reservations/v1/restore-staging/")
  end

  defp plan_assets(project_id, restore_identity, assets, staging_keys) do
    assets
    |> Enum.reduce_while({:ok, []}, fn asset, {:ok, planned} ->
      with {:ok, logical_id} <- logical_id(asset),
           {:ok, uuid} <- deterministic_uuid(restore_identity, logical_id),
           {:ok, source_key} <- Map.fetch(staging_keys, asset["blob_path"]) do
        destination_key =
          "projects/#{project_id}/assets/#{uuid}/#{Assets.sanitize_filename(asset["filename"])}"

        entry = %{
          logical_id: logical_id,
          filename: asset["filename"],
          content_type: asset["content_type"],
          size: asset["size_bytes"],
          sha256: asset["sha256"],
          metadata: asset["metadata"],
          relationships: asset["relationships"],
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

  defp stage_protected_blobs(blobs, tracker) do
    Enum.reduce_while(blobs, :ok, fn blob, :ok ->
      case stage_protected_blob(blob, tracker) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, {:snapshot_blob_staging_failed, blob.path, reason}}}
      end
    end)
  end

  defp stage_protected_blob(blob, tracker) do
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

  defp stage_logical_assets(assets, tracker) do
    Enum.reduce_while(assets, :ok, fn asset, :ok ->
      case stage_logical_asset(asset, tracker) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:snapshot_asset_staging_failed, asset.logical_id, reason}}}
      end
    end)
  end

  defp stage_logical_asset(asset, tracker) do
    with :ok <- verify_object(asset.source_key, asset.size, asset.sha256) do
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
             asset.size,
             asset.content_type
           ),
         :ok <- StorageCompensation.track_force_delete(tracker, asset.destination_key),
         :ok <- verify_object(asset.destination_key, asset.size, asset.sha256) do
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
       when is_integer(expected_size) and expected_size > 0 and is_binary(expected_sha256) do
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
          metadata: planned.metadata,
          blob_hash: planned.sha256
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

  defp apply_relationships(planned_assets, assets, logical_id_map, project) do
    assets_by_id = Map.new(assets, &{&1.id, &1})

    planned_assets
    |> Enum.reduce_while({:ok, []}, fn planned, {:ok, updates} ->
      asset_id = Map.fetch!(logical_id_map, planned.logical_id)
      asset = Map.fetch!(assets_by_id, asset_id)

      case relationship_metadata(planned.relationships, logical_id_map) do
        {:ok, relationship_metadata} ->
          metadata = Map.merge(planned.metadata, relationship_metadata)
          {:cont, {:ok, [{asset, metadata} | updates]}}

        {:error, reason} ->
          {:halt, {:error, {:snapshot_asset_relationship_failed, planned.logical_id, reason}}}
      end
    end)
    |> case do
      {:ok, updates} ->
        updates = Enum.reverse(updates)

        case Assets.update_imported_snapshot_assets_locked(project, updates) do
          {:ok, updated} ->
            {:ok, updated}

          {:error, {:snapshot_asset_batch_entry_failed, index, reason}} ->
            planned = Enum.at(planned_assets, index)
            {:error, {:snapshot_asset_relationship_failed, planned.logical_id, reason}}

          {:error, reason} ->
            {:error, {:snapshot_asset_relationship_failed, :batch, reason}}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp relationship_metadata(%{"original" => original, "web" => web, "variants" => variants}, id_map)
       when is_map(variants) do
    with {:ok, original_id} <- relationship_id(original, id_map),
         {:ok, web_id} <- relationship_id(web, id_map),
         {:ok, variant_ids} <- relationship_ids(variants, id_map) do
      {:ok,
       %{
         "original_asset_id" => original_id,
         "web_asset_id" => web_id,
         "variant_asset_ids" => variant_ids
       }}
    end
  end

  defp relationship_metadata(_relationships, _id_map), do: {:error, :invalid_snapshot_asset_relationships}

  defp relationship_id(nil, _id_map), do: {:ok, nil}

  defp relationship_id(logical_id, id_map) when is_binary(logical_id) do
    case Map.fetch(id_map, logical_id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, {:missing_snapshot_asset_relationship, logical_id}}
    end
  end

  defp relationship_id(value, _id_map), do: {:error, {:invalid_snapshot_asset_relationship, value}}

  defp relationship_ids(variants, id_map) do
    Enum.reduce_while(variants, {:ok, %{}}, fn {profile, logical_id}, {:ok, ids} ->
      case relationship_id(logical_id, id_map) do
        {:ok, id} -> {:cont, {:ok, Map.put(ids, profile, id)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

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

  defp adopted_asset_matches?(asset, planned, logical_id_map) do
    case relationship_metadata(planned.relationships, logical_id_map) do
      {:ok, relationship_metadata} ->
        asset.filename == planned.filename and
          asset.content_type == planned.content_type and
          asset.size == planned.size and
          asset.key == planned.destination_key and
          asset.blob_hash == planned.sha256 and
          asset.metadata == Map.merge(planned.metadata, relationship_metadata)

      {:error, _reason} ->
        false
    end
  end
end
