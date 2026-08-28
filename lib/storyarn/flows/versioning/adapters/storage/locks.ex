defmodule Storyarn.Flows.Versioning.Adapters.Storage.Locks do
  @moduledoc false

  alias Storyarn.Platform.ObjectStorage, as: KeyLock

  @max_project_id 9_223_372_036_854_775_807
  @temporary_copy_marker ".storyarn-copy-"

  def with_project_blob_lock(storage_key, fun), do: with_project_blob_lock(storage_key, fun, [])

  def with_project_blob_lock(storage_key, fun, opts)
      when is_binary(storage_key) and is_function(fun, 0) and is_list(opts) do
    case project_blob_id(storage_key) do
      {:ok, _project_id} -> KeyLock.with_storage_key_lock(storage_key, fun, opts)
      :error -> fun.()
    end
  end

  defdelegate with_storage_key_lock(storage_key, fun), to: KeyLock
  defdelegate with_storage_key_lock(storage_key, fun, opts), to: KeyLock

  def project_blob_id(storage_key) do
    case project_blob_identity(storage_key) do
      {:ok, project_id, _hash} -> {:ok, project_id}
      :error -> :error
    end
  end

  def project_blob_identity(storage_key) when is_binary(storage_key) do
    case Regex.run(
           ~r|\Aprojects/([1-9]\d*)/blobs/([0-9a-f]{64})\.([^/]+)\z|,
           storage_key,
           capture: :all_but_first
         ) do
      [project_id, hash, extension] -> parse_project_blob_identity(project_id, hash, extension)
      _match -> :error
    end
  end

  defp parse_project_blob_identity(project_id, hash, extension) do
    with false <- String.contains?(extension, @temporary_copy_marker),
         {project_id, ""} when project_id > 0 and project_id <= @max_project_id <-
           Integer.parse(project_id) do
      {:ok, project_id, hash}
    else
      _invalid -> :error
    end
  end
end
