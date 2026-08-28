defmodule Storyarn.Projects.Assets.BlobStore do
  @moduledoc """
  Content-addressable blob storage for versioning.

  Assets are stored by SHA256 hash so that snapshots can reference them by
  content rather than database ID. If an asset is deleted, snapshots can
  still restore it from the blob.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageCompensation
  alias Storyarn.Projects.Assets.StorageHash
  alias Storyarn.Projects.Assets.StorageKeyLock
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  require Logger

  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  @doc """
  Generates the storage key for a blob.

  Format: `projects/{project_id}/blobs/{sha256}.{ext}`
  """
  @spec blob_key(integer(), String.t(), String.t()) :: String.t()
  def blob_key(project_id, hash, ext) do
    "projects/#{project_id}/blobs/#{hash}.#{ext}"
  end

  @doc """
  Computes the SHA256 hash of binary data.

  Returns a lowercase hex-encoded string (64 chars).
  """
  @spec compute_hash(binary()) :: String.t()
  def compute_hash(binary_data) do
    :sha256 |> :crypto.hash(binary_data) |> Base.encode16(case: :lower)
  end

  @doc """
  Extracts a file extension from a MIME content type.
  """
  @spec ext_from_content_type(String.t()) :: String.t()
  def ext_from_content_type("image/jpeg"), do: "jpg"
  def ext_from_content_type("image/png"), do: "png"
  def ext_from_content_type("image/gif"), do: "gif"
  def ext_from_content_type("image/webp"), do: "webp"
  def ext_from_content_type("image/svg+xml"), do: "svg"
  def ext_from_content_type("audio/mpeg"), do: "mp3"
  def ext_from_content_type("audio/wav"), do: "wav"
  def ext_from_content_type("audio/ogg"), do: "ogg"
  def ext_from_content_type("audio/webm"), do: "webm"
  def ext_from_content_type("application/pdf"), do: "pdf"
  def ext_from_content_type("application/octet-stream"), do: "bin"

  def ext_from_content_type(other) do
    other |> String.split("/") |> List.last() |> String.split("+") |> List.first()
  end

  @doc """
  Returns whether provider metadata is compatible with the canonical asset
  content type.

  The non-identical pairs preserve historical blobs whose content type was
  inferred from their v1 path extension instead of the original upload
  metadata. Bytes are still verified independently by SHA-256.
  """
  @spec compatible_content_type?(term(), term()) :: boolean()
  def compatible_content_type?(actual, expected) when is_binary(actual) and actual != "" and actual == expected, do: true

  def compatible_content_type?("application/octet-stream", "audio/ogg"), do: true
  def compatible_content_type?("video/webm", "audio/webm"), do: true
  def compatible_content_type?(_actual, _expected), do: false

  @doc """
  Uploads a blob if not already present. Idempotent.

  Returns `{:ok, blob_key}` on success.
  """
  @spec ensure_blob(integer(), String.t(), String.t(), binary()) ::
          {:ok, String.t()} | {:error, term()}
  def ensure_blob(project_id, hash, ext, binary_data) do
    case ensure_blob_with_status(project_id, hash, ext, binary_data) do
      {:ok, key, _created?} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Uploads a blob if needed and reports whether this call created it."
  @spec ensure_blob_with_status(integer(), String.t(), String.t(), binary()) ::
          {:ok, String.t(), boolean()} | {:error, term()}
  def ensure_blob_with_status(project_id, hash, ext, binary_data) do
    ensure_blob_with_status(project_id, hash, ext, binary_data, default_blob_content_type(ext))
  end

  @doc "Uploads a blob with explicit provider metadata and reports ownership."
  @spec ensure_blob_with_status(integer(), String.t(), String.t(), binary(), String.t()) ::
          {:ok, String.t(), boolean()} | {:error, term()}
  def ensure_blob_with_status(project_id, hash, ext, binary_data, content_type)
      when is_binary(content_type) and content_type != "" do
    key = blob_key(project_id, hash, ext)

    StorageKeyLock.with_project_blob_lock(key, fn ->
      do_ensure_blob_with_status(key, hash, binary_data, content_type)
    end)
  end

  def ensure_blob_with_status(_project_id, _hash, _ext, _binary_data, _content_type),
    do: {:error, :invalid_blob_content_type}

  @doc """
  Ensures that an existing asset has its project-scoped canonical blob.

  Canonical blobs are immutable recovery substrate. When the destination is
  absent or verified corrupt, this verifies the asset's original object by
  size, content type, and SHA-256 before copying it under the canonical
  project-blob lock. A corrupt destination is removed only while the same lock
  is held and only while its provider identity still matches the object that
  failed verification.
  """
  @spec ensure_asset_blob(Asset.t()) ::
          {:ok, String.t(), :present | :repaired} | {:error, term()}
  def ensure_asset_blob(
        %Asset{project_id: project_id, blob_hash: blob_hash, content_type: content_type, size: size, key: source_key} =
          asset
      )
      when is_integer(project_id) and project_id > 0 and is_binary(blob_hash) and is_binary(content_type) and
             content_type != "" and is_integer(size) and size > 0 and is_binary(source_key) do
    extension = ext_from_content_type(content_type)
    destination_key = blob_key(project_id, blob_hash, extension)

    with true <- Regex.match?(@sha256_regex, blob_hash),
         true <- valid_asset_content_type?(asset),
         true <- Storage.canonical_key?(destination_key) do
      tracker = StorageCompensation.new()
      opts = [asset_copy_tracker: tracker]

      result =
        StorageKeyLock.with_project_blob_lock(destination_key, fn ->
          ensure_asset_blob_under_lock(
            source_key,
            destination_key,
            blob_hash,
            size,
            content_type,
            Keyword.put(opts, :source_project_id, project_id)
          )
        end)

      finalize_asset_blob_repair(result, tracker)
    else
      false -> {:error, :invalid_asset_blob_identity}
    end
  end

  def ensure_asset_blob(%Asset{}), do: {:error, :invalid_asset_blob_identity}

  def ensure_asset_blob(_asset), do: {:error, :invalid_asset}

  @doc false
  @spec verify_asset_blob(pos_integer(), String.t(), pos_integer(), String.t(), keyword()) ::
          {:ok, String.t(), :present} | {:error, term()}
  def verify_asset_blob(project_id, blob_hash, size, content_type, opts \\ [])

  def verify_asset_blob(project_id, blob_hash, size, content_type, opts)
      when is_integer(project_id) and project_id > 0 and is_binary(blob_hash) and is_integer(size) and size > 0 and
             is_binary(content_type) and content_type != "" and is_list(opts) do
    destination_key = blob_key(project_id, blob_hash, ext_from_content_type(content_type))

    verify_asset_blob_identity(destination_key, blob_hash, size, content_type, opts)
  end

  def verify_asset_blob(_project_id, _blob_hash, _size, _content_type, _opts), do: {:error, :invalid_asset_blob_identity}

  defp verify_asset_blob_identity(destination_key, blob_hash, size, content_type, opts) do
    with true <- Regex.match?(@sha256_regex, blob_hash),
         true <- valid_snapshot_blob_content_type?(content_type, opts),
         true <- Storage.canonical_key?(destination_key) do
      StorageKeyLock.with_project_blob_lock(destination_key, fn ->
        destination_key
        |> Storage.stat()
        |> verify_asset_blob_stat(destination_key, blob_hash, size, content_type)
      end)
    else
      false -> {:error, :invalid_asset_blob_identity}
    end
  end

  defp verify_asset_blob_stat({:ok, stat}, destination_key, blob_hash, size, content_type) do
    case verify_stored_asset_blob(destination_key, stat, blob_hash, size, content_type) do
      :ok -> {:ok, destination_key, :present}
      {:error, _reason} = error -> error
    end
  end

  defp verify_asset_blob_stat({:error, reason}, destination_key, _blob_hash, _size, _content_type) do
    if storage_object_missing?(reason),
      do: {:error, {:asset_blob_destination_missing, destination_key}},
      else: {:error, {:asset_blob_destination_stat_failed, reason}}
  end

  defp verify_asset_blob_stat(_invalid, _destination_key, _blob_hash, _size, _content_type),
    do: {:error, :invalid_asset_blob_destination_stat}

  defp ensure_asset_blob_under_lock(source_key, destination_key, blob_hash, size, content_type, opts) do
    destination_key
    |> Storage.stat()
    |> ensure_asset_blob_from_stat(source_key, destination_key, blob_hash, size, content_type, opts)
  end

  defp ensure_asset_blob_from_stat({:ok, stat}, source_key, destination_key, blob_hash, size, content_type, opts) do
    destination_key
    |> verify_stored_asset_blob(stat, blob_hash, size, content_type)
    |> ensure_existing_asset_blob(source_key, destination_key, blob_hash, size, content_type, stat, opts)
  end

  defp ensure_asset_blob_from_stat({:error, reason}, source_key, destination_key, blob_hash, size, content_type, opts) do
    if storage_object_missing?(reason),
      do: repair_asset_blob(source_key, destination_key, blob_hash, size, content_type, opts),
      else: {:error, {:asset_blob_destination_stat_failed, reason}}
  end

  defp ensure_asset_blob_from_stat(_invalid, _source_key, _destination_key, _blob_hash, _size, _content_type, _opts),
    do: {:error, :invalid_asset_blob_destination_stat}

  defp ensure_existing_asset_blob(:ok, _source_key, destination_key, _blob_hash, _size, _content_type, _stat, _opts),
    do: {:ok, destination_key, :present}

  defp ensure_existing_asset_blob(
         {:error, reason} = error,
         source_key,
         destination_key,
         blob_hash,
         size,
         content_type,
         stat,
         opts
       ) do
    if verified_asset_blob_corruption?(reason),
      do: replace_asset_blob(source_key, destination_key, blob_hash, size, content_type, stat, reason, opts),
      else: error
  end

  defp repair_asset_blob(source_key, destination_key, blob_hash, size, content_type, opts) do
    with {:ok, source_project_id} <- asset_blob_source_project_id(opts),
         true <- valid_asset_source_key?(source_key, source_project_id),
         :ok <- verify_asset_blob_source(source_key, blob_hash, size, content_type) do
      copy_verified_asset_blob(source_key, destination_key, blob_hash, size, content_type, opts)
    else
      false -> {:error, :invalid_asset_blob_identity}
      {:error, _reason} = error -> error
    end
  end

  defp replace_asset_blob(
         source_key,
         destination_key,
         blob_hash,
         size,
         content_type,
         invalid_stat,
         corruption_reason,
         opts
       ) do
    with {:ok, source_project_id} <- asset_blob_source_project_id(opts),
         true <- valid_asset_source_key?(source_key, source_project_id),
         :ok <- verify_asset_blob_source(source_key, blob_hash, size, content_type),
         :ok <- remove_verified_invalid_blob(destination_key, blob_hash, invalid_stat, corruption_reason, opts) do
      copy_verified_asset_blob(source_key, destination_key, blob_hash, size, content_type, opts)
    else
      false -> {:error, :invalid_asset_blob_identity}
      {:error, _reason} = error -> error
    end
  end

  defp asset_blob_source_project_id(opts) do
    case Keyword.fetch(opts, :source_project_id) do
      {:ok, project_id} when is_integer(project_id) and project_id > 0 -> {:ok, project_id}
      _missing_or_invalid -> {:error, :invalid_asset_blob_identity}
    end
  end

  defp copy_verified_asset_blob(source_key, destination_key, blob_hash, size, content_type, opts) do
    with {:ok, ^destination_key, created?} <-
           copy_verified_blob_if_absent(source_key, destination_key, blob_hash, size, opts),
         :ok <- verify_asset_blob_content_type(destination_key, content_type) do
      status = if created?, do: :repaired, else: :present
      {:ok, destination_key, status}
    else
      {:error, {:asset_blob_content_type_mismatch, _expected, _actual}} ->
        compensate_invalid_blob(opts, destination_key)
        {:error, :asset_blob_replacement_pending}

      {:error, _reason} ->
        {:error, :asset_blob_replacement_pending}
    end
  end

  defp remove_verified_invalid_blob(
         destination_key,
         blob_hash,
         invalid_stat,
         {:asset_blob_content_type_mismatch, _expected, _actual},
         opts
       ) do
    case verify_stored_blob(destination_key, invalid_stat, blob_hash) do
      :ok -> delete_content_type_invalid_blob(destination_key, blob_hash, invalid_stat)
      {:error, :blob_hash_mismatch} -> force_delete_invalid_blob(destination_key, opts)
      {:error, _reason} -> {:error, :asset_blob_replacement_pending}
    end
  end

  defp remove_verified_invalid_blob(destination_key, _blob_hash, _invalid_stat, _corruption_reason, opts) do
    force_delete_invalid_blob(destination_key, opts)
  end

  defp force_delete_invalid_blob(destination_key, opts) do
    case Keyword.get(opts, :asset_copy_tracker) do
      tracker when is_reference(tracker) ->
        case StorageCompensation.delete_force_tracked_or_enqueue(tracker, destination_key) do
          :ok -> :ok
          {:error, _reason} -> {:error, :asset_blob_replacement_pending}
        end

      _invalid ->
        raise "asset copy storage tracker is not initialized"
    end
  end

  defp delete_content_type_invalid_blob(destination_key, blob_hash, invalid_stat) do
    identity = invalid_blob_identity(invalid_stat, blob_hash)
    result = Storage.delete_if_matches(destination_key, identity)

    handle_content_type_invalid_blob_delete(result, destination_key, blob_hash)
  end

  defp invalid_blob_identity(%{etag: etag}, _blob_hash) when is_binary(etag) and etag != "", do: etag
  defp invalid_blob_identity(_invalid_stat, blob_hash), do: blob_hash

  defp handle_content_type_invalid_blob_delete(:ok, _destination_key, _blob_hash), do: :ok

  defp handle_content_type_invalid_blob_delete({:error, :object_changed}, destination_key, blob_hash),
    do: recheck_content_type_invalid_blob(destination_key, blob_hash)

  defp handle_content_type_invalid_blob_delete({:error, _reason}, _destination_key, _blob_hash),
    do: {:error, :asset_blob_replacement_pending}

  defp recheck_content_type_invalid_blob(destination_key, blob_hash) do
    case Storage.stat(destination_key) do
      {:ok, current_stat} ->
        _verification = verify_stored_blob(destination_key, current_stat, blob_hash)
        {:error, :asset_blob_replacement_pending}

      {:error, reason} ->
        if storage_object_missing?(reason), do: :ok, else: {:error, :asset_blob_replacement_pending}

      _invalid ->
        {:error, :asset_blob_replacement_pending}
    end
  end

  defp verify_asset_blob_source(source_key, blob_hash, size, content_type) do
    case verify_stored_asset_blob(source_key, blob_hash, size, content_type) do
      {:error, reason} when reason == :enoent -> {:error, {:asset_blob_source_missing, source_key}}
      {:error, {:http_error, 404, _response}} -> {:error, {:asset_blob_source_missing, source_key}}
      result -> result
    end
  end

  defp verify_stored_asset_blob(storage_key, expected_hash, expected_size, expected_content_type) do
    with {:ok, stat} <- Storage.stat(storage_key) do
      verify_stored_asset_blob(storage_key, stat, expected_hash, expected_size, expected_content_type)
    end
  end

  defp verify_stored_asset_blob(storage_key, stat, expected_hash, expected_size, expected_content_type) do
    with :ok <- verify_stored_blob_size(stat, expected_size),
         :ok <- verify_asset_blob_content_type(stat, expected_content_type) do
      verify_stored_blob(storage_key, stat, expected_hash)
    end
  end

  defp verified_asset_blob_corruption?(:blob_hash_mismatch), do: true
  defp verified_asset_blob_corruption?({:asset_blob_size_mismatch, _expected, _actual}), do: true
  defp verified_asset_blob_corruption?({:asset_blob_content_type_mismatch, _expected, _actual}), do: true
  defp verified_asset_blob_corruption?(_reason), do: false

  defp verify_asset_blob_content_type(storage_key, expected_content_type) when is_binary(storage_key) do
    with {:ok, stat} <- Storage.stat(storage_key) do
      verify_asset_blob_content_type(stat, expected_content_type)
    end
  end

  defp verify_asset_blob_content_type(%{content_type: actual_content_type}, expected_content_type) do
    if compatible_content_type?(actual_content_type, expected_content_type),
      do: :ok,
      else: {:error, {:asset_blob_content_type_mismatch, expected_content_type, actual_content_type}}
  end

  defp verify_asset_blob_content_type(_stat, expected_content_type),
    do: {:error, {:asset_blob_content_type_mismatch, expected_content_type, nil}}

  defp finalize_asset_blob_repair({:ok, _key, _status} = result, tracker) do
    :ok = StorageCompensation.discard(tracker)
    result
  end

  defp finalize_asset_blob_repair({:error, reason} = error, tracker) do
    case StorageCompensation.cleanup_after_rollback(tracker) do
      :ok -> error
      {:error, cleanup_reason} -> {:error, {:asset_blob_repair_cleanup_failed, reason, cleanup_reason}}
    end
  end

  defp valid_asset_source_key?(source_key, project_id) do
    expected_project_id = Integer.to_string(project_id)

    case String.split(source_key, "/", trim: false) do
      ["projects", ^expected_project_id, "assets", asset_uuid, filename] ->
        Storage.canonical_key?(source_key) and match?({:ok, _uuid}, Ecto.UUID.cast(asset_uuid)) and
          filename not in ["", ".", "..", ".storyarn-copy"]

      _other ->
        false
    end
  end

  defp valid_asset_content_type?(%Asset{content_type: "image/svg+xml", metadata: %{"sanitized_svg" => true}}), do: true

  defp valid_asset_content_type?(%Asset{content_type: content_type}), do: Asset.allowed_content_type?(content_type)

  defp valid_snapshot_blob_content_type?("image/svg+xml", opts), do: Keyword.get(opts, :sanitized_svg, false) == true

  defp valid_snapshot_blob_content_type?(content_type, opts),
    do: Keyword.get(opts, :sanitized_svg, false) == false and Asset.allowed_content_type?(content_type)

  defp storage_object_missing?(:enoent), do: true
  defp storage_object_missing?({:http_error, 404, _response}), do: true
  defp storage_object_missing?(_reason), do: false

  defp default_blob_content_type("ogg"), do: "audio/ogg"
  defp default_blob_content_type("webm"), do: "audio/webm"
  defp default_blob_content_type(ext), do: MIME.type(ext)

  defp do_ensure_blob_with_status(key, hash, binary_data, content_type) do
    if compute_hash(binary_data) == hash do
      put_blob_if_absent(key, hash, binary_data, content_type)
    else
      {:error, :blob_hash_mismatch}
    end
  end

  defp put_blob_if_absent(key, hash, binary_data, content_type) do
    case Storage.put_if_absent(key, binary_data, content_type) do
      {:ok, _url, true} -> {:ok, key, true}
      {:ok, _url, false} -> verify_existing_blob(key, hash)
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_existing_blob(key, hash) do
    case verify_stored_blob(key, hash) do
      :ok -> {:ok, key, false}
      {:error, :blob_hash_mismatch} -> {:error, {:invalid_existing_blob, key, :blob_hash_mismatch}}
      {:error, reason} -> {:error, {:existing_blob_verification_failed, key, reason}}
    end
  end

  @doc """
  Creates a new Asset record from a blob for restoring deleted assets.

  Verifies the source content, materializes the content-addressed blob in the
  destination project, and populates a new asset with a fresh storage key while
  preserving the original metadata (filename, content_type, size).
  """
  @spec create_asset_from_blob(integer(), integer() | nil, String.t(), String.t(), map(), keyword()) ::
          {:ok, Asset.t()} | {:error, term()}
  def create_asset_from_blob(project_id, user_id, blob_hash, source_key, metadata, opts \\ []) do
    caller_transactional? = Repo.in_transaction?()

    with {:ok, workspace_id} <- project_workspace_id(project_id),
         :ok <- require_workspace_lock_for_transaction(workspace_id, caller_transactional?),
         {:ok, tracker, owns_tracker?} <- asset_copy_tracker(opts, caller_transactional?) do
      opts = Keyword.put(opts, :asset_copy_tracker, tracker)

      try do
        workspace_id
        |> materialize_under_storage_lock(project_id, user_id, blob_hash, source_key, metadata, opts)
        |> finalize_owned_asset_copies(tracker, owns_tracker?)
      rescue
        error ->
          cleanup_owned_asset_copies(tracker, owns_tracker?)
          reraise error, __STACKTRACE__
      catch
        kind, reason ->
          cleanup_owned_asset_copies(tracker, owns_tracker?)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end
    end
  end

  defp require_workspace_lock_for_transaction(workspace_id, true) do
    if Platform.workspace_lock_held?(workspace_id),
      do: :ok,
      else: {:error, :asset_materialization_requires_workspace_lock}
  end

  defp require_workspace_lock_for_transaction(_workspace_id, false), do: :ok

  defp materialize_under_storage_lock(workspace_id, project_id, user_id, blob_hash, source_key, metadata, opts) do
    workspace_id
    |> Platform.with_storage_accounting_lock(fn workspace ->
      with {:ok, _project} <- lock_active_project(project_id, workspace_id),
           :ok <- Platform.can_upload_asset?(workspace, metadata["size"]) do
        do_create_asset_from_blob(project_id, user_id, blob_hash, source_key, metadata, opts)
      else
        {:error, :limit_reached, details} -> {:error, {:limit_reached, details}}
        {:error, _reason} = error -> error
      end
    end)
    |> unwrap_storage_lock_result()
  end

  defp unwrap_storage_lock_result({:ok, result}), do: result
  defp unwrap_storage_lock_result({:error, reason}), do: {:error, reason}

  defp project_workspace_id(project_id) when is_integer(project_id) and project_id > 0 do
    case Repo.one(from(project in Project, where: project.id == ^project_id, select: project.workspace_id)) do
      workspace_id when is_integer(workspace_id) -> {:ok, workspace_id}
      nil -> {:error, :project_not_found}
    end
  end

  defp project_workspace_id(_project_id), do: {:error, :project_not_found}

  defp lock_active_project(project_id, workspace_id) do
    case Repo.one(
           from(project in Project,
             where: project.id == ^project_id and project.workspace_id == ^workspace_id,
             lock: "FOR UPDATE"
           )
         ) do
      %Project{deleted_at: nil} = project -> {:ok, project}
      %Project{} -> {:error, :project_not_active}
      nil -> {:error, :project_not_found}
    end
  end

  defp do_create_asset_from_blob(project_id, user_id, blob_hash, source_key, metadata, opts) do
    ext = ext_from_content_type(metadata["content_type"])
    source_key = source_key || blob_key(project_id, blob_hash, ext)

    uuid = Ecto.UUID.generate()
    filename = metadata["filename"]
    sanitized = Storyarn.Projects.Assets.sanitize_filename(filename)
    dest_key = "projects/#{project_id}/assets/#{uuid}/#{sanitized}"

    now = TimeHelpers.now()

    attrs = %{
      filename: filename,
      content_type: metadata["content_type"],
      size: metadata["size"],
      key: dest_key,
      url: Storage.get_url(dest_key),
      metadata: Map.drop(metadata, ["filename", "content_type", "size", "key", "url", "project_id", "blob_key"]),
      blob_hash: blob_hash
    }

    asset = %Asset{
      project_id: project_id,
      uploaded_by_id: user_id,
      inserted_at: now,
      updated_at: now
    }

    changeset = restore_changeset(asset, attrs)

    if changeset.valid? do
      project_id
      |> blob_key(blob_hash, ext)
      |> StorageKeyLock.with_project_blob_lock(fn ->
        materialize_and_insert_asset(
          changeset,
          project_id,
          blob_hash,
          metadata["size"],
          ext,
          source_key,
          dest_key,
          opts
        )
      end)
    else
      {:error, changeset}
    end
  end

  defp asset_copy_tracker(opts, caller_transactional?) do
    case Keyword.get(opts, :asset_copy_tracker) do
      tracker when is_reference(tracker) ->
        {:ok, tracker, false}

      _tracker ->
        if caller_transactional?,
          do: {:error, :asset_copy_tracker_required_in_transaction},
          else: {:ok, StorageCompensation.new(), true}
    end
  end

  defp finalize_owned_asset_copies({:ok, _asset} = result, tracker, true) do
    case StorageCompensation.cleanup_unretained(tracker) do
      :ok -> result
      {:error, cleanup_reason} -> {:error, {:storage_cleanup_failed, cleanup_reason}}
    end
  end

  defp finalize_owned_asset_copies({:error, _reason} = result, tracker, true) do
    case StorageCompensation.cleanup_after_rollback(tracker) do
      :ok -> result
      {:error, cleanup_reason} -> {:error, {:storage_cleanup_failed, elem(result, 1), cleanup_reason}}
    end
  end

  defp finalize_owned_asset_copies(result, _tracker, false), do: result

  defp cleanup_owned_asset_copies(tracker, true) do
    case StorageCompensation.cleanup_after_rollback(tracker) do
      :ok ->
        :ok

      {:error, cleanup_reason} ->
        Logger.error(
          "Asset copy cleanup failed while preserving the original exception: " <>
            inspect(cleanup_reason)
        )

        :ok
    end
  rescue
    cleanup_error ->
      Logger.error(
        "Asset copy cleanup raised while preserving the original exception: " <>
          Exception.format(:error, cleanup_error, __STACKTRACE__)
      )

      :ok
  catch
    kind, cleanup_reason ->
      Logger.error(
        "Asset copy cleanup threw while preserving the original exception: " <>
          inspect({kind, cleanup_reason})
      )

      :ok
  end

  defp cleanup_owned_asset_copies(_tracker, false), do: :ok

  defp materialize_and_insert_asset(changeset, project_id, blob_hash, expected_size, ext, source_key, dest_key, opts) do
    with {:ok, destination_blob_key, blob_created?} <-
           ensure_destination_blob(project_id, blob_hash, expected_size, ext, source_key, opts) do
      owned_keys = owned_storage_keys(dest_key, destination_blob_key, blob_created?)
      Enum.each(owned_keys, &track_copy(opts, &1))

      StorageKeyLock.with_storage_key_lock(dest_key, fn ->
        copy_and_insert_asset(changeset, destination_blob_key, dest_key, owned_keys, opts)
      end)
    end
  end

  defp ensure_destination_blob(project_id, blob_hash, expected_size, ext, source_key, opts) do
    destination_blob_key = blob_key(project_id, blob_hash, ext)

    with :ok <- verify_stored_blob(source_key, blob_hash, expected_size) do
      if source_key == destination_blob_key do
        {:ok, destination_blob_key, false}
      else
        copy_verified_blob_if_absent(
          source_key,
          destination_blob_key,
          blob_hash,
          expected_size,
          opts
        )
      end
    end
  end

  defp copy_verified_blob_if_absent(source_key, destination_blob_key, blob_hash, expected_size, opts) do
    case Storage.copy_if_absent(source_key, destination_blob_key) do
      {:ok, created?} ->
        verify_copied_blob(destination_blob_key, blob_hash, expected_size, created?, opts)

      {:error,
       {:conditional_copy_cleanup_required, destination_created?, pending_cleanup_key, _cleanup_reason} =
           reason}
      when is_boolean(destination_created?) and is_binary(pending_cleanup_key) ->
        owned_keys =
          if destination_created?,
            do: [destination_blob_key, pending_cleanup_key],
            else: [pending_cleanup_key]

        Enum.each(owned_keys, &track_copy(opts, &1))
        compensate_failed_materialization(opts, owned_keys)
        {:error, reason}

      {:error, reason} ->
        # A remote conditional copy can succeed server-side while its response
        # is lost. Track the deterministic destination conservatively; deferred
        # cleanup retains it for committed projects and removes it after a
        # destination-project rollback.
        track_copy(opts, destination_blob_key)
        {:error, reason}
    end
  end

  defp verify_copied_blob(destination_blob_key, blob_hash, expected_size, created?, opts) do
    verification =
      try do
        {:result, verify_stored_blob(destination_blob_key, blob_hash, expected_size)}
      rescue
        error -> {:raised, error, __STACKTRACE__}
      catch
        kind, reason -> {:caught, kind, reason, __STACKTRACE__}
      end

    case verification do
      {:result, :ok} ->
        {:ok, destination_blob_key, created?}

      {:result, {:error, :blob_hash_mismatch} = error} ->
        compensate_invalid_blob(opts, destination_blob_key)
        error

      {:result, {:error, {:asset_blob_size_mismatch, _expected, _actual}} = error} ->
        compensate_invalid_blob(opts, destination_blob_key)
        error

      {:result, {:error, reason}} ->
        compensate_created_blob(created?, opts, destination_blob_key)
        {:error, reason}

      {:result, _unexpected} ->
        compensate_created_blob(created?, opts, destination_blob_key)
        {:error, :unexpected_blob_verification_result}

      {:raised, error, stacktrace} ->
        compensate_created_blob(created?, opts, destination_blob_key)
        reraise error, stacktrace

      {:caught, kind, reason, stacktrace} ->
        compensate_created_blob(created?, opts, destination_blob_key)
        :erlang.raise(kind, reason, stacktrace)
    end
  end

  defp compensate_created_blob(false, _opts, _destination_blob_key), do: :ok

  defp compensate_created_blob(true, opts, destination_blob_key) do
    track_copy(opts, destination_blob_key)
    compensate_failed_materialization(opts, [destination_blob_key])
  end

  defp compensate_invalid_blob(opts, destination_blob_key) do
    case Keyword.get(opts, :asset_copy_tracker) do
      reference when is_reference(reference) ->
        StorageCompensation.track_force_delete(reference, destination_blob_key)

        case StorageCompensation.delete_force_tracked_or_enqueue(reference, destination_blob_key) do
          :ok ->
            :ok

          {:error, :storage_cleanup_requires_post_transaction} ->
            # The force target intentionally remains tracked until the owner
            # knows whether its database transaction committed or rolled back.
            :ok

          {:error, reason} ->
            Logger.warning("Could not delete or hand off verified-invalid blob error=#{safe_error(reason)}")
        end

      _reference ->
        raise "asset copy storage tracker is not initialized"
    end
  end

  defp verify_stored_blob(storage_key, expected_hash) do
    with {:ok, stat} <- Storage.stat(storage_key) do
      verify_stored_blob(storage_key, stat, expected_hash)
    end
  end

  defp verify_stored_blob(storage_key, expected_hash, expected_size)
       when is_binary(expected_hash) and is_integer(expected_size) do
    with {:ok, stat} <- Storage.stat(storage_key),
         :ok <- verify_stored_blob_size(stat, expected_size) do
      verify_stored_blob(storage_key, stat, expected_hash)
    end
  end

  defp verify_stored_blob(storage_key, %{size: _size} = stat, expected_hash) when is_binary(expected_hash) do
    with {:ok, chunks} <-
           Storage.stream(storage_key, 0, stat.size, etag: stat.etag),
         {:ok, actual_hash} <- StorageHash.sha256_chunks(chunks) do
      if actual_hash == expected_hash, do: :ok, else: {:error, :blob_hash_mismatch}
    end
  end

  defp verify_stored_blob_size(%{size: actual_size}, expected_size)
       when is_integer(expected_size) and expected_size >= 0 do
    if actual_size == expected_size,
      do: :ok,
      else: {:error, {:asset_blob_size_mismatch, expected_size, actual_size}}
  end

  defp verify_stored_blob_size(_stat, _expected_size), do: {:error, :invalid_asset_blob_size}

  defp owned_storage_keys(dest_key, destination_blob_key, true), do: [dest_key, destination_blob_key]
  defp owned_storage_keys(dest_key, _destination_blob_key, false), do: [dest_key]

  defp copy_and_insert_asset(changeset, source_key, dest_key, owned_keys, opts) do
    outcome =
      try do
        with :ok <- Storage.copy(source_key, dest_key),
             {:ok, asset} <- Repo.insert(changeset) do
          {:success, asset}
        else
          {:error, reason} -> {:failure, reason}
        end
      rescue
        error -> {:raised, error, __STACKTRACE__}
      catch
        kind, reason -> {:caught, kind, reason, __STACKTRACE__}
      end

    case outcome do
      {:success, asset} ->
        retain_copied_asset(opts, owned_keys)
        {:ok, asset}

      {:failure, reason} ->
        compensate_failed_materialization(opts, owned_keys)
        {:error, reason}

      {:raised, error, stacktrace} ->
        compensate_failed_materialization(opts, owned_keys)
        reraise error, stacktrace

      {:caught, kind, reason, stacktrace} ->
        compensate_failed_materialization(opts, owned_keys)
        :erlang.raise(kind, reason, stacktrace)
    end
  end

  defp restore_changeset(asset, %{content_type: "image/svg+xml", metadata: %{"sanitized_svg" => true}} = attrs) do
    Asset.create_sanitized_svg_changeset(asset, attrs)
  end

  defp restore_changeset(asset, attrs), do: Asset.create_changeset(asset, attrs)

  defp track_copy(opts, dest_key) do
    case Keyword.get(opts, :asset_copy_tracker) do
      reference when is_reference(reference) -> StorageCompensation.track(reference, dest_key)
      _reference -> :ok
    end
  end

  defp retain_copied_asset(opts, owned_keys) do
    case Keyword.get(opts, :asset_copy_tracker) do
      reference when is_reference(reference) ->
        Enum.each(owned_keys, &StorageCompensation.retain_after_commit(reference, &1))

      _reference ->
        :ok
    end
  end

  defp compensate_failed_materialization(opts, owned_keys) do
    case Keyword.get(opts, :asset_copy_tracker) do
      reference when is_reference(reference) ->
        compensate_tracked_materialization(reference, owned_keys)

      _reference ->
        StorageCompensation.delete_or_enqueue_all!(owned_keys)
    end
  end

  defp compensate_tracked_materialization(reference, owned_keys) do
    Enum.each(owned_keys, fn storage_key ->
      case StorageCompensation.delete_tracked_or_enqueue(reference, storage_key) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Could not delete or hand off tracked asset after materialization failure error=#{safe_error(reason)}"
          )
      end
    end)
  end

  defp safe_error(reason) when is_atom(reason), do: reason
  defp safe_error({reason, _details}) when is_atom(reason), do: reason
  defp safe_error(_reason), do: :unexpected_error
end
