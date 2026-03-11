defmodule Storyarn.Versioning.SnapshotStorage do
  @moduledoc """
  Handles storing and loading version snapshots as compressed JSON in object storage.

  Snapshots are gzipped JSON stored via the configured storage adapter (R2/Local).
  Key format: `projects/{project_id}/snapshots/{entity_type}/{entity_id}/{version_number}.json.gz`
  """

  alias Storyarn.Assets.Storage

  @doc """
  Stores a snapshot map as compressed JSON in object storage.

  Returns `{:ok, storage_key, size_bytes}` or `{:error, reason}`.
  """
  @spec store_snapshot(integer(), String.t(), integer(), integer(), map()) ::
          {:ok, String.t(), integer()} | {:error, term()}
  def store_snapshot(project_id, entity_type, entity_id, version_number, snapshot) do
    key = build_key(project_id, entity_type, entity_id, version_number)
    json = Jason.encode!(snapshot)
    compressed = :zlib.gzip(json)
    size_bytes = byte_size(compressed)

    case Storage.upload(key, compressed, "application/gzip") do
      {:ok, _url} -> {:ok, key, size_bytes}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Loads and decompresses a snapshot from object storage.

  Returns `{:ok, snapshot_map}` or `{:error, reason}`.
  """
  @spec load_snapshot(String.t()) :: {:ok, map()} | {:error, term()}
  def load_snapshot(storage_key) do
    with {:ok, compressed} <- Storage.download(storage_key),
         {:ok, json} <- safe_gunzip(compressed) do
      Jason.decode(json)
    end
  end

  defp safe_gunzip(compressed) do
    {:ok, :zlib.gunzip(compressed)}
  rescue
    e in ErlangError -> {:error, {:decompress_failed, e.original}}
  end

  @doc """
  Deletes a snapshot from object storage.
  """
  @spec delete_snapshot(String.t()) :: :ok | {:error, term()}
  def delete_snapshot(storage_key) do
    Storage.delete(storage_key)
  end

  @doc """
  Builds the storage key for a snapshot.
  """
  @spec build_key(integer(), String.t(), integer(), integer()) :: String.t()
  def build_key(project_id, entity_type, entity_id, version_number) do
    "projects/#{project_id}/snapshots/#{entity_type}/#{entity_id}/#{version_number}.json.gz"
  end
end
