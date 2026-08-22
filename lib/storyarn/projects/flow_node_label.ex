defmodule Storyarn.Projects.FlowNodeLabel do
  @moduledoc false

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Shared.HtmlUtils
  alias Storyarn.Shared.StringUtils

  @max_text_length 48

  @spec for_node(map()) :: String.t()
  def for_node(%{type: type, data: data}) do
    specific_for_node(%{type: type, data: data}) || type_label(type)
  end

  def for_node(%{type: type}), do: type_label(type)
  def for_node(_node), do: type_label(nil)

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
  def type_label("annotation"), do: dgettext("flows", "Note")
  def type_label("condition"), do: dgettext("flows", "Condition")
  def type_label("dialogue"), do: dgettext("flows", "Dialogue")
  def type_label("entry"), do: dgettext("flows", "Entry")
  def type_label("exit"), do: dgettext("flows", "Exit")
  def type_label("hub"), do: dgettext("flows", "Hub")
  def type_label("instruction"), do: dgettext("flows", "Instruction")
  def type_label("jump"), do: dgettext("flows", "Jump")
  def type_label("sequence"), do: dgettext("flows", "Sequence")
  def type_label("subflow"), do: dgettext("flows", "Subflow")

  def type_label(type) when is_binary(type) do
    type
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  def type_label(_type), do: dgettext("flows", "Node")

  defp text_label(text) when is_binary(text) do
    text
    |> HtmlUtils.strip_html()
    |> String.trim()
    |> String.slice(0, @max_text_length)
  end

  defp text_label(_text), do: nil
end
