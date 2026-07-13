defmodule Storyarn.Assets.StorageCompensation do
  @moduledoc false

  alias Storyarn.Assets.Storage
  alias Storyarn.Workers.DeleteStorageObjectsWorker

  require Logger

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

  @spec cleanup(reference()) :: :ok
  def cleanup(reference) when is_reference(reference) do
    storage_keys = reference |> tracked() |> Enum.uniq()

    case delete_storage_keys(storage_keys) do
      :ok -> :ok
      {:error, failed_keys} -> enqueue_cleanup(failed_keys)
    end

    discard(reference)
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

  @spec enqueue_cleanup([String.t()]) :: :ok | {:error, term()}
  def enqueue_cleanup(storage_keys) when is_list(storage_keys) do
    storage_keys = storage_keys |> Enum.filter(&valid_storage_key?/1) |> Enum.uniq()

    case storage_keys do
      [] ->
        :ok

      storage_keys ->
        case storage_keys |> then(&%{"storage_keys" => &1}) |> DeleteStorageObjectsWorker.new() |> Oban.insert() do
          {:ok, _job} ->
            :ok

          {:error, reason} ->
            Logger.error("Could not enqueue copied asset cleanup error=#{safe_error(reason)}")
            {:error, reason}
        end
    end
  end

  @spec discard(reference()) :: :ok
  def discard(reference) when is_reference(reference) do
    Process.delete(key(reference))
    :ok
  end

  defp tracked(reference), do: Process.get(key(reference), [])
  defp key(reference), do: {__MODULE__, reference}

  defp valid_storage_key?(storage_key) when is_binary(storage_key) do
    String.starts_with?(storage_key, "projects/") and String.contains?(storage_key, "/assets/")
  end

  defp valid_storage_key?(_storage_key), do: false

  defp safe_error(reason) when is_atom(reason), do: reason
  defp safe_error({reason, _details}) when is_atom(reason), do: reason
  defp safe_error(_reason), do: :unexpected_error
end
