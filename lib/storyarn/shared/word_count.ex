defmodule Storyarn.Shared.WordCount do
  @moduledoc """
  Computes word counts for flow nodes and sheet blocks.

  Used at write time to denormalize word counts into the entity row,
  avoiding expensive HTML stripping + counting at query time.
  """

  alias Storyarn.Shared.HtmlUtils

  @doc """
  Computes word count for a dialogue flow node's data map.

  Counts words in: text, menu_text, stage_directions, and all response texts.
  Returns 0 for non-dialogue data or nil input.
  """
  @spec for_node_data(map() | nil) :: non_neg_integer()
  def for_node_data(nil), do: 0

  def for_node_data(data) when is_map(data) do
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
end
