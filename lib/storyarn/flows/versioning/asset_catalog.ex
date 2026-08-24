defmodule Storyarn.Flows.Versioning.AssetCatalog do
  @moduledoc """
  Flow-owned capture and materialization of asset references in Flow snapshots.

  The shared SQL tables and storage adapters are implementation details. Flow
  snapshot semantics, validation, restore identity, and quota checks live here
  so the Flow domain does not depend on the Projects-owned asset capability.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Persistence.AssetRecord
  alias Storyarn.Flows.Persistence.ProjectRecord
  alias Storyarn.Flows.Persistence.ProjectSnapshotRecord
  alias Storyarn.Flows.Persistence.StorageReservationRecord
  alias Storyarn.Flows.Persistence.WorkspaceRecord
  alias Storyarn.Flows.Persistence.WorkspaceSnapshotImportRecord
  alias Storyarn.Flows.Versioning.AssetStorageCompensation
  alias Storyarn.Platform
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageHash
  alias Storyarn.Projects.Assets.StorageKeyLock
  alias Storyarn.Repo

  @snapshot_restore_asset_content_types ~w(
    image/jpeg image/png image/gif image/webp image/svg+xml
    audio/mpeg audio/wav audio/ogg audio/webm
    application/pdf application/octet-stream
  )
  @snapshot_materialization_cache_key {__MODULE__, :snapshot_materialization_cache}
  @max_snapshot_asset_size 52_428_800
  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @accounting_version 1
  @active_workspace_import_statuses ~w(uploading queued running retrying)

  defguardp valid_snapshot_asset_restore_request(scope, project_id, uploaded_by_id, mode, opts)
            when is_reference(scope) and is_integer(project_id) and project_id > 0 and
                   (is_nil(uploaded_by_id) or
                      (is_integer(uploaded_by_id) and uploaded_by_id > 0)) and
                   mode in [:reuse, :copy, :drop] and is_list(opts)

  @doc "Captures the portable catalog entries for a bounded set of active assets."
  @spec capture_snapshot_asset_catalog(pos_integer(), [pos_integer() | nil]) ::
          {:ok, {map(), map()}} | {:error, term()}
  def capture_snapshot_asset_catalog(project_id, asset_ids)
      when is_integer(project_id) and project_id > 0 and is_list(asset_ids) do
    with {:ok, ids} <- normalize_snapshot_catalog_ids(asset_ids),
         assets = snapshot_catalog_assets(ids),
         :ok <- validate_snapshot_catalog_assets(assets, ids, project_id),
         :ok <- ensure_snapshot_catalog_blobs(project_id, assets) do
      {:ok, snapshot_catalog_maps(assets)}
    end
  end

  def capture_snapshot_asset_catalog(_project_id, _asset_ids), do: {:error, :invalid_snapshot_asset_catalog_request}

  @doc "Runs one Flow restore under a shared storage-compensation and materialization cache."
  @spec with_snapshot_asset_restore_scope(pos_integer(), (reference() -> term())) :: term()
  def with_snapshot_asset_restore_scope(project_id, callback)
      when is_integer(project_id) and project_id > 0 and is_function(callback, 1) do
    with {:ok, workspace_id} <- project_workspace_id(project_id) do
      tracker = AssetStorageCompensation.new()

      Process.put(snapshot_materialization_cache_key(tracker), %{
        project_id: project_id,
        workspace_id: workspace_id,
        assets: %{}
      })

      try do
        tracker
        |> callback.()
        |> finalize_snapshot_restore_scope(tracker)
      rescue
        error ->
          AssetStorageCompensation.cleanup_after_rollback!(tracker)
          reraise error, __STACKTRACE__
      catch
        kind, reason ->
          AssetStorageCompensation.cleanup_after_rollback!(tracker)
          :erlang.raise(kind, reason, __STACKTRACE__)
      after
        Process.delete(snapshot_materialization_cache_key(tracker))
      end
    end
  end

  def with_snapshot_asset_restore_scope(_project_id, _callback), do: {:error, :invalid_snapshot_asset_restore_scope}

  @doc "Runs one transactional restore attempt under the scope's common workspace and project locks."
  @spec run_snapshot_asset_restore_transaction(reference(), pos_integer(), (reference() -> term())) :: term()
  def run_snapshot_asset_restore_transaction(scope, project_id, callback)
      when is_reference(scope) and is_integer(project_id) and project_id > 0 and is_function(callback, 1) do
    with {:ok, scope_state} <- snapshot_materialization_cache(scope),
         :ok <- validate_restore_scope(scope_state, project_id) do
      run_restore_scope(project_id, scope_state.workspace_id, scope, callback)
    end
  end

  def run_snapshot_asset_restore_transaction(_scope, _project_id, _callback),
    do: {:error, :invalid_snapshot_asset_restore_transaction}

  @doc "Resolves one historical asset reference inside a Flow-owned restore scope."
  @spec materialize_snapshot_asset(
          reference(),
          pos_integer() | nil,
          map(),
          pos_integer(),
          pos_integer() | nil,
          :reuse | :copy | :drop,
          keyword()
        ) :: {:ok, pos_integer() | nil} | {:error, term()}
  def materialize_snapshot_asset(scope, asset_id, catalog, project_id, uploaded_by_id, mode, opts \\ [])

  def materialize_snapshot_asset(scope, nil, _catalog, project_id, uploaded_by_id, mode, opts)
      when valid_snapshot_asset_restore_request(scope, project_id, uploaded_by_id, mode, opts), do: {:ok, nil}

  def materialize_snapshot_asset(scope, asset_id, catalog, project_id, uploaded_by_id, mode, opts)
      when is_integer(asset_id) and asset_id > 0 and is_map(catalog) and
             valid_snapshot_asset_restore_request(scope, project_id, uploaded_by_id, mode, opts) do
    with {:ok, scope_state} <- snapshot_materialization_cache(scope),
         :ok <- validate_restore_scope(scope_state, project_id) do
      do_materialize_snapshot_asset(
        scope_state.assets,
        scope,
        asset_id,
        catalog,
        project_id,
        uploaded_by_id,
        mode,
        opts
      )
    end
  end

  def materialize_snapshot_asset(_scope, _asset_id, _catalog, _project_id, _uploaded_by_id, _mode, _opts),
    do: {:error, :invalid_snapshot_asset_materialization_request}

  @doc "Performs the read-only asset checks used by Flow restore conflict previews."
  @spec validate_snapshot_asset_materialization(
          pos_integer(),
          map(),
          pos_integer(),
          keyword()
        ) :: :ok | {:error, term()}
  def validate_snapshot_asset_materialization(asset_id, catalog, project_id, opts \\ [])

  def validate_snapshot_asset_materialization(asset_id, catalog, project_id, opts)
      when is_integer(asset_id) and asset_id > 0 and is_map(catalog) and is_integer(project_id) and project_id > 0 and
             is_list(opts) do
    id = Integer.to_string(asset_id)
    hashes = Map.get(catalog, "asset_blob_hashes", %{})
    metadata_catalog = Map.get(catalog, "asset_metadata", %{})

    with true <- is_map(hashes) and is_map(metadata_catalog),
         blob_hash when is_binary(blob_hash) <- hashes[id],
         metadata when is_map(metadata) <- metadata_catalog[id],
         :ok <- validate_snapshot_asset_catalog_entry(blob_hash, metadata, project_id),
         :ok <- validate_snapshot_asset_expected_type(asset_id, metadata, opts),
         :ok <- validate_active_snapshot_asset_fingerprint(asset_id, project_id, blob_hash, metadata) do
      :ok
    else
      false -> {:error, :invalid_snapshot_asset_catalog_entry}
      nil -> {:error, :missing_snapshot_asset_catalog_entry}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_snapshot_asset_catalog_entry}
    end
  end

  def validate_snapshot_asset_materialization(_asset_id, _catalog, _project_id, _opts),
    do: {:error, :invalid_snapshot_asset_materialization_preview}

  defp run_restore_scope(project_id, workspace_id, tracker, callback) do
    fn ->
      with %WorkspaceRecord{} <- lock_workspace(workspace_id),
           {:ok, %ProjectRecord{}} <- lock_active_project(project_id, workspace_id) do
        tracker
        |> callback.()
        |> normalize_snapshot_restore_callback()
      else
        nil -> Repo.rollback(:workspace_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction(timeout: :infinity)
    |> normalize_snapshot_restore_lock_result()
  end

  defp normalize_snapshot_restore_callback({:error, _operation, reason, _changes}), do: Repo.rollback(reason)

  defp normalize_snapshot_restore_callback({:error, reason}), do: Repo.rollback(reason)

  defp normalize_snapshot_restore_callback(result), do: {:snapshot_asset_restore_result, result}

  defp normalize_snapshot_restore_lock_result({:ok, {:snapshot_asset_restore_result, result}}), do: result

  defp normalize_snapshot_restore_lock_result({:error, reason}), do: {:error, reason}

  defp finalize_snapshot_restore_scope(result, tracker) do
    cleanup_result =
      if successful_snapshot_restore_result?(result) do
        AssetStorageCompensation.cleanup_unretained(tracker)
      else
        AssetStorageCompensation.cleanup_after_rollback(tracker)
      end

    case cleanup_result do
      :ok -> result
      {:error, reason} -> {:error, {:asset_storage_cleanup_failed, result, reason}}
    end
  end

  defp successful_snapshot_restore_result?(result) when is_tuple(result) and tuple_size(result) > 0,
    do: elem(result, 0) == :ok

  defp successful_snapshot_restore_result?(_result), do: false

  defp lock_workspace(workspace_id) do
    Repo.one(
      from(workspace in WorkspaceRecord,
        where: workspace.id == ^workspace_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp project_workspace_id(project_id) do
    case Repo.one(
           from(project in ProjectRecord,
             where: project.id == ^project_id,
             select: project.workspace_id
           )
         ) do
      workspace_id when is_integer(workspace_id) and workspace_id > 0 -> {:ok, workspace_id}
      nil -> {:error, :project_not_found}
    end
  end

  defp lock_active_project(project_id, workspace_id) do
    case Repo.one(
           from(project in ProjectRecord,
             where: project.id == ^project_id and project.workspace_id == ^workspace_id,
             lock: "FOR UPDATE"
           )
         ) do
      %ProjectRecord{deleted_at: nil} = project -> {:ok, project}
      %ProjectRecord{} -> {:error, :project_not_active}
      nil -> {:error, :project_not_found}
    end
  end

  defp validate_active_snapshot_asset_fingerprint(asset_id, project_id, blob_hash, metadata) do
    case active_snapshot_asset(asset_id, project_id) do
      nil ->
        :ok

      %AssetRecord{} = asset ->
        fingerprint = %{
          blob_hash: blob_hash,
          filename: metadata["filename"],
          content_type: metadata["content_type"],
          size: metadata["size"],
          sanitized_svg: metadata["sanitized_svg"] == true
        }

        if snapshot_asset_matches?(asset, fingerprint),
          do: :ok,
          else: {:error, :existing_asset_fingerprint_mismatch}
    end
  end

  defp normalize_snapshot_catalog_ids(asset_ids) do
    invalid_ids = Enum.reject(asset_ids, &(is_nil(&1) or (is_integer(&1) and &1 > 0)))

    if invalid_ids == [] do
      {:ok,
       asset_ids
       |> Enum.reject(&is_nil/1)
       |> Enum.uniq()
       |> Enum.sort()}
    else
      {:error, {:invalid_snapshot_asset_ids, invalid_ids}}
    end
  end

  defp snapshot_catalog_assets([]), do: []

  defp snapshot_catalog_assets(asset_ids) do
    Repo.all(
      from(asset in AssetRecord,
        where: asset.id in ^asset_ids and is_nil(asset.deleted_at),
        order_by: [asc: asset.id],
        lock: "FOR SHARE"
      )
    )
  end

  defp validate_snapshot_catalog_assets(assets, asset_ids, project_id) do
    assets_by_id = Map.new(assets, &{&1.id, &1})

    with [] <- Enum.reject(asset_ids, &Map.has_key?(assets_by_id, &1)),
         [] <- Enum.reject(assets, &(&1.project_id == project_id)),
         [] <- Enum.reject(assets, &valid_snapshot_catalog_asset?/1) do
      :ok
    else
      missing_ids when is_list(missing_ids) and missing_ids != [] ->
        {:error, {:snapshot_assets_missing, missing_ids}}

      _invalid ->
        {:error, :invalid_snapshot_asset_catalog}
    end
  end

  defp valid_snapshot_catalog_asset?(asset) do
    is_binary(asset.blob_hash) and Regex.match?(@sha256_regex, asset.blob_hash) and
      is_binary(asset.filename) and String.trim(asset.filename) != "" and
      is_binary(asset.content_type) and
      snapshot_restore_content_type?(asset.content_type, asset.metadata) and
      is_integer(asset.size) and asset.size >= 0 and
      asset.size <= @max_snapshot_asset_size
  end

  defp ensure_snapshot_catalog_blobs(_project_id, []), do: :ok

  defp ensure_snapshot_catalog_blobs(project_id, assets) do
    assets
    |> Enum.group_by(& &1.blob_hash)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while(:ok, fn {_blob_hash, equivalent}, :ok ->
      ensure_snapshot_catalog_blob(project_id, equivalent)
    end)
  end

  defp ensure_snapshot_catalog_blob(project_id, equivalent) do
    with {:ok, spec} <- snapshot_blob_spec(equivalent),
         {:ok, _key, _status} <- ensure_snapshot_blob(project_id, spec, equivalent) do
      {:cont, :ok}
    else
      {:error, :conflicting_snapshot_asset_blob_metadata} = error ->
        {:halt, error}

      {:error, errors} ->
        {:halt,
         {:error,
          {:snapshot_asset_blob_unavailable,
           %{
             asset_ids: Enum.map(equivalent, & &1.id),
             blob_hash: hd(equivalent).blob_hash,
             errors: errors
           }}}}
    end
  end

  defp snapshot_blob_spec(equivalent) do
    identities =
      MapSet.new(equivalent, fn asset ->
        {asset.blob_hash, asset.size, asset.content_type, sanitized_svg_asset?(asset)}
      end)

    case MapSet.to_list(identities) do
      [{blob_hash, size, content_type, sanitized_svg}] ->
        {:ok,
         %{
           blob_hash: blob_hash,
           size: size,
           content_type: content_type,
           sanitized_svg: sanitized_svg
         }}

      _conflicting ->
        {:error, :conflicting_snapshot_asset_blob_metadata}
    end
  end

  defp ensure_snapshot_blob(project_id, spec, equivalent_assets) do
    destination_key = blob_key(project_id, spec.blob_hash, spec.content_type)

    StorageKeyLock.with_project_blob_lock(destination_key, fn ->
      case verify_storage_object(
             destination_key,
             spec.blob_hash,
             spec.size,
             spec.content_type
           ) do
        :ok ->
          {:ok, destination_key, :present}

        {:error, verification_reason} ->
          repair_snapshot_blob(
            equivalent_assets,
            destination_key,
            spec,
            verification_reason
          )
      end
    end)
  end

  defp repair_snapshot_blob(assets, destination_key, spec, verification_reason) do
    case remove_invalid_snapshot_blob(destination_key, spec) do
      :ok ->
        assets
        |> Enum.reduce_while(
          {:error, []},
          &try_snapshot_blob_candidate(&1, &2, destination_key, spec)
        )
        |> normalize_snapshot_blob_repair(verification_reason)

      {:error, reason} ->
        {:error, [{nil, reason}]}
    end
  end

  defp try_snapshot_blob_candidate(asset, {:error, errors}, destination_key, spec) do
    case copy_snapshot_blob_candidate(asset, destination_key, spec) do
      {:ok, _key, _status} = success -> {:halt, success}
      {:error, reason} -> {:cont, {:error, [{asset.id, reason} | errors]}}
    end
  end

  defp normalize_snapshot_blob_repair({:error, []}, verification_reason), do: {:error, [{nil, verification_reason}]}

  defp normalize_snapshot_blob_repair({:error, errors}, _verification_reason), do: {:error, Enum.reverse(errors)}

  defp normalize_snapshot_blob_repair(success, _verification_reason), do: success

  defp remove_invalid_snapshot_blob(destination_key, spec) do
    case Storage.stat(destination_key) do
      {:ok, stat} ->
        case verify_storage_object_from_stat(
               destination_key,
               stat,
               spec.blob_hash,
               spec.size,
               spec.content_type
             ) do
          :ok -> :ok
          {:error, _reason} -> delete_if_unchanged(destination_key, stat)
        end

      {:error, reason} ->
        if storage_object_missing?(reason), do: :ok, else: {:error, reason}

      _invalid ->
        {:error, :invalid_asset_blob_destination_stat}
    end
  end

  defp delete_if_unchanged(storage_key, stat) do
    with {:ok, identity} <- storage_object_identity(storage_key, stat) do
      case Storage.adapter().delete_if_matches(storage_key, identity) do
        :ok -> :ok
        {:error, :object_changed} -> {:error, :asset_blob_replacement_pending}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp storage_object_identity(_storage_key, %{etag: etag}) when is_binary(etag) and etag != "", do: {:ok, etag}

  defp storage_object_identity(storage_key, %{size: size} = stat) do
    stored_hash(storage_key, stat, size)
  end

  defp copy_snapshot_blob_candidate(asset, destination_key, spec) do
    with true <- valid_asset_source_key?(asset.key, asset.project_id),
         :ok <-
           verify_storage_object(
             asset.key,
             spec.blob_hash,
             spec.size,
             spec.content_type
           ),
         {:ok, created?} <- Storage.copy_if_absent(asset.key, destination_key) do
      case verify_storage_object(
             destination_key,
             spec.blob_hash,
             spec.size,
             spec.content_type
           ) do
        :ok ->
          {:ok, destination_key, :repaired}

        {:error, reason} ->
          cleanup_invalid_snapshot_blob_copy(destination_key, created?, reason)
      end
    else
      false -> {:error, :invalid_asset_blob_identity}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cleanup_invalid_snapshot_blob_copy(_destination_key, false, reason), do: {:error, reason}

  defp cleanup_invalid_snapshot_blob_copy(destination_key, true, reason) do
    case Storage.stat(destination_key) do
      {:ok, stat} ->
        case delete_if_unchanged(destination_key, stat) do
          :ok ->
            {:error, reason}

          {:error, cleanup_reason} ->
            {:error, {:asset_blob_repair_cleanup_failed, reason, cleanup_reason}}
        end

      {:error, missing_reason} ->
        if storage_object_missing?(missing_reason) do
          {:error, reason}
        else
          {:error, {:asset_blob_repair_cleanup_failed, reason, missing_reason}}
        end
    end
  end

  defp snapshot_catalog_maps(assets) do
    hashes = Map.new(assets, &{Integer.to_string(&1.id), &1.blob_hash})

    metadata =
      Map.new(assets, fn asset ->
        {Integer.to_string(asset.id), snapshot_catalog_metadata(asset)}
      end)

    {hashes, metadata}
  end

  defp snapshot_catalog_metadata(asset) do
    metadata = %{
      "filename" => asset.filename,
      "content_type" => asset.content_type,
      "size" => asset.size,
      "key" => asset.key,
      "url" => asset.url,
      "project_id" => asset.project_id,
      "blob_key" => blob_key(asset.project_id, asset.blob_hash, asset.content_type)
    }

    if sanitized_svg_asset?(asset),
      do: Map.put(metadata, "sanitized_svg", true),
      else: metadata
  end

  defp snapshot_materialization_cache_key(scope), do: {@snapshot_materialization_cache_key, scope}

  defp snapshot_materialization_cache(scope) do
    case Process.get(snapshot_materialization_cache_key(scope), :missing) do
      %{assets: assets} = state when is_map(assets) -> {:ok, state}
      :missing -> {:error, :snapshot_asset_restore_scope_not_found}
    end
  end

  defp validate_restore_scope(%{project_id: project_id, workspace_id: workspace_id}, project_id)
       when is_integer(workspace_id) and workspace_id > 0, do: :ok

  defp validate_restore_scope(_scope, _project_id), do: {:error, :snapshot_asset_restore_scope_mismatch}

  defp do_materialize_snapshot_asset(_cache, _scope, _asset_id, _catalog, _project_id, _uploaded_by_id, :drop, _opts),
    do: {:ok, nil}

  defp do_materialize_snapshot_asset(cache, scope, asset_id, catalog, project_id, uploaded_by_id, mode, opts) do
    with {:ok, entry} <- snapshot_asset_catalog_entry(asset_id, catalog, project_id, opts) do
      cached_or_materialized_snapshot_asset(
        cache,
        scope,
        asset_id,
        project_id,
        uploaded_by_id,
        mode,
        entry
      )
    end
  end

  defp snapshot_asset_catalog_entry(asset_id, catalog, project_id, opts) do
    id = Integer.to_string(asset_id)
    hashes = Map.get(catalog, "asset_blob_hashes", %{})
    metadata_catalog = Map.get(catalog, "asset_metadata", %{})

    with true <- is_map(hashes) and is_map(metadata_catalog),
         blob_hash when is_binary(blob_hash) <- hashes[id],
         metadata when is_map(metadata) <- metadata_catalog[id],
         :ok <- validate_snapshot_asset_catalog_entry(blob_hash, metadata, project_id),
         :ok <- validate_snapshot_asset_expected_type(asset_id, metadata, opts),
         source_key = blob_key(project_id, blob_hash, metadata["content_type"]),
         :ok <-
           verify_storage_object(
             source_key,
             blob_hash,
             metadata["size"],
             metadata["content_type"]
           ) do
      materialization_metadata =
        metadata
        |> Map.take(["filename", "content_type", "size"])
        |> maybe_put_snapshot_svg_metadata(metadata)

      {:ok,
       %{
         blob_hash: blob_hash,
         source_key: source_key,
         metadata: materialization_metadata,
         fingerprint: %{
           blob_hash: blob_hash,
           source_project_id: project_id,
           source_key: source_key,
           filename: metadata["filename"],
           content_type: metadata["content_type"],
           size: metadata["size"],
           sanitized_svg: metadata["sanitized_svg"] == true
         }
       }}
    else
      false -> {:error, :invalid_snapshot_asset_catalog_entry}
      nil -> {:error, :missing_snapshot_asset_catalog_entry}
      {:error, reason} -> {:error, {:snapshot_asset_blob_unavailable, reason}}
      _invalid -> {:error, :invalid_snapshot_asset_catalog_entry}
    end
  end

  defp validate_snapshot_asset_catalog_entry(blob_hash, metadata, project_id) do
    valid? =
      Enum.all?([
        Regex.match?(@sha256_regex, blob_hash),
        valid_snapshot_asset_filename?(metadata["filename"]),
        valid_snapshot_asset_content_type?(metadata["content_type"], metadata),
        valid_snapshot_asset_size?(metadata["size"]),
        metadata["project_id"] == project_id
      ])

    if valid?, do: :ok, else: {:error, :invalid_snapshot_asset_catalog_entry}
  end

  defp valid_snapshot_asset_filename?(filename) when is_binary(filename) do
    String.trim(filename) != "" and sanitize_filename(filename) not in ["", ".", ".."]
  end

  defp valid_snapshot_asset_filename?(_filename), do: false

  defp valid_snapshot_asset_content_type?(content_type, metadata) when is_binary(content_type),
    do: snapshot_restore_content_type?(content_type, metadata)

  defp valid_snapshot_asset_content_type?(_content_type, _metadata), do: false

  defp valid_snapshot_asset_size?(size), do: is_integer(size) and size >= 0 and size <= @max_snapshot_asset_size

  defp snapshot_restore_content_type?("image/svg+xml", metadata), do: metadata["sanitized_svg"] == true

  defp snapshot_restore_content_type?(content_type, _metadata), do: content_type in @snapshot_restore_asset_content_types

  defp validate_snapshot_asset_expected_type(asset_id, metadata, opts) do
    case Keyword.get(opts, :expected_content_type_prefix) do
      nil ->
        :ok

      prefix when is_binary(prefix) ->
        if String.starts_with?(metadata["content_type"], prefix) do
          :ok
        else
          {:error, {:invalid_asset_content_type, Keyword.get(opts, :asset_context), asset_id, metadata["content_type"]}}
        end

      invalid ->
        {:error, {:invalid_expected_content_type_prefix, invalid}}
    end
  end

  defp maybe_put_snapshot_svg_metadata(metadata, %{"sanitized_svg" => true}), do: Map.put(metadata, "sanitized_svg", true)

  defp maybe_put_snapshot_svg_metadata(metadata, _catalog_metadata), do: metadata

  defp cached_or_materialized_snapshot_asset(cache, scope, source_asset_id, project_id, uploaded_by_id, mode, entry) do
    identity = {project_id, source_asset_id}

    case Map.get(cache, identity) do
      %{mode: ^mode, fingerprint: fingerprint, destination_id: destination_id}
      when fingerprint == entry.fingerprint ->
        validate_cached_snapshot_asset(destination_id, project_id, entry.fingerprint)

      nil ->
        with {:ok, asset} <-
               materialize_uncached_snapshot_asset(
                 scope,
                 source_asset_id,
                 project_id,
                 uploaded_by_id,
                 mode,
                 entry
               ) do
          put_materialized_asset(scope, identity, mode, entry.fingerprint, asset.id)
          {:ok, asset.id}
        end

      cached ->
        {:error,
         {:asset_materialization_conflict,
          %{
            project_id: project_id,
            source_asset_id: source_asset_id,
            cached: cached,
            requested_mode: mode,
            requested_fingerprint: entry.fingerprint
          }}}
    end
  end

  defp put_materialized_asset(scope, identity, mode, fingerprint, destination_id) do
    {:ok, state} = snapshot_materialization_cache(scope)

    assets =
      Map.put(state.assets, identity, %{
        mode: mode,
        fingerprint: fingerprint,
        destination_id: destination_id
      })

    Process.put(snapshot_materialization_cache_key(scope), %{state | assets: assets})
  end

  defp validate_cached_snapshot_asset(asset_id, project_id, fingerprint) do
    case active_snapshot_asset(asset_id, project_id) do
      %AssetRecord{} = asset ->
        if snapshot_asset_matches?(asset, fingerprint),
          do: {:ok, asset.id},
          else: {:error, :stale_snapshot_asset_materialization}

      nil ->
        {:error, :stale_snapshot_asset_materialization}
    end
  end

  defp materialize_uncached_snapshot_asset(scope, source_asset_id, project_id, uploaded_by_id, :reuse, entry) do
    case active_snapshot_asset(source_asset_id, project_id) do
      %AssetRecord{} = asset ->
        if snapshot_asset_matches?(asset, entry.fingerprint),
          do: {:ok, asset},
          else: {:error, :existing_asset_fingerprint_mismatch}

      nil ->
        create_snapshot_asset_from_entry(scope, project_id, uploaded_by_id, entry)
    end
  end

  defp materialize_uncached_snapshot_asset(scope, _source_asset_id, project_id, uploaded_by_id, :copy, entry) do
    create_snapshot_asset_from_entry(scope, project_id, uploaded_by_id, entry)
  end

  defp create_snapshot_asset_from_entry(scope, project_id, uploaded_by_id, entry) do
    with {:ok, %{workspace_id: workspace_id}} <- snapshot_materialization_cache(scope),
         {:ok, _project} <- lock_active_project(project_id, workspace_id),
         :ok <- check_storage_capacity(workspace_id, entry.metadata["size"]) do
      create_snapshot_asset_record(scope, project_id, uploaded_by_id, entry)
    end
  end

  defp create_snapshot_asset_record(scope, project_id, uploaded_by_id, entry) do
    uuid = Ecto.UUID.generate()
    filename = entry.metadata["filename"]
    destination_key = "projects/#{project_id}/assets/#{uuid}/#{sanitize_filename(filename)}"
    now = TimeHelpers.now()

    attrs = %{
      filename: filename,
      content_type: entry.metadata["content_type"],
      size: entry.metadata["size"],
      key: destination_key,
      url: Storage.get_url(destination_key),
      metadata: Map.drop(entry.metadata, ["filename", "content_type", "size"]),
      blob_hash: entry.blob_hash
    }

    changeset =
      AssetRecord.snapshot_restore_changeset(
        %AssetRecord{project_id: project_id, uploaded_by_id: uploaded_by_id, inserted_at: now, updated_at: now},
        attrs
      )

    if changeset.valid? do
      StorageKeyLock.with_project_blob_lock(entry.source_key, fn ->
        materialize_snapshot_asset_under_key_lock(changeset, scope, entry, destination_key)
      end)
    else
      {:error, changeset}
    end
  end

  defp materialize_snapshot_asset_under_key_lock(changeset, scope, entry, destination_key) do
    StorageKeyLock.with_storage_key_lock(destination_key, fn ->
      copy_and_insert_snapshot_asset(changeset, scope, entry, destination_key)
    end)
  end

  defp copy_and_insert_snapshot_asset(changeset, scope, entry, destination_key) do
    AssetStorageCompensation.track(scope, destination_key)

    with :ok <-
           verify_storage_object(
             entry.source_key,
             entry.blob_hash,
             entry.metadata["size"],
             entry.metadata["content_type"]
           ),
         :ok <- Storage.copy(entry.source_key, destination_key),
         {:ok, asset} <- Repo.insert(changeset) do
      AssetStorageCompensation.retain_after_commit(scope, destination_key)
      {:ok, asset}
    end
  end

  defp active_snapshot_asset(asset_id, project_id) do
    query =
      from(asset in AssetRecord,
        where:
          asset.id == ^asset_id and asset.project_id == ^project_id and
            is_nil(asset.deleted_at)
      )

    query = if Repo.in_transaction?(), do: lock(query, "FOR UPDATE"), else: query
    Repo.one(query)
  end

  defp snapshot_asset_matches?(asset, fingerprint) do
    asset.blob_hash == fingerprint.blob_hash and
      asset.filename == fingerprint.filename and
      asset.content_type == fingerprint.content_type and
      asset.size == fingerprint.size and
      sanitized_svg_asset?(asset) == fingerprint.sanitized_svg
  end

  defp check_storage_capacity(workspace_id, requested_bytes) when is_integer(requested_bytes) and requested_bytes >= 0 do
    used = workspace_storage_bytes(workspace_id)
    reserved = workspace_reservation_bytes(workspace_id) + workspace_import_reservation_bytes(workspace_id)
    limit = Platform.entitlement_limit(workspace_id, :storage_bytes_per_workspace)
    available = if is_integer(limit), do: max(limit - used, 0), else: 0

    if requested_bytes <= available do
      :ok
    else
      {:error,
       {:limit_reached,
        %{
          resource: :storage_bytes_per_workspace,
          used: used,
          reserved: reserved,
          required: requested_bytes,
          available: available,
          limit: limit
        }}}
    end
  end

  defp workspace_storage_bytes(workspace_id) do
    workspace_asset_bytes(workspace_id) +
      workspace_snapshot_bytes(workspace_id) +
      workspace_reservation_bytes(workspace_id) +
      workspace_import_reservation_bytes(workspace_id)
  end

  defp workspace_asset_bytes(workspace_id) do
    Repo.one!(
      from(asset in AssetRecord,
        join: project in ProjectRecord,
        on: asset.project_id == project.id,
        where: project.workspace_id == ^workspace_id,
        select: type(coalesce(sum(asset.size), 0), :integer)
      )
    )
  end

  defp workspace_snapshot_bytes(workspace_id) do
    Repo.one!(
      from(snapshot in ProjectSnapshotRecord,
        join: project in ProjectRecord,
        on: snapshot.project_id == project.id,
        where:
          project.workspace_id == ^workspace_id and
            snapshot.lifecycle_state in ["ready", "deleting"] and
            snapshot.mode == "full" and
            snapshot.accounting_version == @accounting_version and
            not is_nil(snapshot.accounted_size_bytes),
        select: type(coalesce(sum(snapshot.accounted_size_bytes), 0), :integer)
      )
    )
  end

  defp workspace_reservation_bytes(workspace_id) do
    Repo.one!(
      from(reservation in StorageReservationRecord,
        where:
          reservation.workspace_id_snapshot == ^workspace_id and
            reservation.status == "active",
        select: type(coalesce(sum(reservation.reserved_bytes), 0), :integer)
      )
    )
  end

  defp workspace_import_reservation_bytes(workspace_id) do
    Repo.one!(
      from(snapshot_import in WorkspaceSnapshotImportRecord,
        where:
          snapshot_import.workspace_id == ^workspace_id and
            snapshot_import.status in ^@active_workspace_import_statuses,
        select: type(coalesce(sum(snapshot_import.reserved_bytes), 0), :integer)
      )
    )
  end

  defp verify_storage_object(storage_key, expected_hash, expected_size, expected_content_type) do
    with {:ok, stat} <- Storage.stat(storage_key) do
      verify_storage_object_from_stat(
        storage_key,
        stat,
        expected_hash,
        expected_size,
        expected_content_type
      )
    end
  end

  defp verify_storage_object_from_stat(storage_key, stat, expected_hash, expected_size, expected_content_type) do
    with :ok <- verify_stored_size(stat, expected_size),
         :ok <- verify_stored_content_type(stat, expected_content_type),
         {:ok, actual_hash} <- stored_hash(storage_key, stat, expected_size),
         true <- actual_hash == expected_hash do
      :ok
    else
      false -> {:error, :blob_hash_mismatch}
      {:error, _reason} = error -> error
    end
  end

  defp stored_hash(storage_key, stat, size) do
    opts = if is_binary(stat.etag) and stat.etag != "", do: [etag: stat.etag], else: []

    with {:ok, chunks} <- Storage.stream(storage_key, 0, size, opts) do
      StorageHash.sha256_chunks(chunks)
    end
  end

  defp verify_stored_size(%{size: actual_size}, expected_size) when is_integer(expected_size) and expected_size >= 0 do
    if actual_size == expected_size,
      do: :ok,
      else: {:error, {:asset_blob_size_mismatch, expected_size, actual_size}}
  end

  defp verify_stored_size(_stat, _expected_size), do: {:error, :invalid_asset_blob_size}

  defp verify_stored_content_type(%{content_type: actual}, expected) do
    if compatible_content_type?(actual, expected),
      do: :ok,
      else: {:error, {:asset_blob_content_type_mismatch, expected, actual}}
  end

  defp verify_stored_content_type(_stat, expected), do: {:error, {:asset_blob_content_type_mismatch, expected, nil}}

  defp compatible_content_type?(actual, expected) when is_binary(actual) and actual != "" and actual == expected, do: true

  defp compatible_content_type?("application/octet-stream", "audio/ogg"), do: true
  defp compatible_content_type?("video/webm", "audio/webm"), do: true
  defp compatible_content_type?(_actual, _expected), do: false

  defp storage_object_missing?(:enoent), do: true
  defp storage_object_missing?({:http_error, 404, _response}), do: true
  defp storage_object_missing?(_reason), do: false

  defp valid_asset_source_key?(source_key, project_id) do
    expected_project_id = Integer.to_string(project_id)

    case String.split(source_key, "/", trim: false) do
      ["projects", ^expected_project_id, "assets", asset_uuid, filename] ->
        Storage.canonical_key?(source_key) and
          match?({:ok, _uuid}, Ecto.UUID.cast(asset_uuid)) and
          filename not in ["", ".", "..", ".storyarn-copy"]

      _other ->
        false
    end
  end

  defp blob_key(project_id, hash, content_type) do
    "projects/#{project_id}/blobs/#{hash}.#{extension_for(content_type)}"
  end

  defp extension_for("image/jpeg"), do: "jpg"
  defp extension_for("image/png"), do: "png"
  defp extension_for("image/gif"), do: "gif"
  defp extension_for("image/webp"), do: "webp"
  defp extension_for("image/svg+xml"), do: "svg"
  defp extension_for("audio/mpeg"), do: "mp3"
  defp extension_for("audio/wav"), do: "wav"
  defp extension_for("audio/ogg"), do: "ogg"
  defp extension_for("audio/webm"), do: "webm"
  defp extension_for("application/pdf"), do: "pdf"
  defp extension_for("application/octet-stream"), do: "bin"

  defp extension_for(content_type) do
    content_type
    |> String.split("/")
    |> List.last()
    |> String.split("+")
    |> List.first()
  end

  defp sanitize_filename(filename) do
    sanitized =
      filename
      |> String.split(~r/[\/\\]/)
      |> List.last()
      |> String.replace(~r/[^\w\.\-]/, "_")
      |> String.downcase()
      |> String.slice(0, 255)

    case sanitized do
      value when value in ["", ".", ".."] -> "file"
      ".storyarn-copy" -> "_storyarn-copy"
      value -> value
    end
  end

  defp sanitized_svg_asset?(%AssetRecord{content_type: "image/svg+xml", metadata: %{"sanitized_svg" => true}}), do: true

  defp sanitized_svg_asset?(%AssetRecord{}), do: false
end
