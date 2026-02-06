defmodule Storyarn.Flows.HubColors do
  @moduledoc """
  Single source of truth for hub node color definitions.

  Used by:
  - `SimplePanels` for the color dropdown options
  - `Flows.serialize_for_canvas/1` to resolve hex values for the JS canvas
  """

  @colors %{
    "purple" => "#8b5cf6",
    "blue" => "#3b82f6",
    "green" => "#22c55e",
    "yellow" => "#f59e0b",
    "red" => "#ef4444",
    "pink" => "#ec4899",
    "orange" => "#f97316",
    "cyan" => "#06b6d4"
  }

  @doc "Returns all color names."
  @spec names() :: [String.t()]
  def names, do: Map.keys(@colors) |> Enum.sort()

  @doc "Resolves a color name to its hex value. Returns nil if not found."
  @spec to_hex(String.t()) :: String.t() | nil
  def to_hex(name), do: Map.get(@colors, name)

  @doc "Resolves a color name to hex, falling back to the default purple."
  @spec to_hex(String.t(), String.t()) :: String.t()
  def to_hex(name, default), do: Map.get(@colors, name, default)

  @doc "Returns the default color hex value (purple)."
  @spec default_hex() :: String.t()
  def default_hex, do: @colors["purple"]
end
