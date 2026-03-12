defmodule Storyarn.Assets.BlobStore do
  @moduledoc """
  Content-addressable blob storage for versioning.

  Assets are stored by SHA256 hash so that snapshots can reference them by
  content rather than database ID. If an asset is deleted, snapshots can
  still restore it from the blob.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Assets.{Asset, Storage}
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

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
    :crypto.hash(:sha256, binary_data) |> Base.encode16(case: :lower)
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
    key = blob_key(project_id, hash, ext)

    case Storage.download(key) do
      {:ok, _existing} ->
        {:ok, key}

      {:error, _} ->
        content_type = MIME.type(ext)

        case Storage.upload(key, binary_data, content_type) do
          {:ok, _url} -> {:ok, key}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Creates a new Asset record from a blob for restoring deleted assets.

  Uses the blob content to populate a new asset with a fresh storage key,
  while preserving the original metadata (filename, content_type, size).
  """
  @spec create_asset_from_blob(integer(), integer() | nil, String.t(), String.t(), map()) ::
          {:ok, Asset.t()} | {:error, term()}
  def create_asset_from_blob(project_id, user_id, blob_hash, _blob_key, metadata) do
    ext = ext_from_content_type(metadata["content_type"])
    source_key = blob_key(project_id, blob_hash, ext)

    uuid = Ecto.UUID.generate()
    filename = metadata["filename"]
    sanitized = Storyarn.Assets.sanitize_filename(filename)
    dest_key = "projects/#{project_id}/assets/#{uuid}/#{sanitized}"

    with :ok <- Storage.copy(source_key, dest_key) do
      now = TimeHelpers.now()

      attrs = %{
        filename: filename,
        content_type: metadata["content_type"],
        size: metadata["size"],
        key: dest_key,
        url: Storage.get_url(dest_key),
        metadata: Map.drop(metadata, ["filename", "content_type", "size"]),
        blob_hash: blob_hash
      }

      %Asset{project_id: project_id, uploaded_by_id: user_id, inserted_at: now, updated_at: now}
      |> Asset.create_changeset(attrs)
      |> Repo.insert()
    end
  end
end
