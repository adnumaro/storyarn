defmodule Storyarn.Shared.WordCount do
  @moduledoc """
  Computes word counts for flow nodes and sheet blocks.

  Used at write time to denormalize word counts into the entity row,
  avoiding expensive HTML stripping + counting at query time.
  """

  alias Storyarn.Shared.HtmlUtils

  @doc """
  Computes word count for a flow node's data map.

  Supports dialogue nodes (text, menu_text, stage_directions, response texts)
  and exit labels.
  Returns 0 for other node types or nil input.
  """
  @spec for_node_data(String.t(), map() | nil) :: non_neg_integer()
  def for_node_data(_type, nil), do: 0

  def for_node_data("dialogue", data) when is_map(data) do
    base = [
      field(data, "text", :text),
      field(data, "menu_text", :menu_text),
      field(data, "stage_directions", :stage_directions)
    ]

    response_texts =
      case field(data, "responses", :responses) do
        responses when is_list(responses) -> Enum.map(responses, &response_text/1)
        _ -> []
      end

    (base ++ response_texts)
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&HtmlUtils.word_count/1)
    |> Enum.sum()
  end

  def for_node_data("exit", data) when is_map(data) do
    data
    |> field("label", :label)
    |> text_word_count()
  end

  def for_node_data(_type, _data), do: 0

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

  defp response_text(response) when is_map(response), do: field(response, "text", :text)
  defp response_text(_response), do: nil

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
