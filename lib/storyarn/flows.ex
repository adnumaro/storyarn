defmodule Storyarn.Flows do
  @moduledoc """
  Public facade of the Flows bounded context.

  The facade preserves the established client contract while composing eight
  capability boundaries. Commands, queries, projections, rules, execution
  modules, events, and adapters remain private to their owner.
  """

  alias Storyarn.Flows.AI
  alias Storyarn.Flows.Editor
  alias Storyarn.Flows.EditorCatalog
  alias Storyarn.Flows.Expressions
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.Health
  alias Storyarn.Flows.Localization
  alias Storyarn.Flows.References
  alias Storyarn.Flows.Runtime
  alias Storyarn.Flows.StructuralAnalysis.Analysis
  alias Storyarn.Flows.VariableSearch
  alias Storyarn.Flows.Versioning

  @doc false
  defdelegate child_spec(opts), to: Runtime

  @doc false
  defdelegate start_link(opts), to: Runtime

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type flow :: Storyarn.Flows.Flow.t()
  @type flow_node :: FlowNode.t()
  @type connection :: Storyarn.Flows.FlowConnection.t()
  @type sequence :: FlowNode.t()
  @type changeset :: Ecto.Changeset.t()
  @type attrs :: map()
  @type project_identity :: pos_integer() | %{required(:id) => pos_integer()}
  @type linked_flow_result ::
          {:ok, map()}
          | {:error, :limit_reached, term()}
          | {:error, atom(), term(), map()}

  # =============================================================================
  # Node Types
  # =============================================================================

  @doc """
  Returns the list of valid node types.
  """
  @spec node_types() :: [String.t()]
  defdelegate node_types(), to: Editor
  defdelegate node_label(node), to: Editor
  defdelegate node_specific_label(node), to: Editor

  @doc "Returns the node types represented by the Flow editor catalog."
  defdelegate editor_node_types(), to: Editor

  @doc "Returns the editor node types users may create directly."
  defdelegate user_addable_node_types(), to: Editor

  @doc "Returns the authored default data for an editor node type."
  defdelegate default_node_data(type), to: Editor

  @doc "Normalizes authored node data for the editor form contract."
  defdelegate node_form_data(type, data), to: Editor

  @doc "Applies the Flow-owned identity rules for duplicated node data."
  defdelegate duplicate_node_data(type, data), to: Editor

  @doc "Sanitizes and stores a condition in node data."
  defdelegate put_node_condition(data, condition), to: Editor

  @doc "Sanitizes and stores a dialogue response condition."
  defdelegate put_response_condition(data, response_id, condition), to: Editor

  @doc "Toggles condition switch mode and applies its output-label contract."
  defdelegate toggle_condition_switch_mode(data), to: Editor

  @doc "Returns the sequence number for the next dialogue response."
  defdelegate next_dialogue_response_number(data), to: Editor

  @doc "Appends a response using Flow-owned response identity and shape."
  defdelegate append_dialogue_response(data, default_text), to: Editor

  defdelegate remove_dialogue_response(data, response_id), to: Editor
  defdelegate put_dialogue_response_text(data, response_id, text), to: Editor
  defdelegate put_dialogue_response_condition(data, response_id, condition), to: Editor
  defdelegate put_dialogue_response_instruction(data, response_id, instruction), to: Editor
  defdelegate put_dialogue_response_assignments(data, response_id, assignments), to: Editor
  defdelegate dialogue_technical_id(flow, node, speaker_name), to: Editor

  defdelegate put_exit_mode(data, mode), to: Editor
  defdelegate exit_mode(mode), to: Editor
  defdelegate validate_exit_flow_reference(project_id, current_flow_id, value), to: Editor
  defdelegate put_exit_flow_reference(data, flow_id), to: Editor
  defdelegate add_exit_outcome_tag(data, tag), to: Editor
  defdelegate remove_exit_outcome_tag(data, tag), to: Editor
  defdelegate put_exit_color(data, color), to: Editor
  defdelegate put_exit_target(data, type, id), to: Editor
  defdelegate exit_technical_id(flow, node), to: Editor

  defdelegate validate_subflow_reference(value, current_flow_id), to: Editor
  defdelegate put_subflow_reference(data, flow_id), to: Editor
  defdelegate put_instruction_assignments(data, assignments), to: Editor
  defdelegate put_annotation_color(data, color), to: Editor
  defdelegate put_annotation_font_size(data, size), to: Editor
  defdelegate put_hub_color(data, color), to: Editor

  @doc "Creates an editor node and emits its Flow-owned creation fact on success."
  defdelegate create_editor_node(scope, flow, attrs, creation_method), to: Editor

  @doc "Duplicates an editor node using Flow-owned data and placement rules."
  defdelegate duplicate_editor_node(scope, flow, node), to: Editor

  @doc "Creates an editor sequence and emits its Flow-owned creation fact."
  defdelegate create_editor_sequence(scope, flow, attrs, creation_method), to: Editor

  @doc "Wraps editor nodes and emits the resulting Flow-owned creation fact."
  defdelegate wrap_editor_selection(scope, flow, node_ids, attrs), to: Editor

  defdelegate create_editor_sequence_visual_layer(scope, flow, sequence_id, attrs), to: Editor

  defdelegate update_editor_sequence_visual_layer(scope, flow, sequence_id, layer, attrs), to: Editor

  defdelegate upsert_editor_sequence_track(scope, flow, sequence_id, kind, attrs), to: Editor

  defdelegate create_named_version(scope, flow, opts), to: Versioning

  defdelegate restore_tracked_version(scope, flow, version, opts), to: Versioning

  defdelegate record_version_panel_opened(scope, flow), to: Versioning
  defdelegate record_version_compared(scope, flow), to: Versioning

  @doc "Returns the node types that contribute player-facing runtime text."
  defdelegate localizable_node_types(), to: Localization

  @doc "Recomputes formula values according to the Flow runtime contract."
  defdelegate recompute_formula_variables(variables), to: Expressions

  @doc "Translates a same-row binding into the variable key consumed by Flows."
  defdelegate translate_same_row_binding(formula_ref, bindings), to: Expressions

  @doc "Computes the player-facing word count for one Flow node."
  defdelegate node_word_count(type, data), to: Localization

  @doc "Returns the Flow-owned sort rank for one health severity."
  defdelegate health_severity_rank(severity), to: Health

  @doc "Creates a stable runtime identity for a dialogue node."
  defdelegate new_dialogue_id(), to: Editor

  @doc "Creates a stable runtime identity for a dialogue response."
  defdelegate new_response_id(), to: Editor

  # =============================================================================
  # Flows - CRUD Operations
  # =============================================================================

  @doc """
  Lists all non-deleted flows for a project.
  Returns flows ordered by is_main (descending) then name.
  """
  @spec list_flows(integer()) :: [flow()]
  defdelegate list_flows(project_id), to: Editor

  @doc """
  Lists flows as a tree structure.
  Returns root-level flows with their children preloaded recursively.
  """
  @spec list_flows_tree(integer()) :: [flow()]
  defdelegate list_flows_tree(project_id), to: Editor

  @doc """
  Lists flows by parent (for tree navigation).
  Use parent_id = nil for root level flows.
  """
  @spec list_flows_by_parent(integer(), integer() | nil) :: [flow()]
  defdelegate list_flows_by_parent(project_id, parent_id), to: Editor

  @doc "Returns the default search limit used by search_flows/3 and search_flows_deep/3."
  defdelegate default_search_limit(), to: Editor

  @doc """
  Searches flows by name or shortcut for reference selection.
  Accepts opts: [limit: 25, offset: 0, exclude_id: nil].
  """
  @spec search_flows(integer(), String.t(), keyword()) :: [flow()]
  defdelegate search_flows(project_id, query, opts \\ []), to: Editor

  @doc "Cross-project flow search over a pre-authorized project set (see `Storyarn.Platform.GlobalSearch`)."
  @spec search_flows_in_projects([integer()], String.t(), keyword()) :: [flow()]
  defdelegate search_flows_in_projects(project_ids, query, opts \\ []), to: Editor

  @doc """
  Deep search: searches flow names/shortcuts and node content.
  Accepts opts: [limit: 25, offset: 0, exclude_id: nil].
  """
  @spec search_flows_deep(integer(), String.t(), keyword()) :: [flow()]
  defdelegate search_flows_deep(project_id, query, opts \\ []), to: Editor

  @doc """
  Gets a single flow by ID within a project.
  Returns `nil` if the flow doesn't exist or doesn't belong to the project.
  """
  @spec get_flow(integer(), integer()) :: flow() | nil
  defdelegate get_flow(project_id, flow_id), to: Editor

  @doc """
  Gets a single flow by ID within a project (no preloads).
  Used for breadcrumbs and lightweight lookups.
  """
  @spec get_flow_brief(integer(), integer()) :: flow() | nil
  defdelegate get_flow_brief(project_id, flow_id), to: Editor

  @doc false
  defdelegate list_context_flows(project_id, flow_ids, limit), to: AI

  @doc """
  Gets a single flow by ID within a project, including soft-deleted flows.
  Returns `nil` if not found.
  """
  @spec get_flow_including_deleted(integer(), integer()) :: flow() | nil
  defdelegate get_flow_including_deleted(project_id, flow_id), to: Editor

  @doc """
  Gets a single flow by ID within a project.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_flow!(integer(), integer(), keyword()) :: flow()
  defdelegate get_flow!(project_id, flow_id, opts \\ []), to: Editor

  @doc """
  Creates a child flow and assigns it to a node's referenced_flow_id.
  Used by exit (flow_reference mode) and subflow nodes.
  """
  @spec create_linked_flow(project_identity(), flow(), flow_node()) :: linked_flow_result()
  defdelegate create_linked_flow(project, parent_flow, node), to: Editor

  @spec create_linked_flow(project_identity(), flow(), flow_node(), keyword()) :: linked_flow_result()
  @spec create_linked_flow(map(), project_identity(), flow(), flow_node()) :: linked_flow_result()
  defdelegate create_linked_flow(project, parent_flow, node, opts), to: Editor

  @spec create_linked_flow(map(), project_identity(), flow(), flow_node(), keyword()) :: linked_flow_result()
  defdelegate create_linked_flow(actor_scope, project, parent_flow, node, opts), to: Editor

  @doc """
  Creates a new flow in a project.
  Any flow can have children AND content (nodes). Use parent_id to create nested flows.
  """
  @spec create_flow(project_identity(), attrs()) :: {:ok, flow()} | {:error, changeset()}
  defdelegate create_flow(project, attrs), to: Editor
  defdelegate create_flow(actor_scope, project, attrs), to: Editor

  @doc false
  defdelegate create_flow_in_transaction(project, attrs), to: Editor
  defdelegate create_flow_in_transaction(actor_scope, project, attrs), to: Editor

  @doc """
  Updates a flow.
  """
  @spec update_flow(flow(), attrs()) :: {:ok, flow()} | {:error, changeset()}
  defdelegate update_flow(flow, attrs), to: Editor

  @doc """
  Soft-deletes a flow by setting deleted_at.
  Also soft-deletes all children if it's a folder.
  """
  @spec delete_flow(flow()) :: {:ok, flow()} | {:error, term()}
  defdelegate delete_flow(flow), to: Editor
  defdelegate delete_flow(actor_scope, flow), to: Editor

  @doc """
  Soft deletes a flow and its descendants, returning the committed cascade
  ids (collected under the delete's own lock).
  """
  @spec delete_flow_subtree(flow()) ::
          {:ok, %{entity: flow(), deleted_ids: [integer()], affected_flow_ids: [integer()]}} | {:error, term()}
  defdelegate delete_flow_subtree(flow), to: Editor
  defdelegate delete_flow_subtree(actor_scope, flow), to: Editor

  @doc false
  defdelegate delete_flow_subtree_in_transaction(flow), to: Editor
  defdelegate delete_flow_subtree_in_transaction(actor_scope, flow), to: Editor

  defdelegate delete_flow_subtree_by_id_in_transaction(actor_scope, project_id, flow_id),
    to: Editor

  @doc false
  defdelegate broadcast_flow_refreshes(affected_flow_ids), to: Editor

  @doc """
  Permanently deletes a flow from the database.
  Use with caution - this cannot be undone.
  """
  @spec hard_delete_flow(flow()) :: {:ok, flow()} | {:error, changeset()}
  defdelegate hard_delete_flow(flow), to: Editor

  @doc """
  Restores a soft-deleted flow.
  """
  @spec restore_flow(flow()) :: {:ok, flow()} | {:error, term()}
  defdelegate restore_flow(flow), to: Editor

  @doc """
  Lists all soft-deleted flows for a project (trash).
  """
  @spec list_deleted_flows(integer()) :: [flow()]
  defdelegate list_deleted_flows(project_id), to: Editor

  @doc """
  Returns a changeset for tracking flow changes.
  """
  @spec change_flow(flow(), attrs()) :: changeset()
  defdelegate change_flow(flow, attrs \\ %{}), to: Editor

  @doc """
  Updates only the scene_id of a flow.
  Used to associate a flow with a map as its scene backdrop.
  """
  @spec update_flow_scene(flow(), attrs()) :: {:ok, flow()} | {:error, Ecto.Changeset.t()}
  defdelegate update_flow_scene(flow, attrs), to: Editor

  @doc """
  Resolves the scene_id for a flow using inheritance chain.

  Resolution order:
  1. `flow.scene_id` (explicit)
  2. `opts[:caller_scene_id]` (runtime inheritance from calling flow)
  3. Parent chain (walk up parent_id)
  4. `nil`
  """
  @spec resolve_scene_id(flow(), keyword()) :: integer() | nil
  defdelegate resolve_scene_id(flow, opts \\ []), to: Runtime

  @doc """
  Searches active scene options for Exit node targets.

  The returned maps contain only `:id` and `:name` and are owned by Flows;
  callers never receive a foreign persistence record.
  """
  @spec search_exit_target_scenes(integer(), String.t(), keyword()) ::
          [Storyarn.Flows.ExitTargetScenes.scene_option()]
  defdelegate search_exit_target_scenes(project_id, query, opts \\ []), to: Editor

  @doc """
  Loads the Sheet and Scene presentation catalog needed by the Flow editor.

  The returned data is owned by Flows and does not expose schemas from other
  bounded contexts.
  """
  @spec load_editor_catalog(integer()) :: EditorCatalog.t()
  defdelegate load_editor_catalog(project_id), to: Editor

  @doc "Searches Flow-owned mention candidates from the shared persistence tables."
  @spec search_mentions(integer(), String.t()) :: [EditorCatalog.mention()]
  defdelegate search_mentions(project_id, query), to: Editor

  @doc "Returns a bounded page of Flow-owned speaker options."
  @spec search_speaker_options(integer(), String.t(), keyword()) ::
          {[EditorCatalog.speaker_option()], boolean()}
  defdelegate search_speaker_options(project_id, query, opts \\ []), to: Editor

  @doc "Builds the initial Flow speaker picker options, retaining selected rows."
  @spec initial_speaker_options(integer(), [term()]) :: [EditorCatalog.speaker_option()]
  defdelegate initial_speaker_options(project_id, selected_ids), to: Editor

  @doc "Returns a bounded page of Flow-owned asset picker options."
  @spec search_asset_options(integer(), String.t(), keyword()) ::
          {[EditorCatalog.asset_option()], boolean()}
  defdelegate search_asset_options(project_id, kind, opts \\ []), to: Editor

  @doc "Builds initial Flow asset picker options, retaining selected rows."
  @spec initial_asset_options(integer(), String.t(), [term()]) :: [EditorCatalog.asset_option()]
  defdelegate initial_asset_options(project_id, kind, selected_ids), to: Editor

  @doc """
  Loads the speaker presentation data required by the Flow player.

  Speakers are Flows-owned DTOs and do not expose foreign persistence records.
  """
  @spec load_player_speakers(integer()) :: [Storyarn.Flows.PlayerCatalog.speaker()]
  defdelegate load_player_speakers(project_id), to: Runtime

  @doc """
  Resolves the current speaker name for the editor preview.

  The lookup is project-scoped and excludes soft-deleted source records.
  """
  @spec get_preview_speaker_name(integer(), integer()) :: String.t() | nil
  defdelegate get_preview_speaker_name(project_id, speaker_id), to: Editor

  @doc """
  Sets a flow as the main flow for its project.
  Unsets any existing main flow.
  """
  @spec set_main_flow(flow()) :: {:ok, flow()} | {:error, term()}
  defdelegate set_main_flow(flow), to: Editor

  # =============================================================================
  # Flow Helpers
  # =============================================================================

  @doc """
  Checks if a flow has been soft-deleted (has a non-nil deleted_at).

  Delegates to `Storyarn.Flows.Flow.deleted?/1`.
  """
  defdelegate flow_deleted?(flow), to: Editor

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
  defdelegate reorder_flows(project_id, parent_id, flow_ids), to: Editor

  @doc """
  Moves a flow to a new parent at a specific position.
  """
  @spec move_flow_to_position(flow(), integer() | nil, integer()) ::
          {:ok, flow()} | {:error, term()}
  defdelegate move_flow_to_position(flow, new_parent_id, new_position), to: Editor

  # =============================================================================
  # Nodes - CRUD Operations
  # =============================================================================

  @doc """
  Lists all nodes for a flow.
  """
  @spec list_nodes(integer()) :: [flow_node()]
  defdelegate list_nodes(flow_id), to: Editor

  @doc "Lists active nodes with every sequence runtime association preloaded."
  @spec list_runtime_nodes(integer()) :: [flow_node()]
  defdelegate list_runtime_nodes(flow_id), to: Editor

  @doc false
  @spec lock_flow_nodes_for_update(flow()) ::
          {:ok, {flow(), [flow_node()]}} | {:error, term()}
  defdelegate lock_flow_nodes_for_update(flow), to: Editor

  @doc """
  Gets a single node by ID within a flow.
  Returns `nil` if the node doesn't exist or doesn't belong to the flow.
  """
  @spec get_node(integer(), integer()) :: flow_node() | nil
  defdelegate get_node(flow_id, node_id), to: Editor

  @doc false
  defdelegate get_context_node(project_id, node_id), to: AI

  @doc false
  defdelegate get_context_neighborhood(project_id, node_id, max_depth, max_fan_out, max_entities), to: AI

  @doc """
  Gets a single node by ID within a flow.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_node!(integer(), integer()) :: flow_node()
  defdelegate get_node!(flow_id, node_id), to: Editor

  @doc """
  Gets a node by ID scoped to a flow, without preloads.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_node_by_id!(integer(), integer()) :: flow_node()
  defdelegate get_node_by_id!(flow_id, node_id), to: Editor

  @doc """
  Creates a new node in a flow.
  """
  @spec create_node(flow(), attrs()) :: {:ok, flow_node()} | {:error, changeset()}
  defdelegate create_node(flow, attrs), to: Editor

  @doc false
  defdelegate create_node_without_dashboard_broadcast(flow, attrs), to: Editor

  @doc """
  Updates a node.
  """
  @spec update_node(flow_node(), attrs()) :: {:ok, flow_node()} | {:error, term()}
  defdelegate update_node(node, attrs), to: Editor

  @doc false
  @spec update_node_without_dashboard_broadcast(flow_node(), attrs()) ::
          {:ok, flow_node()} | {:error, term()}
  defdelegate update_node_without_dashboard_broadcast(node, attrs), to: Editor

  @doc """
  Updates only the position of a node.
  """
  @spec update_node_position(flow_node(), attrs()) :: {:ok, flow_node()} | {:error, changeset()}
  defdelegate update_node_position(node, attrs), to: Editor

  @doc """
  Reparents a node. Accepts an integer id of an existing sequence-typed
  flow_node as `parent_id`, or `nil` for root-level.
  """
  @spec update_node_parent(flow_node(), integer() | nil) ::
          {:ok, flow_node()} | {:error, changeset()}
  defdelegate update_node_parent(node, parent_id), to: Editor

  @doc """
  Batch-updates positions for multiple nodes in a single transaction.
  Used by auto-layout.
  """
  @spec batch_update_positions(integer(), [map()]) :: {:ok, integer()} | {:error, term()}
  defdelegate batch_update_positions(flow_id, positions), to: Editor

  @doc """
  Updates only the data of a node.
  """
  @spec update_node_data(flow_node(), map()) ::
          {:ok, flow_node(), map()} | {:error, atom() | changeset()}
  defdelegate update_node_data(node, data), to: Editor

  @doc false
  defdelegate update_node_data_without_dashboard_broadcast(node, data), to: Editor

  @doc "Applies a typed editor operation after locking the latest node state."
  defdelegate edit_node(flow_id, node_id, operation, payload), to: Editor

  @doc false
  @spec node_data_and_derivatives_current?(flow_node(), map(), integer()) :: boolean()
  defdelegate node_data_and_derivatives_current?(node, data, project_id), to: Editor

  @doc false
  @spec node_data_and_derivatives_current_ids([{flow_node(), map()}], integer()) ::
          MapSet.t(integer())
  defdelegate node_data_and_derivatives_current_ids(node_data_pairs, project_id), to: Editor

  @doc """
  Deletes a node and all its connections.
  """
  @spec delete_node(flow_node()) :: {:ok, flow_node(), map()} | {:error, atom() | changeset()}
  defdelegate delete_node(node), to: Editor

  @doc false
  defdelegate delete_node_without_dashboard_broadcast(node), to: Editor

  @doc false
  defdelegate delete_node_in_transaction_without_dashboard_broadcast(node), to: Editor

  @doc """
  Restores a soft-deleted node by clearing its deleted_at timestamp.
  """
  @spec restore_node(integer(), integer()) ::
          {:ok, flow_node()} | {:ok, :already_active} | {:error, atom()}
  defdelegate restore_node(flow_id, node_id), to: Editor

  @doc "Restores a node and returns the active graph fragment needed by the editor adapter."
  defdelegate restore_editor_node(flow, node_id), to: Editor

  @doc """
  Returns a changeset for tracking node changes.
  """
  @spec change_node(flow_node(), attrs()) :: changeset()
  defdelegate change_node(node, attrs \\ %{}), to: Editor

  @doc """
  Lists all dialogue nodes where a given sheet is the speaker, across a project.
  Returns nodes with their flow preloaded.
  """
  @spec list_dialogue_nodes_by_speaker(integer(), integer()) :: [flow_node()]
  defdelegate list_dialogue_nodes_by_speaker(project_id, sheet_id), to: Editor

  @doc """
  Counts nodes by type for a flow.
  """
  @spec count_nodes_by_type(integer()) :: map()
  defdelegate count_nodes_by_type(flow_id), to: Editor

  @doc """
  Lists all hub nodes in a flow with their hub_ids.
  Useful for populating Jump node target dropdown.
  """
  @spec list_hubs(integer()) :: [map()]
  defdelegate list_hubs(flow_id), to: Editor

  @doc "Returns the default Hub color as a hex value."
  defdelegate hub_color_default_hex(), to: Editor

  @doc "Resolves a Hub color to a valid hex value."
  defdelegate resolve_hub_color(color), to: Editor

  @doc "Resolves a historical named Hub color to its hex value."
  defdelegate resolve_legacy_hub_color(color), to: Editor

  @doc """
  Finds a hub node in a flow by its hub_id string.
  Returns nil if not found.
  """
  @spec get_hub_by_hub_id(integer(), String.t()) :: flow_node() | nil
  defdelegate get_hub_by_hub_id(flow_id, hub_id), to: Editor

  @doc """
  Lists jump nodes that reference a given hub_id within a flow.
  """
  @spec list_referencing_jumps(integer(), String.t()) :: [map()]
  defdelegate list_referencing_jumps(flow_id, hub_id), to: Editor

  @doc """
  Lists all Exit nodes for a given flow.
  Used by subflow nodes to generate dynamic output pins.
  """
  @spec list_exit_nodes_for_flow(integer()) :: [map()]
  defdelegate list_exit_nodes_for_flow(flow_id), to: Editor

  @doc """
  Finds all subflow nodes that reference a given flow within the same project.
  Used for stale detection when a flow is deleted or exits change.
  """
  @spec list_subflow_nodes_referencing(integer(), integer()) :: [map()]
  defdelegate list_subflow_nodes_referencing(flow_id, project_id), to: Editor

  @doc """
  Lists all unique outcome tags used across exit nodes in a project.
  Used for autocomplete suggestions in exit node sidebar.
  """
  @spec list_outcome_tags_for_project(integer()) :: [String.t()]
  defdelegate list_outcome_tags_for_project(project_id), to: Editor

  @doc """
  Finds all nodes (subflow and exit with flow_reference) that reference a given flow.
  Used by exit nodes to show "Referenced by" section.
  """
  @spec list_nodes_referencing_flow(integer(), integer()) :: [map()]
  defdelegate list_nodes_referencing_flow(flow_id, project_id), to: Editor

  @doc """
  Checks if a subflow reference would create a circular dependency.
  """
  @spec has_circular_reference?(integer(), integer()) :: boolean()
  defdelegate has_circular_reference?(source_flow_id, target_flow_id), to: Editor

  @doc """
  Safely parses a value to integer. Returns nil if parsing fails.
  """
  defdelegate safe_to_integer(value), to: Editor

  # =============================================================================
  # Flow variable-reference projection
  # =============================================================================

  @doc "Returns Flow-node IDs with stale variable references."
  @spec list_stale_node_ids(integer()) :: MapSet.t(integer())
  defdelegate list_stale_node_ids(flow_id), to: References

  # =============================================================================
  # Connections - CRUD Operations
  # =============================================================================

  @doc """
  Lists all connections for a flow.
  """
  @spec list_connections(integer()) :: [connection()]
  defdelegate list_connections(flow_id), to: Editor

  @doc """
  Gets a single connection by ID within a flow.
  Returns `nil` if the connection doesn't exist or doesn't belong to the flow.
  """
  @spec get_connection(integer(), integer()) :: connection() | nil
  defdelegate get_connection(flow_id, connection_id), to: Editor

  @doc """
  Gets a single connection by ID within a flow.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_connection!(integer(), integer()) :: connection()
  defdelegate get_connection!(flow_id, connection_id), to: Editor

  @doc """
  Gets a connection by ID without flow validation.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_connection_by_id!(integer()) :: connection()
  defdelegate get_connection_by_id!(connection_id), to: Editor

  @doc """
  Creates a new connection between two nodes.
  """
  @spec create_connection(flow(), flow_node(), flow_node(), attrs()) ::
          {:ok, connection()} | {:error, changeset()}
  defdelegate create_connection(flow, source_node, target_node, attrs), to: Editor

  @doc """
  Creates a new connection with node IDs in attrs.
  """
  @spec create_connection_with_attrs(flow(), attrs()) ::
          {:ok, connection()} | {:error, changeset()}
  defdelegate create_connection_with_attrs(flow, attrs), to: Editor

  @doc false
  defdelegate create_connection_without_dashboard_broadcast(flow, attrs),
    to: Editor

  @doc """
  Updates a connection.
  """
  @spec update_connection(connection(), attrs()) :: {:ok, connection()} | {:error, changeset()}
  defdelegate update_connection(connection, attrs), to: Editor

  @doc """
  Deletes a connection.
  """
  @spec delete_connection(connection()) :: {:ok, connection()} | {:error, changeset()}
  defdelegate delete_connection(connection), to: Editor

  @doc """
  Deletes one connection by its project-scoped flow and persisted identity.
  """
  @spec delete_connection_by_id(integer(), integer()) ::
          {:ok, connection()} | {:error, term()}
  defdelegate delete_connection_by_id(flow_id, connection_id),
    to: Editor

  @doc """
  Deletes connections between two nodes.
  """
  @spec delete_connection_by_nodes(integer(), integer(), integer()) :: {integer(), nil | term()}
  defdelegate delete_connection_by_nodes(flow_id, source_node_id, target_node_id),
    to: Editor

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
              to: Editor

  @doc """
  Returns a changeset for tracking connection changes.
  """
  @spec change_connection(connection(), attrs()) :: changeset()
  defdelegate change_connection(connection, attrs \\ %{}), to: Editor

  @doc """
  Gets all outgoing connections from a node.
  """
  @spec get_outgoing_connections(integer()) :: [connection()]
  defdelegate get_outgoing_connections(node_id), to: Editor

  @doc """
  Gets all incoming connections to a node.
  """
  @spec get_incoming_connections(integer()) :: [connection()]
  defdelegate get_incoming_connections(node_id), to: Editor

  @doc """
  Deletes all connections within a flow where both source and target are in the given node IDs list.
  Used by FlowSync to clear internal connections before rebuilding them.
  """
  @spec delete_connections_among_nodes(integer(), [integer()]) :: {integer(), nil | term()}
  defdelegate delete_connections_among_nodes(flow_id, node_ids), to: Editor

  @doc false
  defdelegate delete_connections_among_nodes_without_dashboard_broadcast(flow_id, node_ids),
    to: Editor

  # =============================================================================
  # Evaluator — Engine
  # =============================================================================

  @doc "Initialize an evaluator state for a flow."
  defdelegate evaluator_init(variables, start_node_id), to: Runtime

  @doc "Advance a player session until it reaches player-facing interaction."
  defdelegate player_step_until_interactive(state, nodes, connections, opts \\ []), to: Runtime

  @doc "Creates and advances a Flow-owned player runtime session."
  defdelegate start_player_session(flow, variables), to: Runtime

  @doc "Reconstitutes a previously stored ephemeral player session."
  defdelegate restore_player_session(flow, state, nodes, connections, scene_id), to: Runtime

  @doc "Records the Flow-owned fact that a player session started."
  defdelegate record_player_started(scope_or_user, flow), to: Runtime

  @doc "Advances a player session after an explicit continue action."
  defdelegate continue_player_session(session), to: Runtime

  @doc "Chooses a response and advances the player session."
  defdelegate choose_player_response(session, response_id), to: Runtime

  @doc "Resolves the response selected by a numbered player shortcut."
  defdelegate player_response_id_by_number(responses, mode, number), to: Runtime

  @doc "Restores the previous renderable player state."
  defdelegate go_back_player_session(session), to: Runtime

  @doc "Restarts a complete player run at its root Flow."
  defdelegate restart_player_session(session), to: Runtime

  @doc "Returns whether a player session can restore a renderable snapshot."
  defdelegate player_session_can_go_back?(session), to: Runtime

  @doc "Composes the active nested sequences for the current player frame."
  defdelegate compose_player_sequences(state, nodes), to: Runtime

  @doc "Interprets rich player text references with adapter-owned rendering."
  defdelegate interpolate_player_rich_text(text, variables, renderer), to: Runtime

  @doc "Maps authored player references with adapter-owned presentation."
  defdelegate map_player_rich_text_references(text, renderer), to: Runtime

  @doc "Interpolates plain player response references."
  defdelegate interpolate_player_response_text(text, variables), to: Runtime

  @doc "Formats a player variable without presentation-specific escaping."
  defdelegate format_player_value(value), to: Runtime

  @doc "Builds semantic metadata and statistics for a player outcome."
  defdelegate build_player_outcome(node, state), to: Runtime

  @doc "Advance the evaluator by one step."
  defdelegate evaluator_step(state, nodes, connections), to: Runtime

  @doc "Step back to the previous node."
  defdelegate evaluator_step_back(state), to: Runtime

  @doc "Choose a response in a waiting_input state."
  defdelegate evaluator_choose_response(state, response_id, connections), to: Runtime

  @doc "Push a sub-flow context onto the call stack."
  defdelegate evaluator_push_flow_context(state, node_id, nodes, connections, flow_name), to: Runtime

  @doc "Pop a sub-flow context from the call stack."
  defdelegate evaluator_pop_flow_context(state), to: Runtime

  @doc "Find the parent-flow connection after returning from a sub-flow exit."
  defdelegate evaluator_find_return_connection(connections, return_node_id, returned_exit_node_id), to: Runtime

  @doc "Reset the evaluator to its initial state."
  defdelegate evaluator_reset(state), to: Runtime

  @doc "Toggle a breakpoint on a node."
  defdelegate evaluator_toggle_breakpoint(state, node_id), to: Runtime

  @doc "Check if the evaluator is at a breakpoint."
  defdelegate evaluator_at_breakpoint?(state), to: Runtime

  @doc "Record a breakpoint hit."
  defdelegate evaluator_add_breakpoint_hit(state, node_id), to: Runtime

  @doc "Set a variable value in the evaluator state."
  defdelegate evaluator_set_variable(state, key, value), to: Runtime

  @doc "Extend the step limit for the evaluator."
  defdelegate evaluator_extend_step_limit(state), to: Runtime

  @doc "Add a console entry to the evaluator state."
  defdelegate evaluator_add_console_entry(state, level, node_id, label, message), to: Runtime

  # =============================================================================
  # Evaluator — Helpers
  # =============================================================================

  @doc "Strip HTML tags and truncate to max_length characters."
  defdelegate evaluator_strip_html(text, max_length \\ 40), to: Runtime

  @doc "Format a debug value for display."
  defdelegate evaluator_format_value(value), to: Runtime

  # =============================================================================
  # Evaluator — Condition & Instruction
  # =============================================================================

  @doc "Evaluate a condition expression against variables."
  defdelegate evaluate_condition(condition, variables), to: Runtime

  @doc "Execute instruction assignments against variables."
  defdelegate execute_instructions(assignments, variables), to: Runtime

  # =============================================================================
  # Serialization
  # =============================================================================

  @doc """
  Projects one node into the stable editor-canvas contract.

  This is intentionally Flow-owned: color resolution and assignment type
  warnings must be identical for an incremental node event and a full canvas
  reload. Web only decides which LiveView event carries this DTO.
  """
  @spec serialize_editor_node(flow_node(), pos_integer()) :: map()
  defdelegate serialize_editor_node(node, project_id), to: Editor

  @doc """
  Serializes a flow with its nodes and connections for the Rete.js canvas.
  Returns a map with `nodes` and `connections` arrays in the format expected
  by the JavaScript flow canvas hook.
  """
  @spec serialize_for_canvas(flow(), keyword()) :: map()
  defdelegate serialize_for_canvas(flow, opts \\ []), to: Editor

  @doc """
  Enriches node data with resolved values for the canvas (single node).
  Used by individual node update events. For bulk serialization, use the 3-arity version.
  """
  @spec resolve_node_colors(String.t(), map()) :: map()
  defdelegate resolve_node_colors(type, data), to: Editor

  @doc """
  Enriches node data with resolved values for the canvas.
  Adds validated Hub colors and resolves subflow references.
  The cache is pre-fetched by batch_resolve_subflow_data/1.
  When called via the 2-arity version (single-node updates), cache is `%{}`.
  """
  @spec resolve_node_colors(String.t(), map(), map()) :: map()
  defdelegate resolve_node_colors(arg1, data, cache), to: Editor

  @doc """
  Adds the health flags `serialize_for_canvas/2` injects, for callers reading
  nodes straight from the database.

  The editorial checks in `HealthChecker` read `has_stale_refs` and
  `has_type_warnings` off a node's data. The canvas serializer computes them; a
  project-wide sweep does not go through it, so it applies them here instead —
  otherwise the dashboard would silently miss three codes the editor reports.

  Takes the PREPARED type map (`variable_type_map/1`), not the variable list, so
  a project-wide sweep builds it once for every flow instead of once per node.
  """
  @spec add_health_flags([map()], MapSet.t(), %{String.t() => String.t()}) :: [map()]
  defdelegate add_health_flags(nodes, stale_node_ids, variable_types), to: Health

  # =============================================================================
  # Condition
  # =============================================================================

  defdelegate condition_sanitize(condition), to: Expressions
  defdelegate condition_new(), to: Expressions
  defdelegate condition_has_rules?(condition), to: Expressions
  defdelegate condition_to_json(condition), to: Expressions
  defdelegate condition_parse(condition), to: Expressions

  # =============================================================================
  # Instruction
  # =============================================================================

  defdelegate instruction_sanitize(assignments), to: Expressions
  defdelegate instruction_format_short(assignment), to: Expressions

  defdelegate instruction_has_type_warnings?(assignments, variable_types), to: Expressions

  @doc "Builds the `\"shortcut.name\" => block_type` map the type-warning check reads."
  defdelegate variable_type_map(project_variables), to: Expressions

  # =============================================================================
  # Dialogue preview and debug runtime
  # =============================================================================

  @doc "Builds Flow-owned evaluator variables from the shared persistence read model."
  defdelegate build_runtime_variables(project_id), to: Runtime

  @doc "Starts the editor dialogue preview at a Flow node."
  defdelegate start_dialogue_preview(flow_id, node_id), to: Runtime

  @doc "Follows a dialogue preview output pin."
  defdelegate follow_dialogue_preview(flow_id, node_id, source_pin), to: Runtime

  @doc "Loads the runtime graph used by Flow execution."
  defdelegate load_runtime_graph(flow_id), to: Runtime

  @doc "Returns the entry node in a Flow runtime graph."
  defdelegate runtime_entry_node_id(nodes), to: Runtime

  @doc "Returns the active edge represented by a debugger execution path."
  defdelegate debug_active_connection(path, connections), to: Runtime

  @doc "Starts a complete Flow-owned debug session."
  defdelegate start_debug_session(scope_or_user, flow), to: Runtime

  @doc "Changes the start node and resets a debug session."
  defdelegate debug_select_start_node(state, nodes, node_id), to: Runtime

  @doc "Advances a debug session, including cross-Flow transitions."
  defdelegate debug_step(state, nodes, connections, flow_name), to: Runtime

  @doc "Advances an auto-playing debug session and returns its scheduling action."
  defdelegate debug_auto_step(state, nodes, connections, flow_name), to: Runtime

  @doc "Restores the previous debug evaluator snapshot."
  defdelegate debug_step_back(state), to: Runtime

  @doc "Chooses a response in a waiting debug session."
  defdelegate debug_choose_response(state, response_id, connections), to: Runtime

  @doc "Resets a debug session, returning to its root Flow when nested."
  defdelegate reset_debug_session(state, nodes, connections), to: Runtime

  @doc "Returns the Flow-owned empty state for a stopped debug session."
  defdelegate stop_debug_session(), to: Runtime

  @doc "Coerces and applies a debug variable override."
  defdelegate set_debug_variable(state, key, raw_value), to: Runtime

  @doc "Extends a debug session step limit."
  defdelegate extend_debug_step_limit(state), to: Runtime

  @doc "Toggles a debug breakpoint."
  defdelegate toggle_debug_breakpoint(state, node_id), to: Runtime

  # =============================================================================
  # DebugSessionStore
  # =============================================================================

  defdelegate debug_session_store(key, data), to: Runtime
  defdelegate debug_session_take(key), to: Runtime

  # =============================================================================
  # NavigationHistoryStore
  # =============================================================================

  defdelegate nav_history_get(key), to: Runtime
  defdelegate nav_history_put(key, data), to: Runtime
  defdelegate nav_history_clear(key), to: Runtime

  @doc "Counts non-deleted flows for a project."
  defdelegate count_flows(project_id), to: Editor

  @doc "Returns per-flow node stats for a project. %{flow_id => %{node_count, dialogue_count, condition_count}}."
  defdelegate flow_stats_for_project(project_id), to: Health

  @doc "Returns per-flow localizable word counts from runtime flow-node fields. %{flow_id => word_count}."
  defdelegate flow_word_counts(project_id), to: Health

  @doc "Returns the player-facing word count for an already-loaded Flow."
  defdelegate flow_word_count(flow), to: Health

  @doc """
  Project-wide node type distribution. `%{node_type => count}`.

  Distinct from `count_nodes_by_type/1`, which counts within ONE flow.
  """
  defdelegate count_project_nodes_by_type(project_id), to: Health

  @doc "Top speakers by dialogue line count across every flow in the project."
  defdelegate count_dialogue_lines_by_speaker(project_id, limit \\ 10), to: Health

  @doc "Project-wide flow health findings for the dashboard (canonical shape)."
  defdelegate list_dashboard_health_findings(project_id), to: Health

  @doc "Canonical flow health findings scoped to already-loaded export flows."
  defdelegate list_export_health_findings(project_id, flows, context \\ %{}), to: Health

  @doc """
  Runs the canonical structural analysis for one flow.
  Returns `{:ok, %StructuralAnalysis.Analysis{}}` with deterministic findings.
  """
  @spec analyze_flow_structure(integer(), integer()) ::
          {:ok, Analysis.t()} | {:error, :not_found}
  defdelegate analyze_flow_structure(project_id, flow_id), to: Health

  @doc "Runs the canonical structural analysis on an already-loaded flow."
  @spec analyze_loaded_flow_structure(flow()) :: Analysis.t()
  defdelegate analyze_loaded_flow_structure(flow), to: Health

  @doc "Runs the canonical structural analysis on serialize_for_canvas output (no queries)."
  @spec analyze_serialized_flow_structure(map(), integer()) :: Analysis.t()
  defdelegate analyze_serialized_flow_structure(flow_data, project_id), to: Health

  @doc """
  Every variable a flow can reference: sheet blocks, scene pins and scene zones.

  The ONE definition, because the health checkers compare a node's assignments
  against it and the editor and the dashboard must not be looking at different
  sets — a flow that assigns to a pin property would otherwise get a type warning
  on one surface and not the other. `VariableHelpers.list_all_variables/1`
  delegates here.
  """
  @spec list_referenceable_variables(integer()) :: [map()]
  defdelegate list_referenceable_variables(project_id), to: Expressions

  @doc "Searches and projects Flow variable suggestions for the dialogue editor."
  @spec search_variable_suggestions([map()], String.t()) :: [VariableSearch.suggestion()]
  defdelegate search_variable_suggestions(variables, query), to: Expressions

  @doc "Returns a bounded page of Flow-owned variable picker options."
  @spec search_variable_options([map()], keyword()) ::
          {[VariableSearch.picker_option()], boolean()}
  defdelegate search_variable_options(variables, opts \\ []), to: Expressions

  @doc """
  Every health finding of a flow from already-serialized canvas data.

  The editor's entry into the single composition point the dashboard also uses
  (`StructuralAnalysis.findings/1`). Zero extra node queries: the serializer's
  output is already resolved and already carries the health flags.
  """
  @spec flow_health_findings(map(), integer()) :: [map()]
  defdelegate flow_health_findings(flow_data, project_id), to: Health

  @doc "Counts non-deleted flow nodes across all flows in a project."
  defdelegate count_nodes_for_project(project_id), to: Editor

  # =============================================================================
  # Versioning
  # =============================================================================

  @doc """
  Creates a new version snapshot of the given flow.
  """
  defdelegate create_version(flow, user_id, opts \\ []), to: Versioning

  @doc """
  Lists all versions for a flow.
  """
  defdelegate list_versions(flow_id, opts \\ []), to: Versioning

  @doc """
  Gets a specific version by flow_id and version_number.
  """
  defdelegate get_version(flow_id, version_number), to: Versioning

  @doc """
  Gets the latest version for a flow.
  """
  defdelegate get_latest_version(flow_id), to: Versioning

  @doc """
  Returns the total number of versions for a flow.
  """
  defdelegate count_versions(flow_id), to: Versioning

  @doc """
  Creates a version if enough time has passed since the last version.
  """
  defdelegate maybe_create_version(flow, user_id, opts \\ []), to: Versioning

  @doc """
  Deletes a version and its snapshot.
  """
  defdelegate delete_version(version), to: Versioning

  @doc "Updates the name and description of a Flow version."
  defdelegate update_version(version, attrs), to: Versioning

  @doc false
  defdelegate load_version_snapshot(version), to: Versioning

  @doc "Decides whether restore must first warn about unsaved changes or can show its conflict report."
  defdelegate prepare_version_restore(flow, version), to: Versioning

  @doc "Loads a target Flow version and builds its restore conflict report."
  defdelegate prepare_version_restore_conflicts(flow, version), to: Versioning

  @doc """
  Restores a flow to a specific version.
  """
  defdelegate restore_version(flow, version, opts \\ []), to: Versioning

  @doc "Returns whether Flow version restore is currently enabled."
  defdelegate restore_enabled?(), to: Versioning

  @doc "Ensures that Flow version restore is currently enabled."
  defdelegate ensure_version_restore_enabled(), to: Versioning

  @doc "Builds the current Flow snapshot used for change detection."
  defdelegate build_version_snapshot(flow), to: Versioning

  @doc "Returns whether two Flow version snapshots differ."
  defdelegate version_snapshot_has_changes?(previous, current), to: Versioning

  @doc "Builds the Flow-owned restore-conflict preview."
  defdelegate detect_version_restore_conflicts(snapshot, flow), to: Versioning

  @doc "Returns the previous and next stored Flow version numbers."
  defdelegate get_adjacent_version_numbers(flow_id, current_number), to: Versioning

  @doc "Counts stored Flow versions created since the given instant."
  defdelegate count_versions_since(flow_id, since), to: Versioning

  @doc "Returns whether this project can create or promote another named Flow version."
  defdelegate can_create_named_version?(project_id, workspace_id), to: Versioning

  @doc "Serializes a Flow snapshot for the read-only comparison canvas."
  defdelegate serialize_version_snapshot(snapshot), to: Versioning

  @doc """
  Sets the current version for a flow.
  """
  defdelegate set_current_version(flow, version_or_nil), to: Versioning

  # =============================================================================
  # Sequences - Multi-track composition entity (P-3 of flow-player-redesign)
  # =============================================================================

  @doc "Lists active sequences for a flow, ordered by insertion time."
  defdelegate list_sequences(flow_id), to: Editor

  @doc "Lists soft-deleted sequences for a flow."
  defdelegate list_deleted_sequences(flow_id), to: Editor

  @doc "Fetches an active sequence by id scoped to a flow. Returns nil if absent or deleted."
  defdelegate get_sequence(flow_id, id), to: Editor

  @doc "Fetches a sequence by id scoped to a flow. Raises if absent."
  defdelegate get_sequence!(flow_id, id), to: Editor

  @doc "Gets the sequence-specific configuration for an active sequence node."
  defdelegate get_sequence_config(sequence_id), to: Editor

  @doc "Creates a sequence for a flow."
  defdelegate create_sequence(flow_id, attrs), to: Editor

  @doc "Updates a sequence (name, canvas geometry, or parent)."
  defdelegate update_sequence(sequence, attrs), to: Editor

  @doc "Soft-deletes a sequence."
  defdelegate delete_sequence(sequence), to: Editor

  @doc "Restores a soft-deleted sequence."
  defdelegate restore_sequence(sequence), to: Editor

  @doc """
  Atomically wraps a node selection into a new Sequence (same-parent required;
  rejects mixed parents). See `SequenceCrud.wrap_selection_in_sequence/3`.
  """
  defdelegate wrap_selection_in_sequence(flow, node_ids, attrs \\ %{}), to: Editor

  @doc "Lists visual layers assigned to a sequence."
  defdelegate list_sequence_visual_layers(sequence_id), to: Editor

  @doc "Fetches a visual layer scoped to its sequence."
  defdelegate get_sequence_visual_layer(sequence_id, id), to: Editor

  @doc "Creates a visual layer for a sequence."
  defdelegate create_sequence_visual_layer(sequence_id, attrs), to: Editor

  @doc "Updates a sequence visual layer."
  defdelegate update_sequence_visual_layer(layer, attrs), to: Editor

  @doc "Deletes a sequence visual layer."
  defdelegate delete_sequence_visual_layer(layer), to: Editor

  @doc "Lists the audio tracks assigned to a sequence (one per kind, 0-3 rows)."
  defdelegate list_sequence_tracks(sequence_id), to: Editor

  @doc "Fetches the single track for `(sequence_id, kind)`, or nil."
  defdelegate get_sequence_track(sequence_id, kind), to: Editor

  @doc "Upserts a track slot. `kind` ∈ {music, ambience, sfx}."
  defdelegate upsert_sequence_track(sequence_id, kind, attrs), to: Editor

  @doc "Clears the track for `(sequence_id, kind)`. No-op if already empty."
  defdelegate clear_sequence_track(sequence_id, kind), to: Editor
end
