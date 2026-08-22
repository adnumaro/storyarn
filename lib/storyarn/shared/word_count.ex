defmodule Storyarn.Shared.WordCount do
  @moduledoc """
  Computes word counts for legacy Sheet consumers.

  Used at write time to denormalize word counts into the entity row,
  avoiding expensive HTML stripping + counting at query time.
  """

  alias Storyarn.Shared.HtmlUtils

  @doc """
  Computes word count for a sheet block's value map.

  Only text and rich_text blocks have meaningful word counts.
  Returns 0 for other block types or nil input.
  """
  @spec for_block_value(map() | nil) :: non_neg_integer()
  def for_block_value(nil), do: 0

  def for_block_value(value) when is_map(value) do
    value
    |> field("content", :content)
    |> text_word_count()
  end

  def for_block_value(_), do: 0

  @doc """
  Computes word count for a sheet block based on its type and value.

  Text and rich-text blocks use their content. All other block types return 0.
  """
  @spec for_block(String.t() | nil, map() | nil) :: non_neg_integer()
  def for_block(type, value) when type in ["text", "rich_text"], do: for_block_value(value)
  def for_block(_type, _value), do: 0

  @doc """
  Computes word count for a plain-text name (sheet name, table row name, etc.).

  Splits on whitespace and returns the number of words.
  Returns 0 for nil or empty input.
  """
  @spec for_name(String.t() | nil) :: non_neg_integer()
  def for_name(nil), do: 0
  def for_name(""), do: 0

  def for_name(name) when is_binary(name) do
    name |> String.split(~r/\s+/, trim: true) |> length()
  end

  # Persistence gives us string-keyed JSON maps, while public context APIs also
  # accept atom-keyed maps before their changesets normalize the payload.
  defp field(map, string_key, atom_key) do
    case Map.fetch(map, string_key) do
      {:ok, value} -> value
      :error -> Map.get(map, atom_key)
    end
  end

  defp text_word_count(text) when is_binary(text), do: HtmlUtils.word_count(text)
  defp text_word_count(_text), do: 0
end
