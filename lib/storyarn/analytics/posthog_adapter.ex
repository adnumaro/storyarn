defmodule Storyarn.Analytics.PostHogAdapter do
  @moduledoc false

  require Logger

  def capture(%{event: event_name, distinct_id: distinct_id, properties: properties}) do
    event_name
    |> PostHog.capture(Map.put(properties, :distinct_id, distinct_id))
    |> handle_result()
  end

  def identify(%{distinct_id: distinct_id, properties: properties}) do
    "$identify"
    |> PostHog.capture(%{"$set" => properties, distinct_id: distinct_id})
    |> handle_result()
  end

  defp handle_result(:ok), do: :ok

  defp handle_result({:error, reason}) do
    Logger.debug("PostHog capture failed: #{inspect(reason)}")
    {:error, reason}
  end
end
