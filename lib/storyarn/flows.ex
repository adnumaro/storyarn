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

  alias Storyarn.Flows.{
    ConnectionCrud,
    Flow,
    FlowConnection,
    FlowCrud,
    FlowNode,
    HubColors,
    NodeCrud,
    TreeOperations,
    VariableReferenceTracker
  }

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
  Lists all non-deleted flows for a project.
  Returns flows ordered by is_main (descending) then name.
  """
  @spec list_flows(integer()) :: [flow()]
  defdelegate list_flows(project_id), to: FlowCrud

  @doc """
  Lists leaf flows (flows that are not parents of other flows).
  Useful for subflow reference selection where folder flows are excluded.
  """
  @spec list_leaf_flows(integer()) :: [flow()]
  defdelegate list_leaf_flows(project_id), to: FlowCrud

  @doc """
  Lists flows as a tree structure.
  Returns root-level flows with their children preloaded recursively.
  """
  @spec list_flows_tree(integer()) :: [flow()]
  defdelegate list_flows_tree(project_id), to: FlowCrud

  @doc """
  Lists flows by parent (for tree navigation).
  Use parent_id = nil for root level flows.
  """
  @spec list_flows_by_parent(integer(), integer() | nil) :: [flow()]
  defdelegate list_flows_by_parent(project_id, parent_id), to: FlowCrud

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
  Gets a single flow by ID within a project (no preloads).
  Used for breadcrumbs and lightweight lookups.
  """
  @spec get_flow_brief(integer(), integer()) :: flow() | nil
  defdelegate get_flow_brief(project_id, flow_id), to: FlowCrud

  @doc """
  Gets a single flow by ID within a project.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_flow!(integer(), integer()) :: flow()
  defdelegate get_flow!(project_id, flow_id), to: FlowCrud

  @doc """
  Creates a new flow in a project.
  Any flow can have children AND content (nodes). Use parent_id to create nested flows.
  """
  @spec create_flow(Project.t(), attrs()) :: {:ok, flow()} | {:error, changeset()}
  defdelegate create_flow(project, attrs), to: FlowCrud

  @doc """
  Updates a flow.
  """
  @spec update_flow(flow(), attrs()) :: {:ok, flow()} | {:error, changeset()}
  defdelegate update_flow(flow, attrs), to: FlowCrud

  @doc """
  Soft-deletes a flow by setting deleted_at.
  Also soft-deletes all children if it's a folder.
  """
  @spec delete_flow(flow()) :: {:ok, flow()} | {:error, term()}
  defdelegate delete_flow(flow), to: FlowCrud

  @doc """
  Permanently deletes a flow from the database.
  Use with caution - this cannot be undone.
  """
  @spec hard_delete_flow(flow()) :: {:ok, flow()} | {:error, changeset()}
  defdelegate hard_delete_flow(flow), to: FlowCrud

  @doc """
  Restores a soft-deleted flow.
  """
  @spec restore_flow(flow()) :: {:ok, flow()} | {:error, changeset()}
  defdelegate restore_flow(flow), to: FlowCrud

  @doc """
  Lists all soft-deleted flows for a project (trash).
  """
  @spec list_deleted_flows(integer()) :: [flow()]
  defdelegate list_deleted_flows(project_id), to: FlowCrud

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
  # Tree Operations
  # =============================================================================

  @doc """
  Reorders flows within a parent container.
  Takes a project_id, parent_id (nil for root level), and a list of flow IDs
  in the desired order.
  """
  @spec reorder_flows(integer(), integer() | nil, [integer()]) ::
          {:ok, [flow()]} | {:error, term()}
  defdelegate reorder_flows(project_id, parent_id, flow_ids), to: TreeOperations

  @doc """
  Moves a flow to a new parent at a specific position.
  """
  @spec move_flow_to_position(flow(), integer() | nil, integer()) ::
          {:ok, flow()} | {:error, term()}
  defdelegate move_flow_to_position(flow, new_parent_id, new_position), to: TreeOperations

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
  @spec update_node_data(flow_node(), map()) ::
          {:ok, flow_node(), map()} | {:error, atom() | changeset()}
  defdelegate update_node_data(node, data), to: NodeCrud

  @doc """
  Deletes a node and all its connections.
  """
  @spec delete_node(flow_node()) :: {:ok, flow_node(), map()} | {:error, atom() | changeset()}
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

  @doc """
  Lists all hub nodes in a flow with their hub_ids.
  Useful for populating Jump node target dropdown.
  """
  @spec list_hubs(integer()) :: [map()]
  defdelegate list_hubs(flow_id), to: NodeCrud

  @doc """
  Finds a hub node in a flow by its hub_id string.
  Returns nil if not found.
  """
  @spec get_hub_by_hub_id(integer(), String.t()) :: flow_node() | nil
  defdelegate get_hub_by_hub_id(flow_id, hub_id), to: NodeCrud

  @doc """
  Lists jump nodes that reference a given hub_id within a flow.
  """
  @spec list_referencing_jumps(integer(), String.t()) :: [map()]
  defdelegate list_referencing_jumps(flow_id, hub_id), to: NodeCrud

  @doc """
  Lists all Exit nodes for a given flow.
  Used by subflow nodes to generate dynamic output pins.
  """
  @spec list_exit_nodes_for_flow(integer()) :: [map()]
  defdelegate list_exit_nodes_for_flow(flow_id), to: NodeCrud

  @doc """
  Finds all subflow nodes that reference a given flow within the same project.
  Used for stale detection when a flow is deleted or exits change.
  """
  @spec list_subflow_nodes_referencing(integer(), integer()) :: [map()]
  defdelegate list_subflow_nodes_referencing(flow_id, project_id), to: NodeCrud

  @doc """
  Checks if a subflow reference would create a circular dependency.
  """
  @spec has_circular_reference?(integer(), integer()) :: boolean()
  defdelegate has_circular_reference?(source_flow_id, target_flow_id), to: NodeCrud

  # =============================================================================
  # Variable Reference Tracking
  # =============================================================================

  @doc """
  Returns all variable references for a block, with flow/node info.
  Used by the page editor's variable usage section.
  """
  @spec get_variable_usage(integer(), integer()) :: [map()]
  defdelegate get_variable_usage(block_id, project_id), to: VariableReferenceTracker

  @doc """
  Counts variable references for a block, grouped by kind.
  Returns %{"read" => N, "write" => M}.
  """
  @spec count_variable_usage(integer()) :: map()
  defdelegate count_variable_usage(block_id), to: VariableReferenceTracker

  @doc """
  Returns variable usage for a block with stale detection.
  Each ref map gets an additional `:stale` boolean.
  """
  @spec check_stale_references(integer(), integer()) :: [map()]
  defdelegate check_stale_references(block_id, project_id), to: VariableReferenceTracker

  @doc """
  Repairs all stale variable references across a project.
  Returns `{:ok, count}` of repaired nodes.
  """
  @spec repair_stale_references(integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  defdelegate repair_stale_references(project_id), to: VariableReferenceTracker

  @doc """
  Returns a MapSet of node IDs in a flow that have at least one stale reference.
  """
  @spec list_stale_node_ids(integer()) :: MapSet.t()
  defdelegate list_stale_node_ids(flow_id), to: VariableReferenceTracker

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
  Deletes a specific connection by node IDs and pin names.
  More precise than `delete_connection_by_nodes/3` for cases where
  multiple connections exist between the same node pair (e.g., dialogue responses).
  """
  @spec delete_connection_by_pins(integer(), integer(), String.t(), integer(), String.t()) ::
          {integer(), nil | term()}
  defdelegate delete_connection_by_pins(
                flow_id,
                source_node_id,
                source_pin,
                target_node_id,
                target_pin
              ),
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
    stale_node_ids = VariableReferenceTracker.list_stale_node_ids(flow.id)
    subflow_cache = NodeCrud.batch_resolve_subflow_data(flow.nodes)

    %{
      id: flow.id,
      name: flow.name,
      nodes:
        Enum.map(flow.nodes, fn node ->
          data =
            node.type
            |> resolve_node_colors(node.data, subflow_cache)
            |> maybe_add_stale_flag(node.id, stale_node_ids)

          %{
            id: node.id,
            type: node.type,
            position: %{x: node.position_x, y: node.position_y},
            data: data
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
            label: conn.label
          }
        end)
    }
  end

  @doc """
  Enriches node data with resolved values for the canvas (single node).
  Used by individual node update events. For bulk serialization, use the 3-arity version.
  """
  @spec resolve_node_colors(String.t(), map()) :: map()
  def resolve_node_colors(type, data), do: resolve_node_colors(type, data, %{})

  @doc """
  Enriches node data with resolved values for the canvas.
  Resolves hub color names to hex values and subflow references.
  The subflow_cache is pre-fetched by batch_resolve_subflow_data/1.
  """
  @spec resolve_node_colors(String.t(), map(), map()) :: map()
  def resolve_node_colors("hub", data, _subflow_cache) do
    Map.put(
      data,
      "color_hex",
      HubColors.to_hex(data["color"] || "purple", HubColors.default_hex())
    )
  end

  def resolve_node_colors("subflow", data, subflow_cache) do
    NodeCrud.resolve_subflow_data(data, subflow_cache)
  end

  def resolve_node_colors(_type, data, _subflow_cache), do: data

  defp maybe_add_stale_flag(data, node_id, stale_node_ids) do
    if MapSet.member?(stale_node_ids, node_id) do
      Map.put(data, "has_stale_refs", true)
    else
      data
    end
  end
end
