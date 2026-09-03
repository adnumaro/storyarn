defmodule Storyarn.Projects.Assets.StorageKeyLock do
  @moduledoc """
  Project blob-key policy layered over the neutral object-storage lock engine.
  """

  alias Storyarn.Platform.ObjectStorage, as: KeyLock
  alias Storyarn.Projects.Assets.StorageCleanupOwnership

  @max_project_id 9_223_372_036_854_775_807
  @temporary_copy_marker ".storyarn-copy-"
  @force_delete_prefix "__storyarn_force_delete__:"

  @spec with_project_blob_lock(String.t(), (-> result)) :: result when result: term()
  def with_project_blob_lock(storage_key, fun) when is_binary(storage_key) and is_function(fun, 0) do
    with_project_blob_lock(storage_key, fun, [])
  end

  @doc false
  @spec with_project_blob_lock(String.t(), (-> result), keyword()) :: result when result: term()
  def with_project_blob_lock(storage_key, fun, opts)
      when is_binary(storage_key) and is_function(fun, 0) and is_list(opts) do
    case project_blob_id(storage_key) do
      {:ok, _project_id} -> with_storage_key_lock(storage_key, fun, opts)
      :error -> fun.()
    end
  end

  def with_storage_key_lock(storage_key, fun), do: with_storage_key_lock(storage_key, fun, [])

  def with_storage_key_lock(storage_key, fun, opts)
      when is_binary(storage_key) and is_function(fun, 0) and is_list(opts) do
    KeyLock.with_storage_key_lock(storage_key, fn -> run_if_not_handed_off([storage_key], fun) end, opts)
  end

  def with_storage_key_locks(storage_keys, fun, opts \\ [])
      when is_list(storage_keys) and is_function(fun, 0) and is_list(opts) do
    KeyLock.with_storage_key_locks(storage_keys, fn -> run_if_not_handed_off(storage_keys, fun) end, opts)
  end

  @doc false
  def with_cleanup_handoff_locks(cleanup_targets, fun, opts \\ [])
      when is_list(cleanup_targets) and is_function(fun, 0) and is_list(opts) do
    storage_keys = Enum.map(cleanup_targets, &cleanup_target_storage_key/1)
    KeyLock.transact_with_storage_key_locks(storage_keys, fun, opts)
  end

  @doc false
  def with_multipart_cleanup_handoff(cleanup_targets, fun, opts \\ [])
      when is_list(cleanup_targets) and is_function(fun, 0) and is_list(opts) do
    storage_keys = Enum.map(cleanup_targets, &cleanup_target_storage_key/1)
    KeyLock.transact_with_storage_handoff(storage_keys, fun, opts)
  end

  @doc false
  defdelegate transact_with_storage_key_admission(storage_key, fun, opts \\ []),
    to: KeyLock

  @doc false
  defdelegate with_cleanup_storage_key_lock(storage_key, fun), to: KeyLock, as: :with_storage_key_lock

  @doc false
  defdelegate with_cleanup_storage_key_lock(storage_key, fun, opts), to: KeyLock, as: :with_storage_key_lock

  @doc false
  defdelegate with_owned_asset_adoption_locks(storage_keys, fun), to: KeyLock, as: :with_storage_key_locks

  defdelegate wrapper_owned_transaction_lock_held?(storage_key), to: KeyLock
  defdelegate with_session_lock(lock_name, fun), to: KeyLock
  defdelegate with_session_lock(lock_name, fun, opts), to: KeyLock

  @spec project_blob_id(String.t()) :: {:ok, pos_integer()} | :error
  def project_blob_id(storage_key) when is_binary(storage_key) do
    case project_blob_identity(storage_key) do
      {:ok, project_id, _hash} -> {:ok, project_id}
      :error -> :error
    end
  end

  @spec project_blob_identity(String.t()) :: {:ok, pos_integer(), String.t()} | :error
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

  defp run_if_not_handed_off(storage_keys, fun) do
    case cleanup_handoff_state(storage_keys) do
      {:ok, true} -> {:error, :storage_key_cleanup_handed_off}
      {:ok, false} -> fun.()
      {:error, :unavailable} -> {:error, :storage_write_fence_unavailable}
    end
  end

  defp cleanup_handoff_state(storage_keys) do
    {:ok, StorageCleanupOwnership.handed_off_for_any_key?(storage_keys)}
  rescue
    _exception -> {:error, :unavailable}
  catch
    _kind, _reason -> {:error, :unavailable}
  end

  defp cleanup_target_storage_key(@force_delete_prefix <> storage_key), do: storage_key
  defp cleanup_target_storage_key(storage_key), do: storage_key
end
