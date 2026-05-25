defmodule Storyarn.Scenes.RoutePoints do
  @moduledoc false

  @max_pause_ms 30_000

  def enough_points?(from_pin_id, to_pin_id, waypoints) do
    point_count(from_pin_id, to_pin_id, waypoints) >= 2
  end

  defp point_count(from_pin_id, to_pin_id, waypoints) do
    Enum.count([from_pin_id, to_pin_id], &present?/1) + length(waypoints || [])
  end

  def valid_waypoint?(%{"x" => x, "y" => y} = waypoint) when is_number(x) and is_number(y) do
    valid_stop? = Map.get(waypoint, "stop", false) in [true, false]
    pause_ms = waypoint_pause_ms(waypoint)
    valid_pause? = is_nil(pause_ms) or (is_integer(pause_ms) and pause_ms >= 0 and pause_ms <= @max_pause_ms)

    valid_stop? and valid_pause?
  end

  def valid_waypoint?(_), do: false

  def waypoint_pause_ms(waypoint) do
    Map.get(waypoint, "pause_ms") || Map.get(waypoint, "pauseMs")
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true
end
