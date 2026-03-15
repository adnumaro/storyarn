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

  @node_suffixes %{
    "annotation" => "Annotation",
    "entry" => "Entry",
    "exit" => "Exit",
    "dialogue" => "Dialogue",
    "hub" => "Hub",
    "condition" => "Condition",
    "instruction" => "Instruction",
    "jump" => "Jump",
    "subflow" => "Subflow",
    "slug_line" => "SlugLine"
  }

  @types Map.keys(@node_suffixes) |> Enum.sort()

  @doc "All known node types."
  @spec types() :: [String.t()]
  def types, do: @types

  @doc "Node types that users can add via the 'Add Node' toolbar (excludes annotation and entry)."
  @spec user_addable_types() :: [String.t()]
  def user_addable_types, do: @types -- ["annotation", "entry"]

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
  @spec on_double_click(String.t(), map()) :: :toolbar | :editor | :builder | {:navigate, any()}
  def on_double_click(type, node) do
    case node_module(type) do
      nil -> :toolbar
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
