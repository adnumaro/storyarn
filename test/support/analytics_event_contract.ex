defmodule StoryarnTest.AnalyticsEventContract do
  @moduledoc false

  @behaviour Storyarn.Analytics.EventContract

  @impl true
  def event(:usage), do: {:ok, "test usage event", ~w(item_id mode)}
  def event(_event), do: :error

  @impl true
  def sanitize(:usage, %{item_id: item_id, mode: mode} = properties)
      when is_integer(item_id) and item_id > 0 and mode in ~w(create update) do
    {:ok, Map.take(properties, [:item_id, :mode])}
  end

  def sanitize(_event, _properties), do: :error
end
