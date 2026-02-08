defmodule Storyarn.Flows.HubColors do
  @moduledoc """
  Hub node color utilities.

  All colors are stored and resolved as hex strings.
  """

  @default_hex "#8b5cf6"

  @doc "Returns the default color hex value."
  @spec default_hex() :: String.t()
  def default_hex, do: @default_hex

  @doc "Passes through a hex color, falling back to default for nil."
  @spec to_hex(String.t() | nil) :: String.t() | nil
  def to_hex(nil), do: nil
  def to_hex(hex), do: hex

  @doc "Passes through a hex color, falling back to default for nil or empty."
  @spec to_hex(String.t() | nil, String.t()) :: String.t()
  def to_hex(nil, default), do: default
  def to_hex("", default), do: default
  def to_hex(hex, _default), do: hex
end
