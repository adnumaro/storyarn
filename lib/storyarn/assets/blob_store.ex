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
    with {:ok, binary_data} <- load_verified_blob(source_key, blob_hash),
         {:ok, destination_blob_key, blob_created?} <-
           ensure_destination_blob(project_id, blob_hash, ext, binary_data) do
      owned_keys = owned_storage_keys(dest_key, destination_blob_key, blob_created?)
      Enum.each(owned_keys, &track_copy(opts, &1))

      copy_and_insert_asset(changeset, destination_blob_key, dest_key, owned_keys, opts)
    end
  end

  defp load_verified_blob(source_key, blob_hash) do
    with {:ok, binary_data} <- Storage.download(source_key),
         :ok <- verify_blob_hash(binary_data, blob_hash) do
      {:ok, binary_data}
    end
  end

  defp ensure_destination_blob(project_id, blob_hash, ext, binary_data) do
    case ensure_blob_with_status(project_id, blob_hash, ext, binary_data) do
      {:ok, destination_blob_key, true} ->
        {:ok, destination_blob_key, true}

      {:ok, destination_blob_key, false} ->
        with {:ok, stored_data} <- Storage.download(destination_blob_key),
             :ok <- verify_blob_hash(stored_data, blob_hash) do
          {:ok, destination_blob_key, false}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_blob_hash(binary_data, expected_hash) do
    if compute_hash(binary_data) == expected_hash, do: :ok, else: {:error, :blob_hash_mismatch}
  end

  defp owned_storage_keys(dest_key, destination_blob_key, true), do: [dest_key, destination_blob_key]
  defp owned_storage_keys(dest_key, _destination_blob_key, false), do: [dest_key]

  defp copy_and_insert_asset(changeset, source_key, dest_key, owned_keys, opts) do
    with :ok <- Storage.copy(source_key, dest_key),
         {:ok, asset} <- Repo.insert(changeset) do
      {:ok, asset}
    else
      {:error, reason} ->
        compensate_failed_materialization(opts, owned_keys)
        {:error, reason}
    end
  rescue
    error ->
      compensate_failed_materialization(opts, owned_keys)
      reraise error, __STACKTRACE__
  catch
    kind, reason ->
      compensate_failed_materialization(opts, owned_keys)
      :erlang.raise(kind, reason, __STACKTRACE__)
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

  defp untrack_copy(opts, dest_key) do
    case Keyword.get(opts, :asset_copy_tracker) do
      reference when is_reference(reference) -> StorageCompensation.untrack(reference, dest_key)
      _reference -> :ok
    end
  end

  defp compensate_failed_materialization(opts, owned_keys) do
    failed_keys =
      Enum.reduce(owned_keys, [], fn storage_key, failed_keys ->
        case Storage.delete(storage_key) do
          :ok ->
            untrack_copy(opts, storage_key)
            failed_keys

          {:error, reason} ->
            Logger.warning("Could not delete asset after materialization failure error=#{safe_error(reason)}")
            [storage_key | failed_keys]
        end
      end)

    enqueue_untracked_cleanup(opts, failed_keys)
  end

  defp enqueue_untracked_cleanup(_opts, []), do: :ok

  defp enqueue_untracked_cleanup(opts, storage_keys) do
    case Keyword.get(opts, :asset_copy_tracker) do
      reference when is_reference(reference) -> :ok
      _reference -> StorageCompensation.enqueue_cleanup(storage_keys)
    end
  end

  defp safe_error(reason) when is_atom(reason), do: reason
  defp safe_error({reason, _details}) when is_atom(reason), do: reason
  defp safe_error(_reason), do: :unexpected_error
end
