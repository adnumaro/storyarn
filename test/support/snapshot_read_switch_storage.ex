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
          io_observer: nil,
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

  def observe_io(callback) when is_function(callback, 2) do
    Agent.update(__MODULE__, &%{&1 | io_observer: callback})
  end

  def override_namespace_fingerprint(fingerprint) when is_binary(fingerprint) do
    Agent.update(__MODULE__, &%{&1 | namespace_fingerprint_override: fingerprint})
  end

  @impl true
  defdelegate list_prefix(prefix, opts), to: Local

  @impl true
  def stream(key, offset, length, opts) do
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
  defdelegate upload_stream(key, chunks, content_type), to: Local

  @impl true
  defdelegate put_if_absent(key, data, content_type), to: Local

  @impl true
  defdelegate delete(key), to: Local

  @impl true
  defdelegate delete_if_matches(key, identity), to: Local

  @impl true
  def namespace_fingerprint do
    case Agent.get(__MODULE__, & &1.namespace_fingerprint_override) do
      nil -> Local.namespace_fingerprint()
      fingerprint -> {:ok, fingerprint}
    end
  end

  @impl true
  defdelegate get_url(key), to: Local

  @impl true
  defdelegate download(key), to: Local

  @impl true
  def stat(key) do
    observe_io(:stat, key)

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
  defdelegate copy(source_key, destination_key), to: Local

  @impl true
  defdelegate copy_if_absent(source_key, destination_key), to: Local

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
end
