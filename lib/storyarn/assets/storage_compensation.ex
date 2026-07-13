defmodule Storyarn.Assets.StorageCompensation do
  @moduledoc false

  alias Storyarn.Assets.Storage
  alias Storyarn.Workers.DeleteStorageObjectsWorker

  require Logger

  @enqueue_attempts 3
  @enqueue_retry_delay_ms 25

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
    storage_keys = reference |> tracked() |> Enum.uniq()
    enqueue_fun = Keyword.get(opts, :enqueue_fun, &enqueue_cleanup/1)
    delete_fun = Keyword.get(opts, :delete_fun, &delete_storage_keys/1)

    case storage_keys do
      [] ->
        discard(reference)

      storage_keys ->
        persist_or_delete_cleanup(reference, storage_keys, enqueue_fun, delete_fun)
    end
  end

  @spec delete_storage_keys([String.t()]) :: :ok | {:error, [String.t()]}
  def delete_storage_keys(storage_keys) when is_list(storage_keys) do
    failed_keys =
      storage_keys
      |> Enum.filter(&valid_storage_key?/1)
      |> Enum.uniq()
      |> Enum.filter(fn storage_key ->
        case Storage.delete(storage_key) do
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

  @spec discard(reference()) :: :ok
  def discard(reference) when is_reference(reference) do
    Process.delete(key(reference))
    :ok
  end

  defp tracked(reference), do: Process.get(key(reference), [])
  defp key(reference), do: {__MODULE__, reference}

  defp persist_or_delete_cleanup(reference, storage_keys, enqueue_fun, delete_fun) do
    case enqueue_fun.(storage_keys) do
      :ok ->
        _result = delete_fun.(storage_keys)
        discard(reference)

      {:error, enqueue_reason} ->
        case delete_fun.(storage_keys) do
          :ok ->
            discard(reference)

          {:error, failed_keys} ->
            failed_keys = failed_keys |> Enum.filter(&valid_storage_key?/1) |> Enum.uniq()
            Process.put(key(reference), failed_keys)
            report_unpersisted_cleanup(failed_keys, enqueue_reason)
            {:error, {:storage_cleanup_not_persisted, enqueue_reason}}
        end
    end
  end

  defp enqueue_with_retry(storage_keys, insert_fun, attempts, retry_delay_ms) when attempts > 0 do
    case insert_fun.(storage_keys) do
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

  defp report_unpersisted_cleanup(failed_keys, reason) do
    Logger.error(
      "Copied asset cleanup could not be completed or persisted failed_count=#{length(failed_keys)} error=#{safe_error(reason)}"
    )

    :telemetry.execute(
      [:storyarn, :assets, :storage_compensation, :persistence_failed],
      %{count: 1, failed_count: length(failed_keys)},
      %{error: safe_error(reason)}
    )
  end

  defp valid_storage_key?(storage_key) when is_binary(storage_key) do
    String.starts_with?(storage_key, "projects/") and String.contains?(storage_key, "/assets/")
  end

  defp valid_storage_key?(_storage_key), do: false

  defp safe_error(reason) when is_atom(reason), do: reason
  defp safe_error({reason, _details}) when is_atom(reason), do: reason
  defp safe_error(_reason), do: :unexpected_error
end
