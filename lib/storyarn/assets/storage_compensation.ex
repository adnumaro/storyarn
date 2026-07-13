defmodule Storyarn.Assets.StorageCompensation do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupPersistenceError
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Repo
  alias Storyarn.Workers.DeleteStorageObjectsWorker

  require Logger

  @enqueue_attempts 3
  @enqueue_retry_delay_ms 25
  @persisted_cleanup_batch_size 100

  @spec new() :: reference()
  def new do
    reference = make_ref()
    Process.put(key(reference), [])
    reference
  end

  @spec track(reference(), String.t()) :: :ok
  def track(reference, storage_key) when is_reference(reference) and is_binary(storage_key) do
    Process.put(key(reference), [storage_key | tracked(reference)])
    :ok
  end

  @spec untrack(reference(), String.t()) :: :ok
  def untrack(reference, storage_key) when is_reference(reference) and is_binary(storage_key) do
    Process.put(key(reference), List.delete(tracked(reference), storage_key))
    :ok
  end

  @spec cleanup(reference(), keyword()) :: :ok | {:error, term()}
  def cleanup(reference, opts \\ []) when is_reference(reference) do
    storage_keys = reference |> tracked() |> Enum.filter(&valid_storage_key?/1) |> Enum.uniq()
    enqueue_fun = Keyword.get(opts, :enqueue_fun, &enqueue_cleanup/1)
    delete_fun = Keyword.get(opts, :delete_fun, &delete_storage_keys/1)
    persist_fun = Keyword.get(opts, :persist_fun, &persist_cleanup_request/1)
    reconcile_fun = Keyword.get(opts, :reconcile_fun, &reconcile_cleanup_request/2)

    case storage_keys do
      [] ->
        discard(reference)

      storage_keys ->
        persist_or_delete_cleanup(
          reference,
          storage_keys,
          enqueue_fun,
          delete_fun,
          persist_fun,
          reconcile_fun
        )
    end
  end

  @spec cleanup!(reference(), keyword()) :: :ok
  def cleanup!(reference, opts \\ []) when is_reference(reference) do
    case cleanup(reference, opts) do
      :ok -> :ok
      {:error, reason} -> raise StorageCleanupPersistenceError, reason: reason
    end
  end

  @spec delete_storage_keys([String.t()]) :: :ok | {:error, [String.t()]}
  def delete_storage_keys(storage_keys) when is_list(storage_keys) do
    failed_keys =
      storage_keys
      |> Enum.filter(&valid_storage_key?/1)
      |> Enum.uniq()
      |> Enum.filter(fn storage_key ->
        case safe_storage_delete(storage_key) do
          :ok -> false
          {:error, _reason} -> true
        end
      end)

    if failed_keys == [], do: :ok, else: {:error, failed_keys}
  end

  @spec enqueue_cleanup([String.t()], keyword()) :: :ok | {:error, term()}
  def enqueue_cleanup(storage_keys, opts \\ []) when is_list(storage_keys) do
    storage_keys = storage_keys |> Enum.filter(&valid_storage_key?/1) |> Enum.uniq()
    insert_fun = Keyword.get(opts, :insert_fun, &insert_cleanup_job/1)
    attempts = Keyword.get(opts, :attempts, @enqueue_attempts)
    retry_delay_ms = Keyword.get(opts, :retry_delay_ms, @enqueue_retry_delay_ms)

    case storage_keys do
      [] ->
        :ok

      storage_keys ->
        enqueue_with_retry(storage_keys, insert_fun, attempts, retry_delay_ms)
    end
  end

  @spec retry_persisted_cleanup_requests(pos_integer()) :: :ok | {:error, non_neg_integer()}
  def retry_persisted_cleanup_requests(limit \\ @persisted_cleanup_batch_size) when is_integer(limit) and limit > 0 do
    cleanup_requests =
      StorageCleanupRequest
      |> order_by([request], asc: request.inserted_at, asc: request.id)
      |> limit(^limit)
      |> Repo.all()

    failed_count = Enum.count(cleanup_requests, &(retry_persisted_cleanup_request(&1) == :error))

    :telemetry.execute(
      [:storyarn, :assets, :storage_compensation, :persisted_retry],
      %{count: length(cleanup_requests), failed_count: failed_count},
      %{}
    )

    if failed_count == 0, do: :ok, else: {:error, failed_count}
  end

  @spec discard(reference()) :: :ok
  def discard(reference) when is_reference(reference) do
    Process.delete(key(reference))
    :ok
  end

  defp tracked(reference), do: Process.get(key(reference), [])
  defp key(reference), do: {__MODULE__, reference}

  defp persist_or_delete_cleanup(reference, storage_keys, enqueue_fun, delete_fun, persist_fun, reconcile_fun) do
    case call_enqueue(enqueue_fun, storage_keys) do
      :ok ->
        _result = call_delete(delete_fun, storage_keys)
        discard(reference)

      {:error, enqueue_reason} ->
        case call_persist(persist_fun, storage_keys) do
          {:ok, cleanup_request} ->
            delete_result = call_delete(delete_fun, storage_keys)
            _result = call_reconcile(reconcile_fun, cleanup_request, delete_result)
            discard(reference)

          {:error, persistence_reason} ->
            handle_unpersisted_cleanup(
              reference,
              storage_keys,
              enqueue_reason,
              persistence_reason,
              delete_fun
            )
        end
    end
  end

  defp handle_unpersisted_cleanup(reference, storage_keys, enqueue_reason, persistence_reason, delete_fun) do
    case call_delete(delete_fun, storage_keys) do
      :ok ->
        discard(reference)

      {:error, failed_keys} ->
        failed_keys = failed_keys |> Enum.filter(&valid_storage_key?/1) |> Enum.uniq()
        discard(reference)
        report_unpersisted_cleanup(failed_keys, enqueue_reason, persistence_reason)

        {:error,
         {:storage_cleanup_not_persisted,
          %{
            failed_keys: failed_keys,
            enqueue_error: safe_error(enqueue_reason),
            persistence_error: safe_error(persistence_reason)
          }}}
    end
  end

  defp enqueue_with_retry(storage_keys, insert_fun, attempts, retry_delay_ms) when attempts > 0 do
    case call_insert(insert_fun, storage_keys) do
      {:ok, _job} ->
        :ok

      {:error, reason} when attempts > 1 ->
        Logger.warning(
          "Could not enqueue copied asset cleanup; retrying error=#{safe_error(reason)} attempts_left=#{attempts - 1}"
        )

        Process.sleep(retry_delay_ms)
        enqueue_with_retry(storage_keys, insert_fun, attempts - 1, retry_delay_ms * 2)

      {:error, reason} ->
        Logger.error("Could not enqueue copied asset cleanup error=#{safe_error(reason)}")
        {:error, reason}
    end
  end

  defp insert_cleanup_job(storage_keys) do
    storage_keys
    |> then(&%{"storage_keys" => &1})
    |> DeleteStorageObjectsWorker.new()
    |> Oban.insert()
  end

  defp call_enqueue(enqueue_fun, storage_keys) do
    case enqueue_fun.(storage_keys) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      _result -> {:error, :unexpected_enqueue_result}
    end
  rescue
    error -> {:error, {:exception, error.__struct__}}
  catch
    kind, reason -> {:error, {kind, safe_error(reason)}}
  end

  defp call_insert(insert_fun, storage_keys) do
    case insert_fun.(storage_keys) do
      {:ok, _job} = success -> success
      {:error, reason} -> {:error, reason}
      _result -> {:error, :unexpected_insert_result}
    end
  rescue
    error -> {:error, {:exception, error.__struct__}}
  catch
    kind, reason -> {:error, {kind, safe_error(reason)}}
  end

  defp call_persist(persist_fun, storage_keys) do
    case persist_fun.(storage_keys) do
      {:ok, _request} = success -> success
      {:error, reason} -> {:error, reason}
      _result -> {:error, :unexpected_persistence_result}
    end
  rescue
    error -> {:error, {:exception, error.__struct__}}
  catch
    kind, reason -> {:error, {kind, safe_error(reason)}}
  end

  defp call_delete(delete_fun, storage_keys) do
    case delete_fun.(storage_keys) do
      :ok -> :ok
      {:error, failed_keys} when is_list(failed_keys) -> {:error, failed_keys}
      _result -> {:error, storage_keys}
    end
  rescue
    error ->
      Logger.error("Copied asset deletion raised error=#{safe_error(error)}")
      {:error, storage_keys}
  catch
    kind, reason ->
      Logger.error("Copied asset deletion failed error=#{safe_error({kind, reason})}")
      {:error, storage_keys}
  end

  defp call_reconcile(reconcile_fun, cleanup_request, delete_result) do
    reconcile_fun.(cleanup_request, delete_result)
  rescue
    error ->
      Logger.warning("Could not reconcile durable asset cleanup error=#{safe_error(error)}")
      {:error, error}
  catch
    kind, reason ->
      Logger.warning("Could not reconcile durable asset cleanup error=#{safe_error({kind, reason})}")
      {:error, {kind, reason}}
  end

  defp persist_cleanup_request(storage_keys) do
    case Repo.insert(%StorageCleanupRequest{storage_keys: storage_keys}) do
      {:ok, cleanup_request} = success ->
        Logger.warning(
          "Persisted copied asset cleanup fallback request_id=#{cleanup_request.id} storage_key_count=#{length(storage_keys)}"
        )

        :telemetry.execute(
          [:storyarn, :assets, :storage_compensation, :fallback_persisted],
          %{count: 1, storage_key_count: length(storage_keys)},
          %{request_id: cleanup_request.id}
        )

        success

      {:error, _changeset} = error ->
        error
    end
  rescue
    error ->
      Logger.error("Could not persist copied asset cleanup fallback error=#{safe_error(error)}")
      {:error, {:exception, error.__struct__}}
  catch
    kind, reason ->
      Logger.error("Could not persist copied asset cleanup fallback error=#{safe_error({kind, reason})}")
      {:error, {kind, safe_error(reason)}}
  end

  defp reconcile_cleanup_request(cleanup_request, :ok) do
    Repo.delete(cleanup_request)
  rescue
    error ->
      Logger.warning("Could not discard completed asset cleanup fallback error=#{safe_error(error)}")
      {:error, error}
  end

  defp reconcile_cleanup_request(cleanup_request, {:error, failed_keys}) do
    cleanup_request
    |> Ecto.Changeset.change(storage_keys: failed_keys)
    |> Repo.update()
  rescue
    error ->
      Logger.warning("Could not narrow asset cleanup fallback error=#{safe_error(error)}")
      {:error, error}
  end

  defp retry_persisted_cleanup_request(cleanup_request) do
    case delete_storage_keys(cleanup_request.storage_keys) do
      :ok ->
        cleanup_request
        |> Repo.delete()
        |> persisted_retry_result()

      {:error, failed_keys} ->
        cleanup_request
        |> Ecto.Changeset.change(storage_keys: failed_keys)
        |> Repo.update()
        |> persisted_retry_result(:error)
    end
  end

  defp persisted_retry_result({:ok, _request}), do: :ok
  defp persisted_retry_result({:error, _changeset}), do: :error
  defp persisted_retry_result({:ok, _request}, result), do: result
  defp persisted_retry_result({:error, _changeset}, _result), do: :error

  defp safe_storage_delete(storage_key) do
    Storage.delete(storage_key)
  rescue
    error ->
      Logger.error("Copied asset deletion raised error=#{safe_error(error)}")
      {:error, :delete_exception}
  catch
    kind, reason ->
      Logger.error("Copied asset deletion failed error=#{safe_error({kind, reason})}")
      {:error, :delete_failure}
  end

  defp report_unpersisted_cleanup(failed_keys, enqueue_reason, persistence_reason) do
    Logger.error(
      "Copied asset cleanup could not be completed or persisted failed_count=#{length(failed_keys)} enqueue_error=#{safe_error(enqueue_reason)} persistence_error=#{safe_error(persistence_reason)}"
    )

    :telemetry.execute(
      [:storyarn, :assets, :storage_compensation, :persistence_failed],
      %{count: 1, failed_count: length(failed_keys)},
      %{
        enqueue_error: safe_error(enqueue_reason),
        persistence_error: safe_error(persistence_reason)
      }
    )
  end

  defp valid_storage_key?(storage_key) when is_binary(storage_key) do
    String.starts_with?(storage_key, "projects/") and String.contains?(storage_key, "/assets/")
  end

  defp valid_storage_key?(_storage_key), do: false

  defp safe_error(reason) when is_atom(reason), do: reason
  defp safe_error(%module{}), do: module
  defp safe_error({reason, _details}) when is_atom(reason), do: reason
  defp safe_error(_reason), do: :unexpected_error
end
