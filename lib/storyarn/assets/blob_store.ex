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

    case Storage.put_if_absent(key, binary_data, MIME.type(ext)) do
      {:ok, _url, created?} -> {:ok, key, created?}
      {:error, reason} -> {:error, reason}
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

    if changeset.valid?,
      do: materialize_and_insert_asset(changeset, project_id, blob_hash, ext, source_key, dest_key, opts),
      else: {:error, changeset}
  end

  defp materialize_and_insert_asset(changeset, project_id, blob_hash, ext, source_key, dest_key, opts) do
    with {:ok, destination_blob_key, blob_created?} <-
           ensure_destination_blob(project_id, blob_hash, ext, source_key, opts) do
      owned_keys = owned_storage_keys(dest_key, destination_blob_key, blob_created?)
      Enum.each(owned_keys, &track_copy(opts, &1))

      copy_and_insert_asset(changeset, destination_blob_key, dest_key, owned_keys, opts)
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

      {:error, reason} ->
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

  defp verify_stored_blob(storage_key, expected_hash) do
    with {:ok, stat} <- Storage.stat(storage_key) do
      verify_stored_blob(storage_key, stat, expected_hash)
    end
  end

  defp verify_stored_blob(storage_key, stat, expected_hash) do
    with {:ok, chunks} <-
           Storage.stream(storage_key, 0, stat.size, etag: stat.etag),
         {:ok, actual_hash} <- hash_chunks(chunks) do
      if actual_hash == expected_hash, do: :ok, else: {:error, :blob_hash_mismatch}
    end
  end

  defp hash_chunks(chunks) do
    chunks
    |> Enum.reduce_while({:ok, :crypto.hash_init(:sha256)}, fn
      {:ok, chunk}, {:ok, hash_state} when is_binary(chunk) ->
        {:cont, {:ok, :crypto.hash_update(hash_state, chunk)}}

      {:error, reason}, _acc ->
        {:halt, {:error, reason}}

      _unexpected, _acc ->
        {:halt, {:error, :unexpected_blob_stream_chunk}}
    end)
    |> case do
      {:ok, hash_state} ->
        hash = hash_state |> :crypto.hash_final() |> Base.encode16(case: :lower)
        {:ok, hash}

      {:error, _reason} = error ->
        error
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
      case Storage.delete(storage_key) do
        :ok ->
          StorageCompensation.untrack(reference, storage_key)

        {:error, reason} ->
          Logger.warning("Could not delete tracked asset after materialization failure error=#{safe_error(reason)}")
      end
    end)
  end

  defp safe_error(reason) when is_atom(reason), do: reason
  defp safe_error({reason, _details}) when is_atom(reason), do: reason
  defp safe_error(_reason), do: :unexpected_error
end
