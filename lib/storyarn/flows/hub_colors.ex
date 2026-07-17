defmodule Storyarn.Flows.HubColors do
  @moduledoc """
  Hub node color utilities.

  Hub colors are stored as hex strings. Historical named colors are accepted
  at persistence boundaries so old snapshots and imports retain their intended
  color; invalid or missing values resolve to the default.
  """

  @default_hex "#be185d"
  @legacy_colors %{
    "purple" => "#8b5cf6",
    "blue" => "#3b82f6",
    "green" => "#22c55e",
    "yellow" => "#f59e0b",
    "amber" => "#f59e0b",
    "red" => "#ef4444",
    "pink" => "#ec4899",
    "orange" => "#f97316",
    "cyan" => "#06b6d4"
  }
  @hex_color_regex ~r/\A#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\z/

  @doc "Returns the default color hex value."
  @spec default_hex() :: String.t()
  def default_hex, do: @default_hex

  @doc "Returns a valid hub color, falling back to the default."
  @spec resolve(term()) :: String.t()
  def resolve(color) when is_binary(color) do
    if String.match?(color, @hex_color_regex),
      do: color,
      else: Map.get(@legacy_colors, color, @default_hex)
  end

  def resolve(_color), do: @default_hex
end
