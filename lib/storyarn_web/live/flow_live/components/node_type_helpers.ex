defmodule StoryarnWeb.FlowLive.Components.NodeTypeHelpers do
  @moduledoc """
  Helper functions and components for flow node types.

  Type metadata (icons, labels, defaults) is delegated to `NodeTypeRegistry`.
  This module provides Phoenix components and utility functions.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  alias StoryarnWeb.FlowLive.NodeTypeRegistry

  @doc """
  Renders an icon for the given node type.

  ## Attributes

  * `:type` - Required. The node type string
  """
  attr :type, :string, required: true

  def node_type_icon(assigns) do
    assigns = assign(assigns, :icon, NodeTypeRegistry.icon_name(assigns.type))

    ~H"""
    <.icon name={@icon} class="size-4" />
    """
  end

  @doc "Returns the translated label for a node type."
  @spec node_type_label(String.t()) :: String.t()
  defdelegate node_type_label(type), to: NodeTypeRegistry, as: :label

  @doc "Returns the default data map for a given node type."
  @spec default_node_data(String.t()) :: map()
  defdelegate default_node_data(type), to: NodeTypeRegistry, as: :default_data

  @doc """
  Generates a technical ID with format: {flow_slug}_{speaker}_{speaker_count}

  ## Examples

      iex> generate_technical_id("intro", "Old Merchant", 1)
      "intro_old_merchant_1"

      iex> generate_technical_id("main_quest", nil, 3)
      "main_quest_narrator_3"

      iex> generate_technical_id(nil, "Guard", 1)
      "dlg_guard_1"
  """
  @spec generate_technical_id(String.t() | nil, String.t() | nil, pos_integer()) :: String.t()
  def generate_technical_id(flow_slug, speaker_name, speaker_count) do
    flow_part = normalize_for_id(flow_slug || "")
    speaker_part = normalize_for_id(speaker_name || "")

    flow_part = if flow_part == "", do: "dlg", else: flow_part
    speaker_part = if speaker_part == "", do: "narrator", else: speaker_part

    "#{flow_part}_#{speaker_part}_#{speaker_count}"
  end

  @doc """
  Generates a localization ID following i18n best practices.

  Uses hierarchical naming: dialogue.{context}.{unique_id}
  """
  @spec generate_localization_id(String.t() | nil) :: String.t()
  def generate_localization_id(context \\ nil) do
    suffix = unique_suffix()

    case normalize_for_id(context || "") do
      "" -> "dialogue.#{suffix}"
      ctx -> "dialogue.#{ctx}.#{suffix}"
    end
  end

  defp unique_suffix do
    :erlang.unique_integer([:positive])
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.slice(0, 6)
  end

  @doc """
  Counts words in a text string, stripping HTML tags first.
  """
  @spec word_count(String.t() | nil) :: non_neg_integer()
  def word_count(nil), do: 0
  def word_count(""), do: 0

  def word_count(text) do
    text
    |> strip_html()
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end

  defp normalize_for_id(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  defp normalize_for_id(_), do: ""

  defp strip_html(text) when is_binary(text) do
    text
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp strip_html(_), do: ""
end
