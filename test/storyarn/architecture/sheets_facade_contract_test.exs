defmodule Storyarn.Architecture.SheetsFacadeContractTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets

  @public_contract [
    add_avatar: 2,
    add_avatar: 3,
    add_gallery_image: 2,
    add_gallery_images: 2,
    allowed_asset_content_type?: 1,
    batch_load_avatars_by_sheet: 1,
    batch_load_gallery_data: 1,
    batch_load_gallery_data_by_sheet: 1,
    batch_load_table_data: 1,
    block_word_count: 2,
    can_create_named_version?: 2,
    change_block: 1,
    change_block: 2,
    check_stale_flow_node_variable_references: 2,
    check_stale_variable_references: 2,
    clamp_to_constraints: 3,
    count_backlinks: 2,
    count_context_blocks_by_labels: 3,
    count_stale_variable_references: 2,
    count_variable_usage: 1,
    count_versions: 1,
    create_binary_asset: 4,
    create_block: 2,
    create_block_from_snapshot: 2,
    create_column_group: 2,
    create_named_version: 3,
    create_sheet: 2,
    create_sheet: 3,
    create_sheet_in_transaction: 2,
    create_sheet_in_transaction: 3,
    create_table_column: 2,
    create_table_column_from_snapshot: 3,
    create_table_row: 2,
    create_table_row_from_snapshot: 3,
    create_version: 2,
    create_version: 3,
    delete_block: 1,
    delete_sheet: 1,
    delete_sheet: 2,
    delete_sheet_subtree: 1,
    delete_sheet_subtree: 2,
    delete_sheet_subtree_by_id_in_transaction: 3,
    delete_sheet_subtree_in_transaction: 1,
    delete_sheet_subtree_in_transaction: 2,
    delete_table_column: 1,
    delete_table_row: 1,
    delete_target_references: 2,
    delete_version: 1,
    detach_block: 1,
    detect_version_restore_conflicts: 2,
    duplicate_block: 1,
    enrich_table_formulas: 2,
    ensure_version_restore_enabled: 0,
    extract_formula_symbols: 1,
    formula_to_latex: 1,
    formula_to_latex_substituted: 2,
    get_adjacent_version_numbers: 2,
    get_asset: 2,
    get_avatar: 1,
    get_backlinks_with_sources: 3,
    get_block: 1,
    get_block!: 1,
    get_block_in_project: 2,
    get_block_in_project!: 2,
    get_children: 1,
    get_context_sheet: 2,
    get_default_avatar: 1,
    get_descendant_sheet_ids: 1,
    get_first_gallery_image: 1,
    get_gallery_image: 1,
    get_gallery_image_for_sheet: 2,
    get_latest_version: 1,
    get_project: 2,
    get_project_by_slugs: 3,
    get_reference_target: 3,
    get_reference_targets: 2,
    get_sheet: 2,
    get_sheet!: 2,
    get_sheet_blocks_grouped: 1,
    get_sheet_by_shortcut: 2,
    get_sheet_default_image: 1,
    get_sheet_full: 2,
    get_sheet_full!: 2,
    get_sheet_project_id: 1,
    get_sheet_with_ancestors: 2,
    get_sheet_with_descendants: 2,
    get_source_sheet: 1,
    get_table_column: 2,
    get_table_column!: 2,
    get_table_row: 1,
    get_table_row!: 1,
    get_trashed_sheet: 2,
    get_variable_definition: 3,
    get_version: 2,
    has_children?: 1,
    health_severity_rank: 1,
    health_variable_types: 1,
    hide_for_children: 2,
    list_all_sheets: 1,
    list_assets: 1,
    list_assets: 2,
    list_avatars: 1,
    list_blocks: 1,
    list_blocks_for_sheet_ids: 1,
    list_context_blocks: 4,
    list_context_blocks_by_labels: 4,
    list_context_sheets: 3,
    list_dashboard_health_findings: 1,
    list_dashboard_health_findings: 2,
    list_dialogue_audio_lines: 2,
    list_formula_variable_usages: 2,
    list_formula_variable_usages: 3,
    list_gallery_images: 1,
    list_inheritable_blocks: 1,
    list_inheritance_health_issues: 1,
    list_inherited_instances: 1,
    list_leaf_sheets: 1,
    list_project_variables: 1,
    list_reference_options: 1,
    list_scene_appearances: 1,
    list_sheets_brief: 1,
    list_sheets_brief: 2,
    list_sheets_by_ids: 2,
    list_sheets_tree: 1,
    list_sheets_using_asset_as_avatar: 2,
    list_sheets_using_asset_as_banner: 2,
    list_stale_block_reference_source_ids: 2,
    list_stale_regular_node_ids: 1,
    list_stale_table_node_ids: 1,
    list_table_columns: 1,
    list_table_rows: 1,
    list_trashed_sheets: 1,
    list_variable_referenced_sheet_ids: 1,
    list_variable_refs_with_block_info_for_repair: 1,
    list_versions: 1,
    list_versions: 2,
    load_version_snapshot: 1,
    localizable_block_types: 0,
    maybe_create_version: 2,
    maybe_create_version: 3,
    move_block_down: 2,
    move_block_up: 2,
    move_sheet: 2,
    move_sheet: 3,
    move_sheet_to_position: 3,
    number_clamp_and_format: 2,
    number_parse_constraint: 1,
    parse_formula: 1,
    permanently_delete_block: 1,
    permanently_delete_sheet: 1,
    prepare_version_restore: 2,
    prepare_version_restore_conflicts: 2,
    propagate_to_descendants: 2,
    reattach_block: 1,
    record_block_created: 5,
    record_version_compared: 2,
    record_version_panel_opened: 2,
    referenced_block_ids_for_project: 1,
    remove_avatar: 2,
    remove_gallery_image: 2,
    reorder_avatars: 2,
    reorder_blocks: 2,
    reorder_blocks_with_columns: 2,
    reorder_gallery_images: 2,
    reorder_sheets: 3,
    reorder_table_columns: 2,
    reorder_table_rows: 2,
    resolve_block_id_by_variable: 3,
    resolve_inherited_blocks: 1,
    resolve_table_block_id_by_variable: 5,
    resolve_variable_values: 2,
    restore_block: 1,
    restore_enabled?: 0,
    restore_sheet: 1,
    restore_tracked_version: 4,
    restore_version: 2,
    restore_version: 3,
    search_referenceable: 2,
    search_referenceable: 3,
    search_sheets: 2,
    search_sheets: 3,
    search_sheets_deep: 2,
    search_sheets_deep: 3,
    search_sheets_in_projects: 2,
    search_sheets_in_projects: 3,
    search_variable_definitions: 1,
    search_variable_definitions: 2,
    search_variable_definitions: 3,
    search_variable_initial_value_matches: 4,
    search_variable_initial_value_matches: 5,
    serialize_version_snapshot: 1,
    set_avatar_default: 1,
    set_current_version: 2,
    sheet_health_findings: 1,
    sheet_health_snapshot: 1,
    sheet_stats_for_project: 1,
    sheet_word_counts: 1,
    sync_created_sheet_localization: 1,
    trash_sheet: 1,
    unhide_for_children: 2,
    update_avatar: 2,
    update_block: 2,
    update_block_config: 2,
    update_block_value: 2,
    update_dialogue_audio: 4,
    update_gallery_image: 2,
    update_sheet: 2,
    update_table_cell: 3,
    update_table_cells: 2,
    update_table_column: 2,
    update_table_row: 2,
    update_variable_name: 2,
    update_version: 2,
    validate_reference_target: 3,
    variable_predicate_string_aliases: 4
  ]

  @public_types ~w(attrs block changeset id sheet sheet_avatar validation_error)a

  # ENG-103 deliberately removed these former cross-context writers. Keeping a
  # compatibility delegate would continue to present Sheets as an authority
  # over Flow-owned node data and shared reference indexes.
  @retired_cross_context_writers [
    delete_flow_node_references: 1,
    update_flow_node_references: 1,
    update_flow_node_references: 2
  ]

  # Compared against the compiled facade at baseline 350f19cf. The new module
  # description and semantic argument name for get_reference_target/3 are
  # intentional. validate_reference_target/3 now names the stable References
  # contract instead of leaking the deleted Persistence.FlowRecord projection.
  @docs_digest "937fa3a6874138e2d037dfce75f43b31fadd97d56b35231f4ae8e48c22916677"
  @types_digest "2c676b07271b72ecc2543ffd1c3193849a9b4a9a2e6905bf48a3456518a0d345"
  @specs_digest "0fc5c8b7047eab55752c5db414c353ce6e55c341ecc0e0e0f9df19dcada704a5"

  test "the root facade preserves the reviewed public contract and retired writers stay absent" do
    public_functions =
      :functions
      |> Sheets.__info__()
      |> Enum.reject(fn {name, _arity} -> name in [:module_info, :__info__] end)
      |> MapSet.new()

    assert public_functions == MapSet.new(@public_contract)
    assert MapSet.disjoint?(public_functions, MapSet.new(@retired_cross_context_writers))
  end

  test "the root facade remains declarative delegation without business logic" do
    source = File.read!("lib/storyarn/sheets.ex")

    refute Regex.match?(~r/^\s*def(?:p|macro|macrop)?\s/m, source)
    assert length(Regex.scan(~r/^\s*defdelegate\s/m, source)) == 197
  end

  test "the compiled facade preserves docs and semantic default signatures for every arity" do
    assert {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(Sheets)

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
        Enum.map((arity - defaults)..arity, &{name, &1})
      end)
      |> MapSet.new()

    assert length(function_docs) == 197
    assert status_counts == %{documented: 142, hidden: 10, none: 45}
    assert represented_arities == MapSet.new(@public_contract)
    assert digest(Enum.sort(function_docs)) == @docs_digest
  end

  test "the compiled facade preserves the seven stable public types without exposing data projections" do
    assert {:ok, types} = Code.Typespec.fetch_types(Sheets)

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
    assert {:ok, specs} = Code.Typespec.fetch_specs(Sheets)

    normalized_specs =
      specs
      |> Enum.flat_map(fn {{name, arity}, definitions} ->
        Enum.map(definitions, fn definition ->
          quoted = Code.Typespec.spec_to_quoted(name, definition)
          {name, arity, Macro.to_string(quoted)}
        end)
      end)
      |> Enum.sort()

    assert length(normalized_specs) == 54
    assert digest(normalized_specs) == @specs_digest
    refute Enum.any?(normalized_specs, fn {_name, _arity, spec} -> spec =~ ".Data." end)
  end

  test "reference validation exposes a stable structural target type" do
    assert {:ok, types} = Code.Typespec.fetch_types(Storyarn.Sheets.References)

    reference_target =
      Enum.find_value(types, fn
        {:type, {:reference_target, _definition, []} = type} ->
          type |> Code.Typespec.type_to_quoted() |> Macro.to_string()

        _other ->
          nil
      end)

    assert reference_target =~ "Storyarn.Sheets.Sheet.t()"
    assert reference_target =~ ":project_id => integer()"
    refute reference_target =~ ".Data."
  end

  defp digest(term) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end
end
