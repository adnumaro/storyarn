defmodule StoryarnTest.AnalyticsBrokenEventContract do
  @moduledoc false

  @behaviour Storyarn.Platform.Analytics.EventContract

  @impl true
  def event(_event), do: raise("broken analytics contract")

  @impl true
  def sanitize(_event, properties), do: {:ok, properties}
end
