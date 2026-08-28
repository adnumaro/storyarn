defmodule Storyarn.Flows.Editor do
  @moduledoc """
  Public capability boundary for authored Flow structure and content.

  Editor owns the Flow aggregate, nodes, connections, sequences, hierarchy,
  authoring rules, and the foreign catalogs used by the canvas. Callers enter
  through this module instead of depending on its commands, queries, data
  projections, or rules.
  """

  alias Storyarn.Flows.ConnectionCrud
  alias Storyarn.Flows.Editor.Commands.ItemCapacity
  alias Storyarn.Flows.Editor.Commands.NodeRestore
  alias Storyarn.Flows.Editor.Commands.Tracked
  alias Storyarn.Flows.Editor.Queries.CanvasSerializer
  alias Storyarn.Flows.EditorCatalog
  alias Storyarn.Flows.ExitTargetScenes
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowCrud
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.HubColors
  alias Storyarn.Flows.NodeConnectionRules
  alias Storyarn.Flows.NodeCrud
  alias Storyarn.Flows.NodeEditor
  alias Storyarn.Flows.NodeLabel
  alias Storyarn.Flows.NodeTypes
  alias Storyarn.Flows.RuntimeKey
  alias Storyarn.Flows.SequenceCrud
  alias Storyarn.Flows.ShortcutGenerator
  alias Storyarn.Flows.TreeOperations

  @type flow :: Flow.t()
  @type flow_node :: FlowNode.t()
  @type connection :: Storyarn.Flows.FlowConnection.t()
  @type attrs :: map()

  # Authored node vocabulary and value contracts
  defdelegate node_types(), to: FlowNode
  defdelegate node_label(node), to: NodeLabel, as: :for_node
  defdelegate node_specific_label(node), to: NodeLabel, as: :specific_for_node
  defdelegate node_type_label(type), to: NodeLabel, as: :type_label
  defdelegate editor_node_types(), to: NodeTypes, as: :editor_types
  defdelegate user_addable_node_types(), to: NodeTypes, as: :user_addable_types
  defdelegate default_node_data(type), to: NodeTypes, as: :default_data
  defdelegate node_form_data(type, data), to: NodeTypes, as: :form_data
  defdelegate duplicate_node_data(type, data), to: NodeTypes, as: :duplicate_data
  defdelegate new_dialogue_id(), to: RuntimeKey
  defdelegate new_response_id(), to: RuntimeKey
  defdelegate runtime_key_for_node(node, source_field), to: RuntimeKey, as: :for_node
  defdelegate dialogue_id!(data), to: RuntimeKey
  defdelegate valid_dialogue_id?(value), to: RuntimeKey
  defdelegate valid_response_id?(value), to: RuntimeKey
  defdelegate hub_color_default_hex(), to: HubColors, as: :default_hex
  defdelegate resolve_hub_color(color), to: HubColors, as: :resolve
  defdelegate resolve_legacy_hub_color(color), to: HubColors, as: :resolve_legacy
  defdelegate can_create_item?(project), to: ItemCapacity
  defdelegate can_create_items?(project, requested), to: ItemCapacity

  # Connection semantics consumed by authoring and read-only graph analysis
  defdelegate connection_optional_types(), to: NodeConnectionRules
  defdelegate outgoing_optional_types(), to: NodeConnectionRules
  defdelegate connection_optional_type?(type), to: NodeConnectionRules
  defdelegate can_be_unreachable?(type), to: NodeConnectionRules
  defdelegate needs_outgoing_connection?(type), to: NodeConnectionRules
  defdelegate output_pins(type, data \\ %{}), to: NodeConnectionRules
  defdelegate node_output_pins(type, data), to: NodeConnectionRules, as: :output_pins
  defdelegate accepted_output_pins(type, data), to: NodeConnectionRules
  defdelegate canonical_output_pin(type, data, source_pin), to: NodeConnectionRules
  defdelegate valid_output_pin?(type, data, source_pin), to: NodeConnectionRules
  defdelegate valid_input_pin?(type, target_pin), to: NodeConnectionRules

  # Node editor operations
  defdelegate apply_node_operation(node, flow, project_id, operation, payload),
    to: NodeEditor,
    as: :apply_operation

  defdelegate put_node_condition(data, condition), to: NodeEditor, as: :put_condition
  defdelegate put_response_condition(data, response_id, condition), to: NodeEditor
  defdelegate toggle_condition_switch_mode(data), to: NodeEditor
  defdelegate next_dialogue_response_number(data), to: NodeEditor
  defdelegate append_dialogue_response(data), to: NodeEditor
  defdelegate append_dialogue_response(data, default_text), to: NodeEditor
  defdelegate remove_dialogue_response(data, response_id), to: NodeEditor
  defdelegate put_dialogue_response_text(data, response_id, text), to: NodeEditor
  defdelegate put_dialogue_response_condition(data, response_id, condition), to: NodeEditor
  defdelegate put_dialogue_response_instruction(data, response_id, instruction), to: NodeEditor
  defdelegate put_dialogue_response_assignments(data, response_id, assignments), to: NodeEditor
  defdelegate dialogue_technical_id(flow, node, speaker_name), to: NodeEditor
  defdelegate put_exit_mode(data, mode), to: NodeEditor
  defdelegate exit_mode(mode), to: NodeEditor
  defdelegate validate_exit_flow_reference(project_id, current_flow_id, value), to: NodeEditor
  defdelegate put_exit_flow_reference(data, flow_id), to: NodeEditor
  defdelegate add_exit_outcome_tag(data, tag), to: NodeEditor
  defdelegate remove_exit_outcome_tag(data, tag), to: NodeEditor
  defdelegate put_exit_color(data, color), to: NodeEditor
  defdelegate put_exit_target(data, type, id), to: NodeEditor
  defdelegate exit_technical_id(flow, node), to: NodeEditor
  defdelegate validate_subflow_reference(value, current_flow_id), to: NodeEditor
  defdelegate put_subflow_reference(data, flow_id), to: NodeEditor
  defdelegate put_instruction_assignments(data, assignments), to: NodeEditor
  defdelegate put_annotation_color(data, color), to: NodeEditor
  defdelegate put_annotation_font_size(data, size), to: NodeEditor
  defdelegate put_hub_color(data, color), to: NodeEditor

  # Flow hierarchy and lifecycle
  defdelegate create_editor_node(scope, flow, attrs, creation_method),
    to: Tracked,
    as: :create_node

  defdelegate duplicate_editor_node(scope, flow, node), to: Tracked, as: :duplicate_node

  defdelegate create_editor_sequence(scope, flow, attrs, creation_method),
    to: Tracked,
    as: :create_sequence

  defdelegate wrap_editor_selection(scope, flow, node_ids, attrs),
    to: Tracked,
    as: :wrap_selection_in_sequence

  defdelegate create_editor_sequence_visual_layer(scope, flow, sequence_id, attrs),
    to: Tracked,
    as: :create_sequence_visual_layer

  defdelegate update_editor_sequence_visual_layer(scope, flow, sequence_id, layer, attrs),
    to: Tracked,
    as: :update_sequence_visual_layer

  defdelegate upsert_editor_sequence_track(scope, flow, sequence_id, kind, attrs),
    to: Tracked,
    as: :upsert_sequence_track

  defdelegate list_flows(project_id), to: FlowCrud
  defdelegate list_flows_tree(project_id), to: FlowCrud
  defdelegate list_flows_by_parent(project_id, parent_id), to: TreeOperations
  defdelegate default_search_limit(), to: FlowCrud
  defdelegate search_flows(project_id, query, opts \\ []), to: FlowCrud
  defdelegate search_flows_in_projects(project_ids, query, opts \\ []), to: FlowCrud
  defdelegate search_flows_deep(project_id, query, opts \\ []), to: FlowCrud
  defdelegate get_flow(project_id, flow_id), to: FlowCrud
  defdelegate get_flow_brief(project_id, flow_id), to: FlowCrud
  defdelegate get_flow!(project_id, flow_id, opts \\ []), to: FlowCrud
  defdelegate get_flow_including_deleted(project_id, flow_id), to: FlowCrud
  defdelegate create_linked_flow(project, parent_flow, node), to: FlowCrud

  def create_linked_flow(project, parent_flow, node, opts) when is_list(opts),
    do: FlowCrud.create_linked_flow(project, parent_flow, node, opts)

  def create_linked_flow(%{user: %{id: actor_id}} = scope, project, parent_flow, node)
      when is_integer(actor_id) and actor_id > 0, do: FlowCrud.create_linked_flow(scope, project, parent_flow, node)

  defdelegate create_linked_flow(scope, project, parent_flow, node, opts), to: FlowCrud
  defdelegate create_flow(project, attrs), to: FlowCrud
  defdelegate create_flow(scope, project, attrs), to: FlowCrud
  defdelegate create_flow_in_transaction(project, attrs), to: FlowCrud
  defdelegate create_flow_in_transaction(scope, project, attrs), to: FlowCrud
  defdelegate update_flow(flow, attrs), to: FlowCrud
  defdelegate update_flow_scene(flow, attrs), to: FlowCrud
  defdelegate set_main_flow(flow), to: FlowCrud
  defdelegate delete_flow(flow), to: FlowCrud
  defdelegate delete_flow(scope, flow), to: FlowCrud
  defdelegate delete_flow_subtree(flow), to: FlowCrud
  defdelegate delete_flow_subtree(scope, flow), to: FlowCrud
  defdelegate delete_flow_subtree_in_transaction(flow), to: FlowCrud
  defdelegate delete_flow_subtree_in_transaction(scope, flow), to: FlowCrud
  defdelegate delete_flow_subtree_by_id_in_transaction(scope, project_id, flow_id), to: FlowCrud
  defdelegate hard_delete_flow(flow), to: FlowCrud
  defdelegate restore_flow(flow), to: FlowCrud
  defdelegate restore_flow(flow, extract_flow_nodes), to: FlowCrud
  defdelegate list_deleted_flows(project_id), to: FlowCrud
  defdelegate change_flow(flow, attrs \\ %{}), to: FlowCrud
  defdelegate count_flows(project_id), to: FlowCrud
  defdelegate count_nodes_for_project(project_id), to: FlowCrud
  defdelegate broadcast_flow_refreshes(flow_ids), to: FlowCrud
  defdelegate flow_deleted?(flow), to: Flow, as: :deleted?
  defdelegate reorder_flows(project_id, parent_id, flow_ids), to: TreeOperations
  defdelegate move_flow_to_position(flow, new_parent_id, new_position), to: TreeOperations
  defdelegate next_flow_position(project_id, parent_id), to: TreeOperations, as: :next_position
  defdelegate build_flow_tree(flows), to: TreeOperations, as: :build_tree_from_flat_list
  defdelegate prepare_flow_create(attrs, project_id, exclude_id), to: ShortcutGenerator, as: :prepare_create
  defdelegate prepare_flow_update(flow, attrs, referenced?), to: ShortcutGenerator, as: :prepare_update
  defdelegate generate_flow_shortcut(name, project_id, exclude_id \\ nil), to: ShortcutGenerator, as: :generate

  # Foreign editor catalogs
  defdelegate load_editor_catalog(project_id), to: EditorCatalog, as: :load
  defdelegate search_mentions(project_id, query), to: EditorCatalog
  defdelegate search_speaker_options(project_id, query, opts \\ []), to: EditorCatalog, as: :speaker_options
  defdelegate initial_speaker_options(project_id, selected_ids), to: EditorCatalog
  defdelegate search_asset_options(project_id, kind, opts \\ []), to: EditorCatalog, as: :asset_options
  defdelegate initial_asset_options(project_id, kind, selected_ids), to: EditorCatalog
  defdelegate get_preview_speaker_name(project_id, speaker_id), to: EditorCatalog, as: :speaker_name
  defdelegate get_editor_scene_name(project_id, scene_id), to: EditorCatalog, as: :scene_name
  defdelegate search_exit_target_scenes(project_id, query, opts \\ []), to: ExitTargetScenes, as: :search

  # Nodes
  defdelegate list_nodes(flow_id), to: NodeCrud
  defdelegate list_runtime_nodes(flow_id), to: NodeCrud
  defdelegate lock_flow_nodes_for_update(flow), to: NodeCrud
  defdelegate get_node(flow_id, node_id), to: NodeCrud
  defdelegate get_node!(flow_id, node_id), to: NodeCrud
  defdelegate get_node_by_id!(flow_id, node_id), to: NodeCrud
  defdelegate hub_id_exists?(flow_id, hub_id, exclude_node_id), to: NodeCrud
  defdelegate list_hubs(flow_id), to: NodeCrud
  defdelegate get_hub_by_hub_id(flow_id, hub_id), to: NodeCrud
  defdelegate list_referencing_jumps(flow_id, hub_id), to: NodeCrud
  defdelegate list_dialogue_nodes_by_speaker(project_id, sheet_id), to: NodeCrud
  defdelegate count_nodes_by_type(flow_id), to: NodeCrud
  defdelegate list_exit_nodes_for_flow(flow_id), to: NodeCrud
  defdelegate list_outcome_tags_for_project(project_id), to: NodeCrud
  defdelegate list_subflow_nodes_referencing(flow_id, project_id), to: NodeCrud
  defdelegate list_nodes_referencing_flow(flow_id, project_id), to: NodeCrud
  defdelegate batch_resolve_subflow_data(nodes, project_id \\ nil), to: NodeCrud
  defdelegate resolve_subflow_data(data, cache), to: NodeCrud
  defdelegate batch_resolve_exit_data(nodes, project_id \\ nil), to: NodeCrud
  defdelegate resolve_exit_data(data), to: NodeCrud
  defdelegate resolve_exit_data(data, project_id), to: NodeCrud
  defdelegate resolve_exit_data(data, project_id, cache), to: NodeCrud
  defdelegate safe_to_integer(value), to: NodeCrud
  defdelegate create_node(flow, attrs), to: NodeCrud
  defdelegate create_node_without_dashboard_broadcast(flow, attrs), to: NodeCrud
  defdelegate has_circular_reference?(source_flow_id, target_flow_id), to: NodeCrud
  defdelegate circular_reference_pairs(pairs), to: Storyarn.Flows.NodeCreate
  defdelegate update_node(node, attrs), to: NodeCrud
  defdelegate update_node_without_dashboard_broadcast(node, attrs), to: NodeCrud
  defdelegate update_node_position(node, attrs), to: NodeCrud
  defdelegate update_node_parent(node, parent_id), to: NodeCrud
  defdelegate batch_update_positions(flow_id, positions), to: NodeCrud
  defdelegate update_node_data(node, data), to: NodeCrud
  defdelegate update_node_data_without_dashboard_broadcast(node, data), to: NodeCrud
  defdelegate edit_node(flow_id, node_id, operation, payload), to: NodeCrud

  defdelegate node_data_and_derivatives_current?(node, data, project_id),
    to: NodeCrud,
    as: :data_and_derivatives_current?

  defdelegate node_data_and_derivatives_current_ids(node_data_pairs, project_id),
    to: NodeCrud,
    as: :data_and_derivatives_current_ids

  defdelegate change_node(node, attrs \\ %{}), to: NodeCrud
  defdelegate delete_node(node), to: NodeCrud
  defdelegate delete_node_without_dashboard_broadcast(node), to: NodeCrud
  defdelegate delete_node_in_transaction_without_dashboard_broadcast(node), to: NodeCrud
  defdelegate restore_node(flow_id, node_id), to: NodeCrud

  # Connections
  defdelegate list_connections(flow_id), to: ConnectionCrud
  defdelegate get_connection(flow_id, connection_id), to: ConnectionCrud
  defdelegate get_connection!(flow_id, connection_id), to: ConnectionCrud
  defdelegate get_connection_by_id!(connection_id), to: ConnectionCrud
  defdelegate create_connection(flow, source_node, target_node, attrs), to: ConnectionCrud
  defdelegate create_connection(flow, attrs), to: ConnectionCrud
  defdelegate create_connection_with_attrs(flow, attrs), to: ConnectionCrud, as: :create_connection
  defdelegate create_connection_without_dashboard_broadcast(flow, attrs), to: ConnectionCrud
  defdelegate update_connection(connection, attrs), to: ConnectionCrud
  defdelegate delete_connection(connection), to: ConnectionCrud
  defdelegate delete_connection_by_id(flow_id, connection_id), to: ConnectionCrud
  defdelegate delete_connection_by_nodes(flow_id, source_node_id, target_node_id), to: ConnectionCrud

  defdelegate delete_connection_by_pins(flow_id, source_node_id, source_pin, target_node_id, target_pin),
    to: ConnectionCrud

  defdelegate delete_connections_among_nodes(flow_id, node_ids), to: ConnectionCrud

  defdelegate delete_connections_among_nodes_without_dashboard_broadcast(flow_id, node_ids),
    to: ConnectionCrud

  defdelegate change_connection(connection, attrs \\ %{}), to: ConnectionCrud
  defdelegate get_outgoing_connections(node_id), to: ConnectionCrud
  defdelegate get_incoming_connections(node_id), to: ConnectionCrud

  # Editor canvas projection
  defdelegate restore_editor_node(flow, node_id), to: NodeRestore
  defdelegate serialize_editor_node(node, project_id), to: CanvasSerializer
  defdelegate serialize_for_canvas(flow, opts \\ []), to: CanvasSerializer
  defdelegate resolve_node_colors(type, data), to: CanvasSerializer
  defdelegate resolve_node_colors(type, data, cache), to: CanvasSerializer

  # Sequences
  defdelegate list_sequences(flow_id), to: SequenceCrud
  defdelegate list_deleted_sequences(flow_id), to: SequenceCrud, as: :list_deleted
  defdelegate get_sequence(flow_id, id), to: SequenceCrud
  defdelegate get_sequence!(flow_id, id), to: SequenceCrud
  defdelegate get_sequence_config(sequence_id), to: SequenceCrud
  defdelegate create_sequence(flow_id, attrs), to: SequenceCrud
  defdelegate update_sequence(sequence, attrs), to: SequenceCrud
  defdelegate delete_sequence(sequence), to: SequenceCrud
  defdelegate restore_sequence(sequence), to: SequenceCrud
  defdelegate wrap_selection_in_sequence(flow, node_ids, attrs \\ %{}), to: SequenceCrud
  defdelegate list_sequence_visual_layers(sequence_id), to: SequenceCrud
  defdelegate get_sequence_visual_layer(sequence_id, id), to: SequenceCrud
  defdelegate create_sequence_visual_layer(sequence_id, attrs), to: SequenceCrud
  defdelegate update_sequence_visual_layer(layer, attrs), to: SequenceCrud
  defdelegate delete_sequence_visual_layer(layer), to: SequenceCrud
  defdelegate list_sequence_tracks(sequence_id), to: SequenceCrud
  defdelegate get_sequence_track(sequence_id, kind), to: SequenceCrud
  defdelegate upsert_sequence_track(sequence_id, kind, attrs), to: SequenceCrud
  defdelegate clear_sequence_track(sequence_id, kind), to: SequenceCrud
end
