defmodule Storyarn.SnapshotReadSwitchStorage do
  @moduledoc false

  @behaviour Storyarn.Assets.Storage

  alias Storyarn.Assets.Storage.Local

  def start_link(replacements) when is_map(replacements) do
    Agent.start_link(
      fn ->
        %{
          counts: %{},
          replacements: replacements,
          content_type_overrides: %{},
          put_content_types: %{},
          presigned_download_result: {:error, :not_supported},
          stat_result: :delegate,
          stream_result: :delegate,
          io_observer: nil,
          namespace_observer: nil,
          namespace_fingerprint_override: nil
        }
      end,
      name: __MODULE__
    )
  end

  def reset_counts do
    Agent.update(__MODULE__, &%{&1 | counts: %{}})
  end

  def stream_count(key) do
    Agent.get(__MODULE__, &Map.get(&1.counts, key, 0))
  end

  def override_content_type(key, content_type) do
    Agent.update(__MODULE__, &put_in(&1, [:content_type_overrides, key], content_type))
  end

  def put_content_type(key) do
    Agent.get(__MODULE__, &Map.get(&1.put_content_types, key))
  end

  def set_presigned_download_result(result) do
    Agent.update(__MODULE__, &%{&1 | presigned_download_result: result})
  end

  def set_stat_result(result) do
    Agent.update(__MODULE__, &%{&1 | stat_result: result})
  end

  def set_stream_result(result) do
    Agent.update(__MODULE__, &%{&1 | stream_result: result})
  end

  def observe_io(callback) when is_function(callback, 2) do
    Agent.update(__MODULE__, &%{&1 | io_observer: callback})
  end

  def observe_namespace(callback) when is_function(callback, 1) do
    Agent.update(__MODULE__, &%{&1 | namespace_observer: callback})
  end

  def override_namespace_fingerprint(fingerprint) when is_binary(fingerprint) do
    Agent.update(__MODULE__, &%{&1 | namespace_fingerprint_override: fingerprint})
  end

  @impl true
  defdelegate list_prefix(prefix, opts), to: Local

  @impl true
  def stream(key, offset, length, opts) do
    case Agent.get(__MODULE__, & &1.stream_result) do
      :delegate -> delegated_stream(key, offset, length, opts)
      callback when is_function(callback, 4) -> callback.(key, offset, length, opts)
      result -> result
    end
  end

  defp delegated_stream(key, offset, length, opts) do
    read_number =
      Agent.get_and_update(__MODULE__, fn state ->
        read_number = Map.get(state.counts, key, 0) + 1
        {read_number, put_in(state, [:counts, key], read_number)}
      end)

    replacement = Agent.get(__MODULE__, &Map.get(&1.replacements, key))

    result =
      if read_number > 1 and is_binary(replacement),
        do: {:ok, [{:ok, replacement}]},
        else: Local.stream(key, offset, length, opts)

    case result do
      {:ok, chunks} -> {:ok, Stream.map(chunks, &observe_chunk(&1, key))}
      {:error, _reason} = error -> error
    end
  end

  @impl true
  defdelegate upload(key, data, content_type), to: Local

  @impl true
  def upload_stream(key, chunks, content_type) do
    observed_chunks =
      Stream.map(chunks, fn
        {:ok, chunk} = item when is_binary(chunk) ->
          observe_io({:upload_stream_chunk, byte_size(chunk)}, key)
          item

        item ->
          item
      end)

    result = Local.upload_stream(key, observed_chunks, content_type)
    if match?({:ok, _url}, result), do: observe_io(:upload_stream, key)
    result
  end

  @impl true
  def put_if_absent(key, data, content_type) do
    Agent.update(__MODULE__, &put_in(&1, [:put_content_types, key], content_type))
    result = Local.put_if_absent(key, data, content_type)
    if match?({:ok, _url, true}, result), do: observe_io(:put_if_absent, key)
    result
  end

  @impl true
  defdelegate delete(key), to: Local

  @impl true
  defdelegate delete_if_matches(key, identity), to: Local

  @impl true
  def namespace_fingerprint do
    result =
      case Agent.get(__MODULE__, & &1.namespace_fingerprint_override) do
        nil -> Local.namespace_fingerprint()
        fingerprint -> {:ok, fingerprint}
      end

    case result do
      {:ok, fingerprint} -> notify_namespace(fingerprint)
      {:error, reason} -> notify_namespace(reason)
    end

    result
  end

  @impl true
  defdelegate get_url(key), to: Local

  @impl true
  defdelegate download(key), to: Local

  @impl true
  def stat(key) do
    observe_io(:stat, key)

    case Agent.get(__MODULE__, & &1.stat_result) do
      :delegate -> delegated_stat(key)
      callback when is_function(callback, 1) -> callback.(key)
      result -> result
    end
  end

  defp delegated_stat(key) do
    with {:ok, stat} <- Local.stat(key) do
      case Agent.get(__MODULE__, &Map.fetch(&1.content_type_overrides, key)) do
        {:ok, content_type} -> {:ok, %{stat | content_type: content_type}}
        :error -> {:ok, stat}
      end
    end
  end

  @impl true
  defdelegate presigned_upload_url(key, content_type, opts), to: Local

  @impl true
  def presigned_download_url(_key, _content_type, _opts) do
    case Agent.get(__MODULE__, & &1.presigned_download_result) do
      callback when is_function(callback, 0) -> callback.()
      result -> result
    end
  end

  @impl true
  defdelegate copy(source_key, destination_key), to: Local

  @impl true
  def copy_if_absent(source_key, destination_key) do
    result = Local.copy_if_absent(source_key, destination_key)
    if match?({:ok, true}, result), do: observe_io(:copy_if_absent, destination_key)
    result
  end

  @impl true
  defdelegate key_from_url(url), to: Local

  defp observe_chunk(chunk, key) do
    observe_io(:stream_chunk, key)
    chunk
  end

  defp observe_io(operation, key) do
    case Agent.get(__MODULE__, & &1.io_observer) do
      callback when is_function(callback, 2) -> callback.(operation, key)
      nil -> :ok
    end
  end

  defp notify_namespace(value) do
    case Agent.get(__MODULE__, & &1.namespace_observer) do
      callback when is_function(callback, 1) -> callback.(value)
      nil -> :ok
    end
  end
end
