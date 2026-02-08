defmodule StoryarnWeb.FlowLive.NodeTypeRegistry do
  @moduledoc """
  Single source of truth for flow node type definitions.

  Aggregates per-type modules via a lookup map.
  Each node type is defined in its own module under `Nodes.{Type}.Node`.

  Consumers:
  - `NodeTypeHelpers` delegates icon_name, label, default_data
  - `FormHelpers` delegates extract_form_data
  - `NodeHelpers` delegates duplicate_data_cleanup
  - `NodeEventHandlers` delegates on_select, on_double_click
  """

  alias StoryarnWeb.FlowLive.Nodes

  @node_modules %{
    "entry" => Nodes.Entry.Node,
    "exit" => Nodes.Exit.Node,
    "dialogue" => Nodes.Dialogue.Node,
    "hub" => Nodes.Hub.Node,
    "condition" => Nodes.Condition.Node,
    "instruction" => Nodes.Instruction.Node,
    "jump" => Nodes.Jump.Node,
    "subflow" => Nodes.Subflow.Node
  }

  @sidebar_modules %{
    "entry" => Nodes.Entry.ConfigSidebar,
    "exit" => Nodes.Exit.ConfigSidebar,
    "dialogue" => Nodes.Dialogue.ConfigSidebar,
    "hub" => Nodes.Hub.ConfigSidebar,
    "condition" => Nodes.Condition.ConfigSidebar,
    "instruction" => Nodes.Instruction.ConfigSidebar,
    "jump" => Nodes.Jump.ConfigSidebar,
    "subflow" => Nodes.Subflow.ConfigSidebar
  }

  @types Map.keys(@node_modules) |> Enum.sort()

  @doc "All known node types."
  @spec types() :: [String.t()]
  def types, do: @types

  @doc "Node types that users can add via the toolbar."
  @spec user_addable_types() :: [String.t()]
  def user_addable_types, do: @types -- ["entry"]

  @doc "Returns the node module for a given type."
  @spec node_module(String.t()) :: module() | nil
  def node_module(type), do: Map.get(@node_modules, type)

  @doc "Returns the sidebar module for a given type."
  @spec sidebar_module(String.t()) :: module() | nil
  def sidebar_module(type), do: Map.get(@sidebar_modules, type)

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

  @doc "Returns the default data map for a given node type."
  @spec default_data(String.t()) :: map()
  def default_data(type) do
    case node_module(type) do
      nil -> %{}
      mod -> mod.default_data()
    end
  end

  @doc "Extracts form-compatible data from a node based on its type."
  @spec extract_form_data(String.t(), map()) :: map()
  def extract_form_data(type, data) do
    case node_module(type) do
      nil -> %{}
      mod -> mod.extract_form_data(data)
    end
  end

  @doc "Returns the editing mode for double-click on a node type."
  @spec on_double_click(String.t(), map()) :: :sidebar | :screenplay | {:navigate, any()}
  def on_double_click(type, node) do
    case node_module(type) do
      nil -> :sidebar
      mod -> mod.on_double_click(node)
    end
  end

  @doc "Performs extra work when a node is selected (e.g., hub loads referencing jumps)."
  @spec on_select(String.t(), map(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def on_select(type, node, socket) do
    case node_module(type) do
      nil -> socket
      mod -> mod.on_select(node, socket)
    end
  end

  @doc "Transforms node data when duplicating (clears unique identifiers)."
  @spec duplicate_data_cleanup(String.t(), map()) :: map()
  def duplicate_data_cleanup(type, data) do
    case node_module(type) do
      nil -> data
      mod -> mod.duplicate_data_cleanup(data)
    end
  end
end
