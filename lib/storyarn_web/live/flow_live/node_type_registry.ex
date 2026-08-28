defmodule StoryarnWeb.FlowLive.NodeTypeRegistry do
  @moduledoc """
  Presentation registry for Flow node types.

  `Storyarn.Flows.NodeTypes` owns the domain vocabulary and authored data
  contract. This module maps those types to Web modules under
  `Nodes.{Type}.Node` for translated labels, icons and socket behavior.

  Consumers:
  - `Flows` owns default data, form normalization and duplication semantics
  - Web modules retain only presentation metadata and socket behavior
  - `NodeEventHandlers` delegates on_select and on_double_click
  """

  alias Phoenix.LiveView.Socket
  alias Storyarn.Flows

  @node_suffixes %{
    "annotation" => "Annotation",
    "entry" => "Entry",
    "exit" => "Exit",
    "dialogue" => "Dialogue",
    "hub" => "Hub",
    "condition" => "Condition",
    "instruction" => "Instruction",
    "jump" => "Jump",
    "subflow" => "Subflow"
  }

  @doc "All known node types."
  @spec types() :: [String.t()]
  defdelegate types(), to: Flows, as: :editor_node_types

  @doc "Node types that users can add via the 'Add Node' toolbar (excludes annotation and entry)."
  @spec user_addable_types() :: [String.t()]
  defdelegate user_addable_types(), to: Flows, as: :user_addable_node_types

  @doc "Returns the node module for a given type."
  @spec node_module(String.t()) :: module() | nil
  def node_module(type) do
    case Map.get(@node_suffixes, type) do
      nil -> nil
      suffix -> Module.concat(["StoryarnWeb", "FlowLive", "Nodes", suffix, "Node"])
    end
  end

  @doc "Returns the Lucide icon name for a node type."
  @spec icon_name(String.t()) :: String.t()
  def icon_name(type) do
    case node_module(type) do
      nil -> "circle"
      mod -> mod.icon_name()
    end
  end

  @doc "Returns the translated label for a node type."
  @spec label(String.t()) :: String.t()
  def label(type) do
    case node_module(type) do
      nil -> type
      mod -> mod.label()
    end
  end

  @doc "Returns a short description of what the node type does."
  @spec description(String.t()) :: String.t()
  def description(type) do
    case node_module(type) do
      nil -> ""
      mod -> mod.description()
    end
  end

  @doc "Returns the default data map for a given node type."
  @spec default_data(String.t()) :: map()
  defdelegate default_data(type), to: Flows, as: :default_node_data

  @doc "Extracts form-compatible data from a node based on its type."
  @spec extract_form_data(String.t(), map()) :: map()
  defdelegate extract_form_data(type, data), to: Flows, as: :node_form_data

  @doc "Returns the editing mode for double-click on a node type."
  @spec on_double_click(String.t(), map()) ::
          :toolbar | :dialogue_panel | :builder | {:navigate, any()}
  def on_double_click(type, node) do
    case node_module(type) do
      nil -> :toolbar
      mod -> mod.on_double_click(node)
    end
  end

  @doc "Performs extra work when a node is selected (e.g., hub loads referencing jumps)."
  @spec on_select(String.t(), map(), Socket.t()) :: Socket.t()
  def on_select(type, node, socket) do
    case node_module(type) do
      nil -> socket
      mod -> mod.on_select(node, socket)
    end
  end

  @doc "Transforms node data when duplicating (clears unique identifiers)."
  @spec duplicate_data_cleanup(String.t(), map()) :: map()
  defdelegate duplicate_data_cleanup(type, data), to: Flows, as: :duplicate_node_data
end
