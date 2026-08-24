defmodule Storyarn.Flows.WordCount do
  @moduledoc """
  Computes the player-facing word count of Flow node data.

  This is intentionally local to Flows. Sheet blocks may share the same HTML
  counting primitive, but they do not share this domain rule.
  """

  alias Storyarn.Platform.Shared.HtmlUtils

  @spec for_node_data(String.t(), map() | nil) :: non_neg_integer()
  def for_node_data(_type, nil), do: 0

  def for_node_data("dialogue", data) when is_map(data) do
    base_text = [
      field(data, "text", :text),
      field(data, "menu_text", :menu_text),
      field(data, "stage_directions", :stage_directions)
    ]

    response_text =
      case field(data, "responses", :responses) do
        responses when is_list(responses) -> Enum.map(responses, &response_text/1)
        _responses -> []
      end

    (base_text ++ response_text)
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&HtmlUtils.word_count/1)
    |> Enum.sum()
  end

  def for_node_data("exit", data) when is_map(data) do
    data
    |> field("label", :label)
    |> count_text()
  end

  def for_node_data(_type, _data), do: 0

  defp response_text(response) when is_map(response), do: field(response, "text", :text)
  defp response_text(_response), do: nil

  defp field(map, string_key, atom_key) do
    case Map.fetch(map, string_key) do
      {:ok, value} -> value
      :error -> Map.get(map, atom_key)
    end
  end

  defp count_text(text) when is_binary(text), do: HtmlUtils.word_count(text)
  defp count_text(_text), do: 0
end
