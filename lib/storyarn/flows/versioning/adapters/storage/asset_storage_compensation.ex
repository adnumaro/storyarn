defmodule Storyarn.Flows.Versioning.AssetStorageCompensation do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Versioning.Adapters.Storage.Locks, as: StorageKeyLock
  alias Storyarn.Flows.Versioning.Adapters.Storage.Objects, as: Storage
  alias Storyarn.Flows.Versioning.Entities.AssetRecord
  alias Storyarn.Flows.Versioning.Entities.StorageCleanupRequestRecord
  alias Storyarn.Repo

  @tracker_key {__MODULE__, :tracked}
  @retained_key {__MODULE__, :retained}

  @spec new() :: reference()
  def new do
    reference = make_ref()
    Process.put(key(reference), [])
    Process.put(retained_key(reference), [])
    reference
  end

  @spec track(reference(), String.t()) :: :ok
  def track(reference, storage_key) when is_reference(reference) and is_binary(storage_key) do
    Process.put(key(reference), [storage_key | Enum.reject(tracked(reference), &(&1 == storage_key))])
    :ok
  end

  @spec retain_after_commit(reference(), String.t()) :: :ok
  def retain_after_commit(reference, storage_key) when is_reference(reference) and is_binary(storage_key) do
    track(reference, storage_key)

    Process.put(
      retained_key(reference),
      [storage_key | Enum.reject(retained(reference), &(&1 == storage_key))]
    )

    :ok
  end

  @spec cleanup_after_rollback(reference(), keyword()) :: :ok | {:error, term()}
  def cleanup_after_rollback(reference, opts \\ []) when is_reference(reference) and is_list(opts) do
    cleanup(reference, tracked(reference), opts)
  end

  @spec cleanup_after_rollback!(reference(), keyword()) :: :ok
  def cleanup_after_rollback!(reference, opts \\ []) when is_reference(reference) and is_list(opts) do
    case cleanup_after_rollback(reference, opts) do
      :ok -> :ok
      {:error, reason} -> raise "Flow asset rollback cleanup failed: #{inspect(reason)}"
    end
  end

  @spec cleanup_unretained(reference(), keyword()) :: :ok | {:error, term()}
  def cleanup_unretained(reference, opts \\ []) when is_reference(reference) and is_list(opts) do
    retained = reference |> retained() |> MapSet.new()
    cleanup(reference, Enum.reject(tracked(reference), &MapSet.member?(retained, &1)), opts)
  end

  @spec discard(reference()) :: :ok
  def discard(reference) when is_reference(reference) do
    Process.delete(key(reference))
    Process.delete(retained_key(reference))
    :ok
  end

  defp cleanup(reference, storage_keys, opts) do
    delete_fun = Keyword.get(opts, :delete_fun, &delete_unowned_storage_key/1)
    persist_fun = Keyword.get(opts, :persist_fun, &persist_cleanup_request/1)

    failures =
      storage_keys
      |> Enum.filter(&Storage.canonical_key?/1)
      |> Enum.uniq()
      |> Enum.filter(&(call_delete(delete_fun, &1) != :ok))

    if failures == [] do
      discard(reference)
    else
      hand_off_failed_cleanup(reference, failures, persist_fun)
    end
  end

  defp hand_off_failed_cleanup(reference, storage_keys, persist_fun) do
    case call_persist(persist_fun, storage_keys) do
      {:ok, _request} ->
        discard(reference)

      {:error, reason} ->
        {:error, {:storage_cleanup_not_persisted, %{failed_keys: storage_keys, persistence_error: safe_error(reason)}}}
    end
  end

  defp persist_cleanup_request(storage_keys) do
    StorageKeyLock.with_cleanup_handoff_locks(storage_keys, fn ->
      %StorageCleanupRequestRecord{}
      |> StorageCleanupRequestRecord.flow_restore_changeset(storage_keys)
      |> Repo.insert()
    end)
  end

  defp call_delete(delete_fun, storage_key) do
    case delete_fun.(storage_key) do
      :ok -> :ok
      _error -> :error
    end
  rescue
    _error -> :error
  catch
    _kind, _reason -> :error
  end

  defp call_persist(persist_fun, storage_keys) do
    case persist_fun.(storage_keys) do
      {:ok, request} -> {:ok, request}
      {:error, reason} -> {:error, reason}
      _result -> {:error, :unexpected_persistence_result}
    end
  rescue
    error -> {:error, {:exception, error.__struct__}}
  catch
    kind, reason -> {:error, {kind, safe_error(reason)}}
  end

  defp delete_unowned_storage_key(storage_key) do
    StorageKeyLock.with_storage_key_lock(storage_key, fn ->
      if asset_storage_key_owned?(storage_key), do: :ok, else: Storage.delete(storage_key)
    end)
  end

  defp asset_storage_key_owned?(storage_key) do
    Repo.exists?(from(asset in AssetRecord, where: asset.key == ^storage_key))
  end

  defp tracked(reference), do: Process.get(key(reference), [])
  defp retained(reference), do: Process.get(retained_key(reference), [])
  defp key(reference), do: {@tracker_key, reference}
  defp retained_key(reference), do: {@retained_key, reference}

  defp safe_error(reason) when is_atom(reason), do: reason
  defp safe_error({reason, _details}) when is_atom(reason), do: reason
  defp safe_error(_reason), do: :unexpected_error
end
