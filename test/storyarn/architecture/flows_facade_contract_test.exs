defmodule Storyarn.Architecture.FlowsFacadeContractTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows

  @public_contract ~w(
    add_exit_outcome_tag/2
    add_health_flags/3
    analyze_flow_structure/2
    analyze_loaded_flow_structure/1
    analyze_serialized_flow_structure/2
    append_dialogue_response/2
    assign_dialogue_audio/4
    batch_update_positions/2
    broadcast_flow_refreshes/1
    build_player_outcome/2
    build_runtime_variables/1
    build_version_snapshot/1
    can_create_named_version?/2
    capture_sequence_composition/1
    change_connection/1
    change_connection/2
    change_flow/1
    change_flow/2
    change_node/1
    change_node/2
    child_spec/1
    choose_player_response/2
    clear_sequence_track/2
    compose_node_sequences/2
    compose_player_sequences/2
    condition_has_rules?/1
    condition_new/0
    condition_parse/1
    condition_sanitize/1
    condition_to_json/1
    continue_player_session/1
    count_dialogue_lines_by_speaker/1
    count_dialogue_lines_by_speaker/2
    count_flows/1
    count_nodes_by_type/1
    count_nodes_for_project/1
    count_project_nodes_by_type/1
    count_versions/1
    count_versions_since/2
    create_connection/4
    create_connection_with_attrs/2
    create_connection_without_dashboard_broadcast/2
    create_editor_node/4
    create_editor_sequence/4
    create_editor_sequence_visual_layer/4
    create_flow/2
    create_flow/3
    create_flow_in_transaction/2
    create_flow_in_transaction/3
    create_linked_flow/3
    create_linked_flow/4
    create_linked_flow/5
    create_named_version/3
    create_node/2
    create_node_without_dashboard_broadcast/2
    create_sequence/2
    create_sequence_visual_layer/2
    create_version/2
    create_version/3
    debug_active_connection/2
    debug_auto_step/4
    debug_choose_response/3
    debug_select_start_node/3
    debug_session_store/2
    debug_session_take/1
    debug_step/4
    debug_step_back/1
    default_node_data/1
    default_search_limit/0
    delete_connection/1
    delete_connection_by_id/2
    delete_connection_by_nodes/3
    delete_connection_by_pins/5
    delete_connections_among_nodes/2
    delete_connections_among_nodes_without_dashboard_broadcast/2
    delete_flow/1
    delete_flow/2
    delete_flow_subtree/1
    delete_flow_subtree/2
    delete_flow_subtree_by_id_in_transaction/3
    delete_flow_subtree_in_transaction/1
    delete_flow_subtree_in_transaction/2
    delete_node/1
    delete_node_in_transaction_without_dashboard_broadcast/1
    delete_node_without_dashboard_broadcast/1
    delete_sequence/1
    delete_sequence_visual_layer/1
    delete_version/1
    detect_version_restore_conflicts/2
    dialogue_technical_id/3
    duplicate_editor_node/3
    duplicate_node_data/2
    edit_node/4
    editor_node_types/0
    ensure_version_restore_enabled/0
    evaluate_condition/2
    evaluator_add_breakpoint_hit/2
    evaluator_add_console_entry/5
    evaluator_at_breakpoint?/1
    evaluator_choose_response/3
    evaluator_extend_step_limit/1
    evaluator_find_return_connection/3
    evaluator_format_value/1
    evaluator_init/2
    evaluator_pop_flow_context/1
    evaluator_push_flow_context/5
    evaluator_reset/1
    evaluator_set_variable/3
    evaluator_step/3
    evaluator_step_back/1
    evaluator_strip_html/1
    evaluator_strip_html/2
    evaluator_toggle_breakpoint/2
    execute_instructions/2
    exit_mode/1
    exit_technical_id/2
    extend_debug_step_limit/1
    flow_deleted?/1
    flow_health_findings/2
    flow_stats_for_project/1
    flow_word_count/1
    flow_word_counts/1
    follow_dialogue_preview/3
    format_player_value/1
    get_adjacent_version_numbers/2
    get_connection/2
    get_connection!/2
    get_connection_by_id!/1
    get_context_neighborhood/5
    get_context_node/2
    get_editor_scene_name/2
    get_flow/2
    get_flow!/2
    get_flow!/3
    get_flow_brief/2
    get_flow_including_deleted/2
    get_hub_by_hub_id/2
    get_incoming_connections/1
    get_latest_version/1
    get_node/2
    get_node!/2
    get_node_by_id!/2
    get_outgoing_connections/1
    get_preview_speaker_name/2
    get_sequence/2
    get_sequence!/2
    get_sequence_config/1
    get_sequence_track/2
    get_sequence_track_by_key/2
    get_sequence_visual_layer/2
    get_sequence_visual_layer_by_key/2
    get_version/2
    go_back_player_session/1
    hard_delete_flow/1
    has_circular_reference?/2
    health_severity_rank/1
    hub_color_default_hex/0
    initial_asset_options/3
    initial_speaker_options/2
    inspect_node_sequences/2
    instruction_format_short/1
    instruction_has_type_warnings?/2
    instruction_sanitize/1
    interpolate_player_response_text/2
    interpolate_player_rich_text/3
    list_connections/1
    list_context_flows/3
    list_dashboard_health_findings/1
    list_deleted_flows/1
    list_deleted_sequences/1
    list_dialogue_nodes_by_speaker/2
    list_exit_nodes_for_flow/1
    list_export_health_findings/2
    list_export_health_findings/3
    list_flows/1
    list_flows_by_parent/2
    list_flows_tree/1
    list_hubs/1
    list_nodes/1
    list_nodes_referencing_flow/2
    list_outcome_tags_for_project/1
    list_referenceable_variables/1
    list_referencing_jumps/2
    list_runtime_nodes/1
    list_sequence_tracks/1
    list_sequence_visual_layers/1
    list_sequences/1
    list_stale_node_ids/1
    list_subflow_nodes_referencing/2
    list_versions/1
    list_versions/2
    load_editor_catalog/1
    load_player_speakers/1
    load_runtime_graph/1
    load_version_snapshot/1
    localizable_node_types/0
    lock_flow_nodes_for_update/1
    map_player_rich_text_references/2
    maybe_create_version/2
    maybe_create_version/3
    move_flow_to_position/3
    nav_history_clear/1
    nav_history_get/1
    nav_history_put/2
    new_dialogue_id/0
    new_response_id/0
    next_dialogue_response_number/1
    node_data_and_derivatives_current?/3
    node_data_and_derivatives_current_ids/2
    node_form_data/2
    node_label/1
    node_specific_label/1
    node_types/0
    node_word_count/2
    override_sequence_track/3
    override_sequence_visual_layer/3
    player_response_id_by_number/3
    player_session_can_go_back?/1
    player_step_until_interactive/3
    player_step_until_interactive/4
    prepare_version_restore/2
    prepare_version_restore_conflicts/2
    put_annotation_color/2
    put_annotation_font_size/2
    put_dialogue_response_assignments/3
    put_dialogue_response_condition/3
    put_dialogue_response_instruction/3
    put_dialogue_response_text/3
    put_exit_color/2
    put_exit_flow_reference/2
    put_exit_mode/2
    put_exit_target/3
    put_hub_color/2
    put_instruction_assignments/2
    put_node_condition/2
    put_response_condition/3
    put_subflow_reference/2
    recompute_formula_variables/1
    record_player_started/2
    record_version_compared/2
    record_version_panel_opened/2
    remove_dialogue_response/2
    remove_exit_outcome_tag/2
    remove_sequence_track/2
    remove_sequence_visual_layer/2
    repair_stale_variable_references/2
    reorder_flows/3
    reset_debug_session/3
    resolve_hub_color/1
    resolve_legacy_hub_color/1
    resolve_node_colors/2
    resolve_node_colors/3
    resolve_scene_id/1
    resolve_scene_id/2
    restart_player_session/1
    restore_editor_node/2
    restore_enabled?/0
    restore_flow/1
    restore_node/2
    restore_player_session/5
    restore_sequence/1
    restore_sequence_composition/2
    restore_sequence_composition/3
    restore_sequence_track/2
    restore_sequence_visual_layer/2
    restore_tracked_version/4
    restore_version/2
    restore_version/3
    revert_sequence_track_fields/3
    revert_sequence_visual_layer_fields/3
    runtime_entry_node_id/1
    safe_to_integer/1
    search_asset_options/2
    search_asset_options/3
    search_exit_target_scenes/2
    search_exit_target_scenes/3
    search_flows/2
    search_flows/3
    search_flows_deep/2
    search_flows_deep/3
    search_flows_in_projects/2
    search_flows_in_projects/3
    search_mentions/2
    search_speaker_options/2
    search_speaker_options/3
    search_variable_options/1
    search_variable_options/2
    search_variable_suggestions/2
    serialize_editor_node/2
    serialize_for_canvas/1
    serialize_for_canvas/2
    serialize_version_snapshot/1
    set_composition_source/2
    set_current_version/2
    set_debug_variable/3
    set_main_flow/1
    start_debug_session/2
    start_dialogue_preview/2
    start_link/1
    start_player_session/2
    stop_debug_session/0
    toggle_condition_switch_mode/1
    toggle_debug_breakpoint/2
    transact_sequence_composition/2
    translate_same_row_binding/2
    update_connection/2
    update_editor_sequence_visual_layer/5
    update_flow/2
    update_flow_scene/2
    update_node/2
    update_node_data/2
    update_node_data_without_dashboard_broadcast/2
    update_node_parent/2
    update_node_position/2
    update_node_without_dashboard_broadcast/2
    update_sequence/2
    update_sequence_visual_layer/2
    update_version/2
    upsert_editor_sequence_track/5
    upsert_sequence_track/3
    user_addable_node_types/0
    validate_exit_flow_reference/3
    validate_subflow_reference/2
    variable_type_map/1
    version_snapshot_has_changes?/2
    wrap_editor_selection/4
    wrap_selection_in_sequence/2
    wrap_selection_in_sequence/3
  )

  @public_types ~w(attrs changeset connection dialogue_audio_error dialogue_audio_receipt flow flow_node linked_flow_result project_identity sequence variable_reference_repair_error variable_reference_repair_failure)a

  # Frozen immediately before the capability reorganization. These hashes
  # cover semantic signatures, docs/defaults, public types, and specs.
  @docs_digest "e89cab24e24c81ebd22e32a07e1a2156609e69b573dba4aad21c7f2a19ac3ccf"
  @types_digest "185b2bf999eed11bd7b86968d880d33cccdc414a7f9f5b23921412d98bc03805"
  @specs_digest "c01ed8ba241c0ab1a5717cc1ca8f1147a6f0fa96b86bcabf26c07e4fc9937e02"

  test "the root facade preserves every established function and arity" do
    public_functions =
      :functions
      |> Flows.__info__()
      |> Enum.reject(fn {name, _arity} -> name in [:module_info, :__info__] end)
      |> MapSet.new(fn {name, arity} -> "#{name}/#{arity}" end)

    assert public_functions == MapSet.new(@public_contract)
  end

  test "the root facade remains declarative delegation without business logic" do
    source = File.read!("lib/storyarn/flows.ex")

    refute Regex.match?(~r/^\s*def(?:p|macro|macrop)?\s/m, source)
    assert Regex.scan(~r/^\s*defdelegate\s/m, source) != []
    refute source =~ "Storyarn.Repo"
  end

  test "the compiled facade preserves docs and semantic default signatures for every arity" do
    assert {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(Flows)

    function_docs =
      Enum.flat_map(entries, fn
        {{:function, name, arity}, _, signatures, doc, metadata} ->
          [{name, arity, signatures, doc, Map.get(metadata, :defaults, 0)}]

        _other ->
          []
      end)

    status_counts =
      Enum.frequencies_by(function_docs, fn {_name, _arity, _signatures, doc, _defaults} ->
        case doc do
          :hidden -> :hidden
          :none -> :none
          %{} -> :documented
        end
      end)

    represented_arities =
      function_docs
      |> Enum.flat_map(fn {name, arity, _signatures, _doc, defaults} ->
        Enum.map((arity - defaults)..arity, &"#{name}/#{&1}")
      end)
      |> MapSet.new()

    assert length(function_docs) == 306
    assert status_counts == %{documented: 236, hidden: 19, none: 51}
    assert represented_arities == MapSet.new(@public_contract)
    assert digest(Enum.sort(function_docs)) == @docs_digest
  end

  test "the compiled facade preserves its public types without exposing data projections" do
    assert {:ok, types} = Code.Typespec.fetch_types(Flows)

    type_names =
      types
      |> Enum.map(fn {_kind, {name, _definition, _args}} -> name end)
      |> Enum.sort()

    normalized_types =
      types
      |> Enum.map(fn {kind, type} ->
        {kind, type |> Code.Typespec.type_to_quoted() |> Macro.to_string()}
      end)
      |> Enum.sort()

    assert type_names == Enum.sort(@public_types)
    assert digest(normalized_types) == @types_digest
    refute Enum.any?(normalized_types, fn {_kind, type} -> type =~ ".Data." end)
  end

  test "the compiled facade preserves every established public spec" do
    assert {:ok, specs} = Code.Typespec.fetch_specs(Flows)

    normalized_specs =
      specs
      |> Enum.flat_map(fn {{name, arity}, definitions} ->
        Enum.map(definitions, fn definition ->
          quoted = Code.Typespec.spec_to_quoted(name, definition)
          {name, arity, Macro.to_string(quoted)}
        end)
      end)
      |> Enum.sort()

    assert length(normalized_specs) == 96
    assert digest(normalized_specs) == @specs_digest
    refute Enum.any?(normalized_specs, fn {_name, _arity, spec} -> spec =~ ".Data." end)
  end

  defp digest(term) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end
end
