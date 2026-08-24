defmodule Storyarn.Sheets.WordCount do
  @moduledoc """
  Computes word counts according to the Sheet runtime content contract.

  HTML handling is a technical primitive shared with other consumers; deciding
  which Sheet fields count is owned here by Sheets.
  """

  alias Storyarn.Platform.Shared.HtmlUtils

  @spec for_block_value(map() | nil) :: non_neg_integer()
  def for_block_value(nil), do: 0

  def for_block_value(value) when is_map(value) do
    value
    |> field("content", :content)
    |> count_text()
  end

  def for_block_value(_value), do: 0

  @spec for_block(String.t() | nil, map() | nil) :: non_neg_integer()
  def for_block(type, value) when type in ["text", "rich_text"], do: for_block_value(value)
  def for_block(_type, _value), do: 0

  @spec for_name(String.t() | nil) :: non_neg_integer()
  def for_name(name), do: count_text(name)

  defp field(map, string_key, atom_key) do
    case Map.fetch(map, string_key) do
      {:ok, value} -> value
      :error -> Map.get(map, atom_key)
    end
  end

  defp count_text(text) when is_binary(text), do: HtmlUtils.word_count(text)
  defp count_text(_text), do: 0
end
