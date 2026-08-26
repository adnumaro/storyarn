defmodule Storyarn.Flows.HubColors do
  @moduledoc """
  Hub node color utilities.

  Hub colors are stored as hex strings. The current contract accepts only valid
  hex values, while `resolve_legacy/1` is reserved for historical boundaries
  that must translate the former named-color representation.
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

  @doc "Returns a valid current Hub color, falling back to the default."
  @spec resolve(term()) :: String.t()
  def resolve(color) when is_binary(color) do
    if String.match?(color, @hex_color_regex), do: color, else: @default_hex
  end

  def resolve(_color), do: @default_hex

  @doc """
  Resolves a historical named Hub color to hex.

  Use only when reading snapshots or imports created under the former
  named-color contract. Current write paths must use `resolve/1`.
  """
  @spec resolve_legacy(term()) :: String.t()
  def resolve_legacy(color) when is_binary(color) do
    Map.get(@legacy_colors, color, resolve(color))
  end

  def resolve_legacy(color), do: resolve(color)
end
