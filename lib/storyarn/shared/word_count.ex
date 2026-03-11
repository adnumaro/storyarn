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
  and slug_line nodes (description, sub_location, time_of_day).
  Returns 0 for other node types or nil input.
  """
  @spec for_node_data(String.t(), map() | nil) :: non_neg_integer()
  def for_node_data(_type, nil), do: 0

  def for_node_data("dialogue", data) when is_map(data) do
    base = [data["text"], data["menu_text"], data["stage_directions"]]

    response_texts =
      case data["responses"] do
        rs when is_list(rs) -> Enum.map(rs, & &1["text"])
        _ -> []
      end

    (base ++ response_texts)
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.map(&HtmlUtils.word_count/1)
    |> Enum.sum()
  end

  def for_node_data("slug_line", data) when is_map(data) do
    [data["description"], data["sub_location"], data["time_of_day"]]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.map(&HtmlUtils.word_count/1)
    |> Enum.sum()
  end

  def for_node_data(_type, _data), do: 0

  # Backward-compatible arity-1 clause for dialogue-only callers
  @doc false
  @spec for_node_data(map() | nil) :: non_neg_integer()
  def for_node_data(nil), do: 0
  def for_node_data(data) when is_map(data), do: for_node_data("dialogue", data)
  def for_node_data(_), do: 0

  @doc """
  Computes word count for a sheet block's value map.

  Only text and rich_text blocks have meaningful word counts.
  Returns 0 for other block types or nil input.
  """
  @spec for_block_value(map() | nil) :: non_neg_integer()
  def for_block_value(nil), do: 0

  def for_block_value(%{"content" => content}) when is_binary(content) and content != "" do
    HtmlUtils.word_count(content)
  end

  def for_block_value(_), do: 0

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
end
