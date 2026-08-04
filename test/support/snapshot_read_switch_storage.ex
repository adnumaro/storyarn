defmodule Storyarn.SnapshotReadSwitchStorage do
  @moduledoc false

  @behaviour Storyarn.Assets.Storage

  alias Storyarn.Assets.Storage.Local

  def start_link(replacements) when is_map(replacements) do
    Agent.start_link(fn -> %{counts: %{}, replacements: replacements} end, name: __MODULE__)
  end

  def reset_counts do
    Agent.update(__MODULE__, &%{&1 | counts: %{}})
  end

  def stream_count(key) do
    Agent.get(__MODULE__, &Map.get(&1.counts, key, 0))
  end

  @impl true
  def stream(key, offset, length, opts) do
    read_number =
      Agent.get_and_update(__MODULE__, fn state ->
        read_number = Map.get(state.counts, key, 0) + 1
        {read_number, put_in(state, [:counts, key], read_number)}
      end)

    replacement = Agent.get(__MODULE__, &Map.get(&1.replacements, key))

    if read_number > 1 and is_binary(replacement),
      do: {:ok, [{:ok, replacement}]},
      else: Local.stream(key, offset, length, opts)
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
  defdelegate get_url(key), to: Local

  @impl true
  defdelegate download(key), to: Local

  @impl true
  defdelegate stat(key), to: Local

  @impl true
  defdelegate presigned_upload_url(key, content_type, opts), to: Local

  @impl true
  defdelegate copy(source_key, destination_key), to: Local

  @impl true
  defdelegate copy_if_absent(source_key, destination_key), to: Local

  @impl true
  defdelegate key_from_url(url), to: Local
end
