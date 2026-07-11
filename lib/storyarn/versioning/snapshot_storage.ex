defmodule Storyarn.Versioning.SnapshotStorage do
  @moduledoc """
  Handles storing and loading version snapshots as compressed JSON in object storage.

  Snapshots are gzipped JSON stored via the configured storage adapter (R2/Local).
  Key format: `projects/{project_id}/snapshots/{entity_type}/{entity_id}/{version_number}.json.gz`
  or, for uniquely owned write attempts,
  `projects/{project_id}/snapshots/{entity_type}/{entity_id}/{version_number}-{suffix}.json.gz`.
  """

  alias Storyarn.Assets.Storage

  @doc """
  Stores a snapshot map as compressed JSON in object storage.

  Returns `{:ok, storage_key, size_bytes}` or `{:error, reason}`.
  """
  @spec store_snapshot(integer(), String.t(), integer(), integer(), map()) ::
          {:ok, String.t(), integer()} | {:error, term()}
  @spec store_snapshot(integer(), String.t(), integer(), integer(), map(), String.t() | nil) ::
          {:ok, String.t(), integer()} | {:error, term()}
  def store_snapshot(project_id, entity_type, entity_id, version_number, snapshot, suffix \\ nil) do
    key = build_key(project_id, entity_type, entity_id, version_number, suffix)
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
  Stores a snapshot map with a pre-built storage key.

  Returns `{:ok, size_bytes}` or `{:error, reason}`.
  """
  @spec store_raw(String.t(), map()) :: {:ok, integer()} | {:error, term()}
  def store_raw(key, snapshot) do
    json = Jason.encode!(snapshot)
    compressed = :zlib.gzip(json)
    size_bytes = byte_size(compressed)

    case Storage.upload(key, compressed, "application/gzip") do
      {:ok, _url} -> {:ok, size_bytes}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes a snapshot from object storage.
  """
  @spec delete_snapshot(String.t()) :: :ok | {:error, term()}
  def delete_snapshot(storage_key) do
    Storage.delete(storage_key)
  end

  @doc """
  Returns a random hex suffix suitable for uniquely owned snapshot storage keys.
  """
  @spec unique_key_suffix() :: String.t()
  def unique_key_suffix do
    8
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  @doc """
  Builds the storage key for a snapshot.
  """
  @spec build_key(integer(), String.t(), integer(), integer()) :: String.t()
  @spec build_key(integer(), String.t(), integer(), integer(), String.t() | nil) :: String.t()
  def build_key(project_id, entity_type, entity_id, version_number, suffix \\ nil) do
    version_segment = version_segment(version_number, suffix)
    "projects/#{project_id}/snapshots/#{entity_type}/#{entity_id}/#{version_segment}.json.gz"
  end

  @doc """
  Builds the storage key for a project-level snapshot.
  """
  @spec build_project_key(integer(), integer()) :: String.t()
  @spec build_project_key(integer(), integer(), String.t() | nil) :: String.t()
  def build_project_key(project_id, version_number, suffix \\ nil) do
    version_segment = version_segment(version_number, suffix)
    "projects/#{project_id}/snapshots/project/#{version_segment}.json.gz"
  end

  defp version_segment(version_number, nil), do: to_string(version_number)
  defp version_segment(version_number, ""), do: to_string(version_number)
  defp version_segment(version_number, suffix), do: "#{version_number}-#{suffix}"
end
