defmodule Storyarn.Flows.HubColors do
  @moduledoc """
  Hub node color utilities.

  Hub colors are stored as hex strings. Invalid or missing values resolve to
  the default color so malformed imports cannot leak into the editor.
  """

  @default_hex "#be185d"
  @hex_color_regex ~r/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/

  @doc "Returns the default color hex value."
  @spec default_hex() :: String.t()
  def default_hex, do: @default_hex

  @doc "Returns a valid hub color, falling back to the default."
  @spec resolve(term()) :: String.t()
  def resolve(color) when is_binary(color) do
    if String.match?(color, @hex_color_regex), do: color, else: @default_hex
  end

  def resolve(_color), do: @default_hex
end
