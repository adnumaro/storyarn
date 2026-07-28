defmodule Storyarn.Flows.NodeLabel do
  @moduledoc false

  alias Storyarn.Shared.HtmlUtils
  alias Storyarn.Shared.StringUtils

  @max_text_length 48

  @spec for_node(map()) :: String.t()
  def for_node(%{type: type, data: data}) do
    specific_for_node(%{type: type, data: data}) || type_label(type)
  end

  def for_node(%{type: type}), do: type_label(type)
  def for_node(_node), do: "Node"

  @spec specific_for_node(map()) :: String.t() | nil
  def specific_for_node(%{data: data}) do
    data = data || %{}

    Enum.find(
      [data["technical_id"], data["label"], text_label(data["text"])],
      &(not StringUtils.blank?(&1))
    )
  end

  def specific_for_node(_node), do: nil

  @spec type_label(term()) :: String.t()
  def type_label(type) when is_binary(type) do
    type
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  def type_label(_type), do: "Node"

  defp text_label(text) when is_binary(text) do
    text
    |> HtmlUtils.strip_html()
    |> String.trim()
    |> String.slice(0, @max_text_length)
  end

  defp text_label(_text), do: nil
end
