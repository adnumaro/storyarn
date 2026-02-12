defmodule Storyarn.Screenplays.CharacterExtension do
  @moduledoc """
  Pure functions for parsing screenplay character name extensions.

  Standard extensions: (V.O.), (O.S.), (CONT'D), (O.C.), (SUBTITLE).
  Parses `"JAIME (V.O.)"` → `%{base_name: "JAIME", extensions: ["V.O."]}`.
  """

  alias Storyarn.Screenplays.ContentUtils

  @type parsed :: %{base_name: String.t(), extensions: [String.t()]}

  @doc """
  Parses a character name string into base name and extensions.

  ## Examples

      iex> parse("JAIME (V.O.)")
      %{base_name: "JAIME", extensions: ["V.O."]}

      iex> parse("JAIME")
      %{base_name: "JAIME", extensions: []}
  """
  @spec parse(String.t() | nil) :: parsed()
  def parse(nil), do: %{base_name: "", extensions: []}
  def parse(""), do: %{base_name: "", extensions: []}

  def parse(content) when is_binary(content) do
    plain = ContentUtils.strip_html(content)

    extensions =
      ~r/\(([^)]+)\)/
      |> Regex.scan(plain)
      |> Enum.map(fn [_, ext] -> String.trim(ext) end)

    base_name =
      plain
      |> String.replace(~r/\s*\([^)]+\)/, "")
      |> String.trim()

    %{base_name: base_name, extensions: extensions}
  end

  @doc """
  Returns the base name without any extensions.

  ## Examples

      iex> base_name("JAIME (V.O.) (CONT'D)")
      "JAIME"
  """
  @spec base_name(String.t() | nil) :: String.t()
  def base_name(content), do: parse(content).base_name

  @doc """
  Returns the base name for a screenplay element, using sheet lookup when available.

  If the element has a `sheet_id` in its data, looks up the sheet name from `sheets_map`
  and uppercases it. Otherwise falls back to `base_name/1` on the element's content.
  """
  @spec base_name_from_element(map(), map()) :: String.t()
  def base_name_from_element(%{data: %{"sheet_id" => sheet_id}} = _element, sheets_map)
      when not is_nil(sheet_id) do
    sheet_id = if is_binary(sheet_id), do: String.to_integer(sheet_id), else: sheet_id

    case Map.get(sheets_map, sheet_id) do
      nil -> ""
      sheet -> String.upcase(sheet.name)
    end
  end

  def base_name_from_element(element, _sheets_map) do
    base_name(element.content)
  end

  @doc """
  Checks if content already includes a CONT'D extension.

  ## Examples

      iex> has_contd?("JAIME (CONT'D)")
      true

      iex> has_contd?("JAIME")
      false
  """
  @spec has_contd?(String.t() | nil) :: boolean()
  def has_contd?(nil), do: false
  def has_contd?(""), do: false

  def has_contd?(content) when is_binary(content) do
    content
    |> parse()
    |> Map.get(:extensions, [])
    |> Enum.any?(&(String.upcase(&1) == "CONT'D"))
  end
end
