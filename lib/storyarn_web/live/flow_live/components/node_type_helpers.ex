defmodule StoryarnWeb.FlowLive.Components.NodeTypeHelpers do
  @moduledoc """
  Helper functions and components for flow node types.

  Provides:
  - `node_type_icon/1` - Component to render the appropriate icon for a node type
  - `node_type_label/1` - Returns the translated label for a node type
  - `default_node_data/1` - Returns the default data structure for a node type
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.CoreComponents, only: [icon: 1]

  @doc """
  Renders an icon for the given node type.

  ## Attributes

  * `:type` - Required. The node type string ("dialogue", "hub", "condition", "instruction", "jump")
  """
  attr :type, :string, required: true

  def node_type_icon(assigns) do
    icon =
      case assigns.type do
        "dialogue" -> "message-square"
        "hub" -> "git-merge"
        "condition" -> "git-branch"
        "instruction" -> "zap"
        "jump" -> "arrow-right"
        _ -> "circle"
      end

    assigns = assign(assigns, :icon, icon)

    ~H"""
    <.icon name={@icon} class="size-4" />
    """
  end

  @doc """
  Returns the translated label for a node type.

  ## Examples

      iex> node_type_label("dialogue")
      "Dialogue"
  """
  @spec node_type_label(String.t()) :: String.t()
  def node_type_label(type) do
    case type do
      "dialogue" -> gettext("Dialogue")
      "hub" -> gettext("Hub")
      "condition" -> gettext("Condition")
      "instruction" -> gettext("Instruction")
      "jump" -> gettext("Jump")
      _ -> type
    end
  end

  @doc """
  Returns the default data map for a given node type.

  ## Examples

      iex> default_node_data("dialogue")
      %{"speaker_page_id" => nil, "text" => "", "responses" => []}
  """
  @spec default_node_data(String.t()) :: map()
  def default_node_data(type) do
    case type do
      "dialogue" -> %{"speaker_page_id" => nil, "text" => "", "responses" => []}
      "hub" -> %{"label" => ""}
      "condition" -> %{"expression" => ""}
      "instruction" -> %{"action" => "", "parameters" => ""}
      "jump" -> %{"target_flow" => "", "target_node" => ""}
      _ -> %{}
    end
  end
end
