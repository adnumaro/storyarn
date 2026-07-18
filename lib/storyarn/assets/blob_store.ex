defmodule Storyarn.Assets.BlobStore do
  @moduledoc """
  Content-addressable blob storage for versioning.

  Assets are stored by SHA256 hash so that snapshots can reference them by
  content rather than database ID. If an asset is deleted, snapshots can
  still restore it from the blob.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Assets.StorageHash
  alias Storyarn.Assets.StorageKeyLock
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  require Logger

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

  def ext_from_content_type(other) do
    other |> String.split("/") |> List.last() |> String.split("+") |> List.first()
  end

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
    key = blob_key(project_id, hash, ext)

    StorageKeyLock.with_project_blob_lock(key, fn ->
      do_ensure_blob_with_status(key, hash, ext, binary_data)
    end)
  end

  defp do_ensure_blob_with_status(key, hash, ext, binary_data) do
    if compute_hash(binary_data) == hash do
      put_blob_if_absent(key, hash, ext, binary_data)
    else
      {:error, :blob_hash_mismatch}
    end
  end

  defp put_blob_if_absent(key, hash, ext, binary_data) do
    case Storage.put_if_absent(key, binary_data, MIME.type(ext)) do
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

    case asset_copy_tracker(opts, caller_transactional?) do
      {:ok, tracker, owns_tracker?} ->
        opts =
          opts
          |> Keyword.put(:asset_copy_tracker, tracker)
          |> Keyword.put(:asset_copy_caller_transactional?, caller_transactional?)

        try do
          project_id
          |> do_create_asset_from_blob(user_id, blob_hash, source_key, metadata, opts)
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

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_create_asset_from_blob(project_id, user_id, blob_hash, source_key, metadata, opts) do
    ext = ext_from_content_type(metadata["content_type"])
    source_key = source_key || blob_key(project_id, blob_hash, ext)

    uuid = Ecto.UUID.generate()
    filename = metadata["filename"]
    sanitized = Storyarn.Assets.sanitize_filename(filename)
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
        materialize_and_insert_asset(changeset, project_id, blob_hash, ext, source_key, dest_key, opts)
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
    case StorageCompensation.cleanup(tracker) do
      :ok -> result
      {:error, cleanup_reason} -> {:error, {:storage_cleanup_failed, elem(result, 1), cleanup_reason}}
    end
  end

  defp finalize_owned_asset_copies(result, _tracker, false), do: result

  defp cleanup_owned_asset_copies(tracker, true), do: StorageCompensation.cleanup!(tracker)
  defp cleanup_owned_asset_copies(_tracker, false), do: :ok

  defp materialize_and_insert_asset(changeset, project_id, blob_hash, ext, source_key, dest_key, opts) do
    with {:ok, destination_blob_key, blob_created?} <-
           ensure_destination_blob(project_id, blob_hash, ext, source_key, opts) do
      owned_keys = owned_storage_keys(dest_key, destination_blob_key, blob_created?)
      Enum.each(owned_keys, &track_copy(opts, &1))

      StorageKeyLock.with_storage_key_lock(dest_key, fn ->
        copy_and_insert_asset(changeset, destination_blob_key, dest_key, owned_keys, opts)
      end)
    end
  end

  defp ensure_destination_blob(project_id, blob_hash, ext, source_key, opts) do
    destination_blob_key = blob_key(project_id, blob_hash, ext)

    with :ok <- verify_stored_blob(source_key, blob_hash) do
      if source_key == destination_blob_key do
        {:ok, destination_blob_key, false}
      else
        copy_verified_blob_if_absent(
          source_key,
          destination_blob_key,
          blob_hash,
          opts
        )
      end
    end
  end

  defp copy_verified_blob_if_absent(source_key, destination_blob_key, blob_hash, opts) do
    case Storage.copy_if_absent(source_key, destination_blob_key) do
      {:ok, created?} ->
        verify_copied_blob(destination_blob_key, blob_hash, created?, opts)

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

  defp verify_copied_blob(destination_blob_key, blob_hash, created?, opts) do
    verification =
      try do
        {:result, verify_stored_blob(destination_blob_key, blob_hash)}
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

        case StorageCompensation.delete_force_tracked_or_enqueue(reference, destination_blob_key,
               allow_force_delete_in_transaction?: not Keyword.fetch!(opts, :asset_copy_caller_transactional?)
             ) do
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

  defp verify_stored_blob(storage_key, stat, expected_hash) do
    with {:ok, chunks} <-
           Storage.stream(storage_key, 0, stat.size, etag: stat.etag),
         {:ok, actual_hash} <- StorageHash.sha256_chunks(chunks) do
      if actual_hash == expected_hash, do: :ok, else: {:error, :blob_hash_mismatch}
    end
  end

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
