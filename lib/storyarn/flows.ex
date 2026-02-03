defmodule Storyarn.Flows do
  @moduledoc """
  The Flows context.

  Manages flows (visual graphs), nodes, and connections within a project.
  Flows are used to represent narrative structure, dialogue trees, and game logic.

  This module serves as a facade, delegating to specialized submodules:
  - `FlowCrud` - CRUD operations for flows
  - `NodeCrud` - CRUD operations for nodes
  - `ConnectionCrud` - CRUD operations for connections
  """

  alias Storyarn.Flows.{ConnectionCrud, Flow, FlowConnection, FlowCrud, FlowNode, NodeCrud}
  alias Storyarn.Projects.Project

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type flow :: Flow.t()
  @type flow_node :: FlowNode.t()
  @type connection :: FlowConnection.t()
  @type changeset :: Ecto.Changeset.t()
  @type attrs :: map()

  # =============================================================================
  # Flows - CRUD Operations
  # =============================================================================

  @doc """
  Lists all flows for a project.
  Returns flows ordered by is_main (descending) then name.
  """
  @spec list_flows(integer()) :: [flow()]
  defdelegate list_flows(project_id), to: FlowCrud

  @doc """
  Searches flows by name or shortcut for reference selection.
  Returns flows matching the query, limited to 10 results.
  """
  @spec search_flows(integer(), String.t()) :: [flow()]
  defdelegate search_flows(project_id, query), to: FlowCrud

  @doc """
  Gets a single flow by ID within a project.
  Returns `nil` if the flow doesn't exist or doesn't belong to the project.
  """
  @spec get_flow(integer(), integer()) :: flow() | nil
  defdelegate get_flow(project_id, flow_id), to: FlowCrud

  @doc """
  Gets a single flow by ID within a project.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_flow!(integer(), integer()) :: flow()
  defdelegate get_flow!(project_id, flow_id), to: FlowCrud

  @doc """
  Creates a new flow in a project.
  """
  @spec create_flow(Project.t(), attrs()) :: {:ok, flow()} | {:error, changeset()}
  defdelegate create_flow(project, attrs), to: FlowCrud

  @doc """
  Updates a flow.
  """
  @spec update_flow(flow(), attrs()) :: {:ok, flow()} | {:error, changeset()}
  defdelegate update_flow(flow, attrs), to: FlowCrud

  @doc """
  Deletes a flow and all its nodes and connections.
  """
  @spec delete_flow(flow()) :: {:ok, flow()} | {:error, changeset()}
  defdelegate delete_flow(flow), to: FlowCrud

  @doc """
  Returns a changeset for tracking flow changes.
  """
  @spec change_flow(flow(), attrs()) :: changeset()
  defdelegate change_flow(flow, attrs \\ %{}), to: FlowCrud

  @doc """
  Gets the main flow for a project.
  """
  @spec get_main_flow(integer()) :: flow() | nil
  defdelegate get_main_flow(project_id), to: FlowCrud

  @doc """
  Sets a flow as the main flow for its project.
  Unsets any existing main flow.
  """
  @spec set_main_flow(flow()) :: {:ok, flow()} | {:error, term()}
  defdelegate set_main_flow(flow), to: FlowCrud

  # =============================================================================
  # Nodes - CRUD Operations
  # =============================================================================

  @doc """
  Lists all nodes for a flow.
  """
  @spec list_nodes(integer()) :: [flow_node()]
  defdelegate list_nodes(flow_id), to: NodeCrud

  @doc """
  Gets a single node by ID within a flow.
  Returns `nil` if the node doesn't exist or doesn't belong to the flow.
  """
  @spec get_node(integer(), integer()) :: flow_node() | nil
  defdelegate get_node(flow_id, node_id), to: NodeCrud

  @doc """
  Gets a single node by ID within a flow.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_node!(integer(), integer()) :: flow_node()
  defdelegate get_node!(flow_id, node_id), to: NodeCrud

  @doc """
  Gets a node by ID without flow validation.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_node_by_id!(integer()) :: flow_node()
  defdelegate get_node_by_id!(node_id), to: NodeCrud

  @doc """
  Creates a new node in a flow.
  """
  @spec create_node(flow(), attrs()) :: {:ok, flow_node()} | {:error, changeset()}
  defdelegate create_node(flow, attrs), to: NodeCrud

  @doc """
  Updates a node.
  """
  @spec update_node(flow_node(), attrs()) :: {:ok, flow_node()} | {:error, changeset()}
  defdelegate update_node(node, attrs), to: NodeCrud

  @doc """
  Updates only the position of a node.
  """
  @spec update_node_position(flow_node(), attrs()) :: {:ok, flow_node()} | {:error, changeset()}
  defdelegate update_node_position(node, attrs), to: NodeCrud

  @doc """
  Updates only the data of a node.
  """
  @spec update_node_data(flow_node(), map()) :: {:ok, flow_node()} | {:error, changeset()}
  defdelegate update_node_data(node, data), to: NodeCrud

  @doc """
  Deletes a node and all its connections.
  """
  @spec delete_node(flow_node()) :: {:ok, flow_node()} | {:error, changeset()}
  defdelegate delete_node(node), to: NodeCrud

  @doc """
  Returns a changeset for tracking node changes.
  """
  @spec change_node(flow_node(), attrs()) :: changeset()
  defdelegate change_node(node, attrs \\ %{}), to: NodeCrud

  @doc """
  Counts nodes by type for a flow.
  """
  @spec count_nodes_by_type(integer()) :: map()
  defdelegate count_nodes_by_type(flow_id), to: NodeCrud

  # =============================================================================
  # Connections - CRUD Operations
  # =============================================================================

  @doc """
  Lists all connections for a flow.
  """
  @spec list_connections(integer()) :: [connection()]
  defdelegate list_connections(flow_id), to: ConnectionCrud

  @doc """
  Gets a single connection by ID within a flow.
  Returns `nil` if the connection doesn't exist or doesn't belong to the flow.
  """
  @spec get_connection(integer(), integer()) :: connection() | nil
  defdelegate get_connection(flow_id, connection_id), to: ConnectionCrud

  @doc """
  Gets a single connection by ID within a flow.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_connection!(integer(), integer()) :: connection()
  defdelegate get_connection!(flow_id, connection_id), to: ConnectionCrud

  @doc """
  Gets a connection by ID without flow validation.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_connection_by_id!(integer()) :: connection()
  defdelegate get_connection_by_id!(connection_id), to: ConnectionCrud

  @doc """
  Creates a new connection between two nodes.
  """
  @spec create_connection(flow(), flow_node(), flow_node(), attrs()) ::
          {:ok, connection()} | {:error, changeset()}
  defdelegate create_connection(flow, source_node, target_node, attrs), to: ConnectionCrud

  @doc """
  Creates a new connection with node IDs in attrs.
  """
  @spec create_connection_with_attrs(flow(), attrs()) ::
          {:ok, connection()} | {:error, changeset()}
  def create_connection_with_attrs(%Flow{} = flow, attrs) do
    ConnectionCrud.create_connection(flow, attrs)
  end

  @doc """
  Updates a connection.
  """
  @spec update_connection(connection(), attrs()) :: {:ok, connection()} | {:error, changeset()}
  defdelegate update_connection(connection, attrs), to: ConnectionCrud

  @doc """
  Deletes a connection.
  """
  @spec delete_connection(connection()) :: {:ok, connection()} | {:error, changeset()}
  defdelegate delete_connection(connection), to: ConnectionCrud

  @doc """
  Deletes connections between two nodes.
  """
  @spec delete_connection_by_nodes(integer(), integer(), integer()) :: {integer(), nil | term()}
  defdelegate delete_connection_by_nodes(flow_id, source_node_id, target_node_id),
    to: ConnectionCrud

  @doc """
  Returns a changeset for tracking connection changes.
  """
  @spec change_connection(connection(), attrs()) :: changeset()
  defdelegate change_connection(connection, attrs \\ %{}), to: ConnectionCrud

  @doc """
  Gets all outgoing connections from a node.
  """
  @spec get_outgoing_connections(integer()) :: [connection()]
  defdelegate get_outgoing_connections(node_id), to: ConnectionCrud

  @doc """
  Gets all incoming connections to a node.
  """
  @spec get_incoming_connections(integer()) :: [connection()]
  defdelegate get_incoming_connections(node_id), to: ConnectionCrud

  # =============================================================================
  # Serialization
  # =============================================================================

  @doc """
  Serializes a flow with its nodes and connections for the Rete.js canvas.
  Returns a map with `nodes` and `connections` arrays in the format expected
  by the JavaScript flow canvas hook.
  """
  @spec serialize_for_canvas(flow()) :: map()
  def serialize_for_canvas(%Flow{} = flow) do
    %{
      id: flow.id,
      name: flow.name,
      nodes:
        Enum.map(flow.nodes, fn node ->
          %{
            id: node.id,
            type: node.type,
            position: %{x: node.position_x, y: node.position_y},
            data: node.data
          }
        end),
      connections:
        Enum.map(flow.connections, fn conn ->
          %{
            id: conn.id,
            source_node_id: conn.source_node_id,
            source_pin: conn.source_pin,
            target_node_id: conn.target_node_id,
            target_pin: conn.target_pin,
            label: conn.label,
            condition: conn.condition
          }
        end)
    }
  end
end
