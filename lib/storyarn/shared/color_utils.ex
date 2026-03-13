defmodule Storyarn.Shared.ColorUtils do
  @moduledoc """
  Color conversion utilities for theme customization.
  Converts hex colors to oklch format for daisyUI v5 compatibility.
  """

  @hex_regex ~r/^#[0-9a-fA-F]{6}$/

  @doc """
  Returns true if the string is a valid 6-digit hex color (e.g., "#ff0000").
  """
  @spec valid_hex?(String.t()) :: boolean()
  def valid_hex?(hex) when is_binary(hex), do: Regex.match?(@hex_regex, hex)
  def valid_hex?(_), do: false

  @doc """
  Converts a hex color string to an oklch() CSS string.

  ## Examples

      iex> hex_to_oklch("#ff0000")
      "oklch(63.27% 0.2577 29.23)"

      iex> hex_to_oklch("#00D4CC")
      "oklch(79.46% 0.1229 192.17)"
  """
  @spec hex_to_oklch(String.t()) :: String.t()
  def hex_to_oklch(hex) do
    {r, g, b} = hex_to_rgb(hex)
    {l, c, h} = rgb_to_oklch(r, g, b)
    "oklch(#{Float.round(l * 100, 2)}% #{Float.round(c, 4)} #{Float.round(h, 2)})"
  end

  @doc """
  Generates a darker variant of a hex color for gradient endpoints.
  Reduces lightness by the given amount (0.0-1.0 scale).
  """
  @spec darken_oklch(String.t(), float()) :: String.t()
  def darken_oklch(hex, amount \\ 0.1) do
    {r, g, b} = hex_to_rgb(hex)
    {l, c, h} = rgb_to_oklch(r, g, b)
    l2 = max(l - amount, 0.0)
    "oklch(#{Float.round(l2 * 100, 2)}% #{Float.round(c, 4)} #{Float.round(h + 15, 2)})"
  end

  defp hex_to_rgb("#" <> hex), do: hex_to_rgb(hex)

  defp hex_to_rgb(<<r::binary-size(2), g::binary-size(2), b::binary-size(2)>>) do
    {String.to_integer(r, 16) / 255, String.to_integer(g, 16) / 255,
     String.to_integer(b, 16) / 255}
  end

  defp rgb_to_oklch(r, g, b) do
    # sRGB → linear
    lr = to_linear(r)
    lg = to_linear(g)
    lb = to_linear(b)

    # Linear RGB → OKLab (via LMS)
    l_ = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
    m_ = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
    s_ = 0.0883024619 * lr + 0.2220049624 * lg + 0.6696925757 * lb

    l_cbrt = cbrt(l_)
    m_cbrt = cbrt(m_)
    s_cbrt = cbrt(s_)

    ok_l = 0.2104542553 * l_cbrt + 0.7936177850 * m_cbrt - 0.0040720468 * s_cbrt
    ok_a = 1.9779984951 * l_cbrt - 2.4285922050 * m_cbrt + 0.4505937099 * s_cbrt
    ok_b = 0.0259040371 * l_cbrt + 0.7827717662 * m_cbrt - 0.8086757660 * s_cbrt

    # OKLab → OKLCH
    c = :math.sqrt(ok_a * ok_a + ok_b * ok_b)

    h =
      if c < 0.0001 do
        0.0
      else
        h_rad = :math.atan2(ok_b, ok_a)
        h_deg = h_rad * 180 / :math.pi()
        if h_deg < 0, do: h_deg + 360, else: h_deg
      end

    {ok_l, c, h}
  end

  defp to_linear(v) when v <= 0.04045, do: v / 12.92
  defp to_linear(v), do: :math.pow((v + 0.055) / 1.055, 2.4)

  defp cbrt(x) when x >= 0, do: :math.pow(x, 1 / 3)
  defp cbrt(x), do: -:math.pow(-x, 1 / 3)
end
