defmodule Storyarn.Scenes.Assets.Adapters.Storage.Locks do
  @moduledoc false

  alias Storyarn.Projects.Assets.StorageKeyLock

  defdelegate with_project_blob_lock(storage_key, fun), to: StorageKeyLock
  defdelegate with_project_blob_lock(storage_key, fun, opts), to: StorageKeyLock
  defdelegate with_storage_key_lock(storage_key, fun), to: StorageKeyLock
  defdelegate with_storage_key_lock(storage_key, fun, opts), to: StorageKeyLock
  defdelegate with_storage_key_locks(storage_keys, fun, opts \\ []), to: StorageKeyLock
  defdelegate project_blob_identity(storage_key), to: StorageKeyLock
end
