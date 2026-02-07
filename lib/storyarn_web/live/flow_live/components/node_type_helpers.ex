defmodule StoryarnWeb.FlowLive.Components.NodeTypeHelpers do
  @moduledoc """
  Shared Phoenix components and utility functions for flow node types.

  Type metadata (icons, labels, defaults) is delegated to `NodeTypeRegistry`.
  Type-specific logic lives in `Nodes.{Type}.Node` modules.
  """

  use Phoenix.Component

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

  defp strip_html(text) when is_binary(text) do
    text
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp strip_html(_), do: ""
end
