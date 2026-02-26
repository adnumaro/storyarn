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
    Condition,
    ConnectionCrud,
    DebugSessionStore,
    Flow,
    FlowConnection,
    FlowCrud,
    FlowNode,
    HubColors,
    Instruction,
    NavigationHistoryStore,
    NodeCrud,
    SceneResolver,
    TreeOperations,
    VariableReferenceTracker
  }

  alias Storyarn.Flows.Evaluator.{
    ConditionEval,
    Engine,
    Helpers,
    InstructionExec
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
  # Node Types
  # =============================================================================

  @doc """
  Returns the list of valid node types.
  """
  @spec node_types() :: [String.t()]
  defdelegate node_types(), to: FlowNode

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
  defdelegate list_flows_by_parent(project_id, parent_id), to: TreeOperations

  @doc "Returns the default search limit used by search_flows/3 and search_flows_deep/3."
  defdelegate default_search_limit(), to: FlowCrud

  @doc """
  Searches flows by name or shortcut for reference selection.
  Accepts opts: [limit: 25, offset: 0, exclude_id: nil].
  """
  @spec search_flows(integer(), String.t(), keyword()) :: [flow()]
  defdelegate search_flows(project_id, query, opts \\ []), to: FlowCrud

  @doc """
  Deep search: searches flow names/shortcuts and node content.
  Accepts opts: [limit: 25, offset: 0, exclude_id: nil].
  """
  @spec search_flows_deep(integer(), String.t(), keyword()) :: [flow()]
  defdelegate search_flows_deep(project_id, query, opts \\ []), to: FlowCrud

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
  Gets a single flow by ID within a project, including soft-deleted flows.
  Returns `nil` if not found.
  """
  @spec get_flow_including_deleted(integer(), integer()) :: flow() | nil
  defdelegate get_flow_including_deleted(project_id, flow_id), to: FlowCrud

  @doc """
  Gets a single flow by ID within a project.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_flow!(integer(), integer()) :: flow()
  defdelegate get_flow!(project_id, flow_id), to: FlowCrud

  @doc """
  Creates a child flow and assigns it to a node's referenced_flow_id.
  Used by exit (flow_reference mode) and subflow nodes.
  """
  @spec create_linked_flow(Project.t(), flow(), flow_node(), keyword()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  defdelegate create_linked_flow(project, parent_flow, node, opts \\ []), to: FlowCrud

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
  Updates only the scene_id of a flow.
  Used to associate a flow with a map as its scene backdrop.
  """
  @spec update_flow_scene(flow(), attrs()) :: {:ok, flow()} | {:error, Ecto.Changeset.t()}
  defdelegate update_flow_scene(flow, attrs), to: FlowCrud

  @doc """
  Resolves the scene_id for a flow using inheritance chain.

  Resolution order:
  1. `flow.scene_id` (explicit)
  2. `opts[:caller_scene_id]` (runtime inheritance from calling flow)
  3. Parent chain (walk up parent_id)
  4. `nil`
  """
  @spec resolve_scene_id(flow(), keyword()) :: integer() | nil
  defdelegate resolve_scene_id(flow, opts \\ []), to: SceneResolver

  @doc """
  Sets a flow as the main flow for its project.
  Unsets any existing main flow.
  """
  @spec set_main_flow(flow()) :: {:ok, flow()} | {:error, term()}
  defdelegate set_main_flow(flow), to: FlowCrud

  # =============================================================================
  # Flow Helpers
  # =============================================================================

  @doc """
  Checks if a flow has been soft-deleted (has a non-nil deleted_at).

  Delegates to `Storyarn.Flows.Flow.deleted?/1`.
  """
  defdelegate flow_deleted?(flow), to: Flow, as: :deleted?

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
  Gets a node by ID scoped to a flow, without preloads.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_node_by_id!(integer(), integer()) :: flow_node()
  defdelegate get_node_by_id!(flow_id, node_id), to: NodeCrud

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
  Batch-updates positions for multiple nodes in a single transaction.
  Used by auto-layout.
  """
  @spec batch_update_positions(integer(), [map()]) :: {:ok, integer()} | {:error, term()}
  defdelegate batch_update_positions(flow_id, positions), to: NodeCrud

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
  Restores a soft-deleted node by clearing its deleted_at timestamp.
  """
  @spec restore_node(integer(), integer()) ::
          {:ok, flow_node()} | {:ok, :already_active} | {:error, atom()}
  defdelegate restore_node(flow_id, node_id), to: NodeCrud

  @doc """
  Returns a changeset for tracking node changes.
  """
  @spec change_node(flow_node(), attrs()) :: changeset()
  defdelegate change_node(node, attrs \\ %{}), to: NodeCrud

  @doc """
  Lists all dialogue nodes where a given sheet is the speaker, across a project.
  Returns nodes with their flow preloaded.
  """
  @spec list_dialogue_nodes_by_speaker(integer(), integer()) :: [flow_node()]
  defdelegate list_dialogue_nodes_by_speaker(project_id, sheet_id), to: NodeCrud

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
  Lists all unique outcome tags used across exit nodes in a project.
  Used for autocomplete suggestions in exit node sidebar.
  """
  @spec list_outcome_tags_for_project(integer()) :: [String.t()]
  defdelegate list_outcome_tags_for_project(project_id), to: NodeCrud

  @doc """
  Finds all nodes (subflow and exit with flow_reference) that reference a given flow.
  Used by exit nodes to show "Referenced by" section.
  """
  @spec list_nodes_referencing_flow(integer(), integer()) :: [map()]
  defdelegate list_nodes_referencing_flow(flow_id, project_id), to: NodeCrud

  @doc """
  Checks if a subflow reference would create a circular dependency.
  """
  @spec has_circular_reference?(integer(), integer()) :: boolean()
  defdelegate has_circular_reference?(source_flow_id, target_flow_id), to: NodeCrud

  @doc """
  Safely parses a value to integer. Returns nil if parsing fails.
  """
  defdelegate safe_to_integer(value), to: NodeCrud

  # =============================================================================
  # Variable Reference Tracking
  # =============================================================================

  @doc """
  Returns all variable references for a block, with flow/node info.
  Used by the sheet editor's variable usage section.
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

  @doc """
  Updates variable references for a scene zone after its action_data changes.
  """
  @spec update_scene_zone_references(map(), keyword()) :: :ok
  defdelegate update_scene_zone_references(zone, opts \\ []), to: VariableReferenceTracker

  @doc """
  Deletes all variable references for a scene zone.
  """
  @spec delete_map_zone_references(integer()) :: :ok
  defdelegate delete_map_zone_references(zone_id), to: VariableReferenceTracker

  @doc """
  Updates variable references for a scene pin after its action_data changes.
  """
  @spec update_scene_pin_references(map(), keyword()) :: :ok
  defdelegate update_scene_pin_references(pin, opts \\ []), to: VariableReferenceTracker

  @doc """
  Deletes all variable references for a scene pin.
  """
  @spec delete_map_pin_references(integer()) :: :ok
  defdelegate delete_map_pin_references(pin_id), to: VariableReferenceTracker

  @doc """
  Deletes all variable references for a flow node.
  Called when a node is deleted.
  """
  @spec delete_references(integer()) :: :ok
  defdelegate delete_references(node_id), to: VariableReferenceTracker

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

  @doc """
  Deletes all connections within a flow where both source and target are in the given node IDs list.
  Used by FlowSync to clear internal connections before rebuilding them.
  """
  @spec delete_connections_among_nodes(integer(), [integer()]) :: {integer(), nil | term()}
  defdelegate delete_connections_among_nodes(flow_id, node_ids), to: ConnectionCrud

  # =============================================================================
  # Evaluator — Engine
  # =============================================================================

  @doc "Initialize an evaluator state for a flow."
  defdelegate evaluator_init(variables, start_node_id), to: Engine, as: :init

  @doc "Advance the evaluator by one step."
  defdelegate evaluator_step(state, nodes, connections), to: Engine, as: :step

  @doc "Step back to the previous node."
  defdelegate evaluator_step_back(state), to: Engine, as: :step_back

  @doc "Choose a response in a waiting_input state."
  defdelegate evaluator_choose_response(state, response_id, connections),
    to: Engine,
    as: :choose_response

  @doc "Push a sub-flow context onto the call stack."
  defdelegate evaluator_push_flow_context(state, node_id, nodes, connections, flow_name),
    to: Engine,
    as: :push_flow_context

  @doc "Pop a sub-flow context from the call stack."
  defdelegate evaluator_pop_flow_context(state), to: Engine, as: :pop_flow_context

  @doc "Reset the evaluator to its initial state."
  defdelegate evaluator_reset(state), to: Engine, as: :reset

  @doc "Toggle a breakpoint on a node."
  defdelegate evaluator_toggle_breakpoint(state, node_id), to: Engine, as: :toggle_breakpoint

  @doc "Check if the evaluator is at a breakpoint."
  defdelegate evaluator_at_breakpoint?(state), to: Engine, as: :at_breakpoint?

  @doc "Record a breakpoint hit."
  defdelegate evaluator_add_breakpoint_hit(state, node_id), to: Engine, as: :add_breakpoint_hit

  @doc "Set a variable value in the evaluator state."
  defdelegate evaluator_set_variable(state, key, value), to: Engine, as: :set_variable

  @doc "Extend the step limit for the evaluator."
  defdelegate evaluator_extend_step_limit(state), to: Engine, as: :extend_step_limit

  @doc "Add a console entry to the evaluator state."
  defdelegate evaluator_add_console_entry(state, level, node_id, label, message),
    to: Engine,
    as: :add_console_entry

  # =============================================================================
  # Evaluator — Helpers
  # =============================================================================

  @doc "Strip HTML tags and truncate to max_length characters."
  def evaluator_strip_html(text, max_length \\ 40), do: Helpers.strip_html(text, max_length)

  @doc "Format a debug value for display."
  defdelegate evaluator_format_value(value), to: Helpers, as: :format_value

  # =============================================================================
  # Evaluator — Condition & Instruction
  # =============================================================================

  @doc "Evaluate a condition expression against variables."
  defdelegate evaluate_condition(condition, variables), to: ConditionEval, as: :evaluate

  @doc "Execute instruction assignments against variables."
  defdelegate execute_instructions(assignments, variables), to: InstructionExec, as: :execute

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
    referencing_flows = NodeCrud.list_nodes_referencing_flow(flow.id, flow.project_id)

    cache = %{subflow: subflow_cache}

    %{
      id: flow.id,
      name: flow.name,
      nodes:
        Enum.map(flow.nodes, fn node ->
          data =
            node.type
            |> resolve_node_colors(node.data, cache)
            |> maybe_add_stale_flag(node.id, stale_node_ids)
            |> maybe_add_referencing_flows(node.type, referencing_flows)

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
  The cache is pre-fetched by batch_resolve_subflow_data/1.
  When called via the 2-arity version (single-node updates), cache is `%{}`.
  """
  @spec resolve_node_colors(String.t(), map(), map()) :: map()
  def resolve_node_colors("hub", data, _cache) do
    Map.put(
      data,
      "color_hex",
      HubColors.to_hex(data["color"], HubColors.default_hex())
    )
  end

  def resolve_node_colors("subflow", data, cache) do
    subflow_cache = Map.get(cache, :subflow, %{})
    NodeCrud.resolve_subflow_data(data, subflow_cache)
  end

  def resolve_node_colors("exit", data, _cache) do
    NodeCrud.resolve_exit_data(data)
  end

  def resolve_node_colors(_type, data, _cache), do: data

  defp maybe_add_referencing_flows(data, "entry", referencing_flows) do
    refs =
      Enum.map(referencing_flows, fn ref ->
        %{
          "flow_id" => ref.flow_id,
          "flow_name" => ref.flow_name,
          "flow_shortcut" => ref.flow_shortcut,
          "node_type" => to_string(ref.node_type)
        }
      end)

    Map.put(data, "referencing_flows", refs)
  end

  defp maybe_add_referencing_flows(data, _type, _referencing_flows), do: data

  defp maybe_add_stale_flag(data, node_id, stale_node_ids) do
    if MapSet.member?(stale_node_ids, node_id) do
      Map.put(data, "has_stale_refs", true)
    else
      data
    end
  end

  # =============================================================================
  # Condition
  # =============================================================================

  defdelegate condition_sanitize(condition), to: Condition, as: :sanitize
  defdelegate condition_new(), to: Condition, as: :new
  defdelegate condition_has_rules?(condition), to: Condition, as: :has_rules?
  defdelegate condition_to_json(condition), to: Condition, as: :to_json
  defdelegate condition_parse(condition), to: Condition, as: :parse

  # =============================================================================
  # Instruction
  # =============================================================================

  defdelegate instruction_sanitize(assignments), to: Instruction, as: :sanitize
  defdelegate instruction_format_short(assignment), to: Instruction, as: :format_assignment_short

  # =============================================================================
  # DebugSessionStore
  # =============================================================================

  defdelegate debug_session_store(key, data), to: DebugSessionStore, as: :store
  defdelegate debug_session_take(key), to: DebugSessionStore, as: :take

  # =============================================================================
  # NavigationHistoryStore
  # =============================================================================

  defdelegate nav_history_get(key), to: NavigationHistoryStore, as: :get
  defdelegate nav_history_put(key, data), to: NavigationHistoryStore, as: :put
  defdelegate nav_history_clear(key), to: NavigationHistoryStore, as: :clear

  # =============================================================================
  # Export / Import helpers
  # =============================================================================

  @doc "Returns the project_id for a flow by its ID."
  defdelegate get_flow_project_id(flow_id), to: FlowCrud

  @doc "Lists flows with nodes and connections preloaded. Opts: [filter_ids: :all | [ids]]."
  defdelegate list_flows_for_export(project_id, opts \\ []), to: FlowCrud

  @doc "Counts non-deleted flows for a project."
  defdelegate count_flows(project_id), to: FlowCrud

  @doc "Counts non-deleted flow nodes across all flows in a project."
  defdelegate count_nodes_for_project(project_id), to: FlowCrud

  @doc "Lists all non-deleted nodes for the given flow IDs."
  defdelegate list_nodes_for_flow_ids(flow_ids), to: FlowCrud

  @doc "Lists active scene IDs in a project (for validator cross-reference checks)."
  defdelegate list_valid_scene_ids_in_project(project_id), to: FlowCrud

  @doc "Lists flow nodes using a specific asset (audio_asset_id in data)."
  defdelegate list_nodes_using_asset(project_id, asset_id), to: FlowCrud

  @doc "Resolves flow node backlinks for entity reference tracking."
  defdelegate query_flow_node_backlinks(target_type, target_id, project_id), to: FlowCrud

  @doc "Lists sheet IDs referenced as speakers by flow nodes in a project."
  defdelegate list_speaker_sheet_ids(project_id), to: FlowCrud

  @doc "Lists sheet IDs referenced through variable_references in a project."
  defdelegate list_variable_referenced_sheet_ids(project_id), to: FlowCrud

  @doc "Lists existing flow shortcuts for a project."
  defdelegate list_flow_shortcuts(project_id), to: FlowCrud, as: :list_shortcuts

  @doc "Detects shortcut conflicts between imported flows and existing ones."
  defdelegate detect_flow_shortcut_conflicts(project_id, shortcuts),
    to: FlowCrud,
    as: :detect_shortcut_conflicts

  @doc "Soft-deletes existing flows with the given shortcut (overwrite import strategy)."
  defdelegate soft_delete_flow_by_shortcut(project_id, shortcut),
    to: FlowCrud,
    as: :soft_delete_by_shortcut

  @doc "Bulk-inserts flow connections from a list of attr maps."
  defdelegate bulk_import_connections(attrs_list), to: FlowCrud

  @doc "Creates a flow for import (raw insert, no side effects)."
  defdelegate import_flow(project_id, attrs), to: FlowCrud

  @doc "Creates a flow node for import (raw insert, no side effects)."
  defdelegate import_node(flow_id, attrs), to: FlowCrud

  @doc "Updates a flow's parent_id after import."
  defdelegate link_flow_import_parent(flow, parent_id), to: FlowCrud, as: :link_import_parent
end
