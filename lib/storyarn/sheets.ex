defmodule Storyarn.Sheets do
  @moduledoc "Public facade of the Sheets bounded context.\n\nThe facade composes capability boundaries while keeping commands, queries,\nprojections, rules, execution modules, events, and adapters private. Its\npublic functions, documentation, types, and specs are pinned by architecture\ntests so an internal reorganization cannot silently erode the client contract.\n"
  alias Storyarn.Sheets.Access
  alias Storyarn.Sheets.AI
  alias Storyarn.Sheets.Assets
  alias Storyarn.Sheets.Editor
  alias Storyarn.Sheets.Health
  alias Storyarn.Sheets.Localization
  alias Storyarn.Sheets.Logic
  alias Storyarn.Sheets.References
  alias Storyarn.Sheets.Versioning

  @type sheet :: Storyarn.Sheets.Sheet.t()
  @type block :: Storyarn.Sheets.Block.t()
  @type id :: integer()
  @type changeset :: Ecto.Changeset.t()
  @type attrs :: map()
  @type validation_error ::
          :cannot_be_own_parent
          | :parent_not_found
          | :parent_different_project
          | :would_create_cycle
  @type sheet_avatar :: Storyarn.Sheets.SheetAvatar.t()
  defdelegate add_avatar(sheet, asset_id, attrs \\ %{}), to: Editor
  defdelegate add_gallery_image(block, asset_id), to: Editor
  defdelegate add_gallery_images(block, asset_ids), to: Editor
  @doc "Checks whether a content type is allowed for direct Sheet uploads."
  defdelegate allowed_asset_content_type?(content_type), to: Assets
  defdelegate batch_load_avatars_by_sheet(project_id), to: Editor
  defdelegate batch_load_gallery_data(block_ids), to: Editor
  defdelegate batch_load_gallery_data_by_sheet(project_id), to: Editor
  defdelegate batch_load_table_data(block_ids), to: Editor
  @doc "Computes the player-facing word count for one Sheet block."
  defdelegate block_word_count(type, value), to: Localization, as: :word_count_for_block
  @doc "Returns whether this project can create another named Sheet version."
  defdelegate can_create_named_version?(project_id, workspace_id), to: Versioning
  @doc "Returns a changeset for tracking block changes.\n"
  @spec change_block(block(), attrs()) :: changeset()
  defdelegate change_block(block, attrs \\ %{}), to: Editor
  @doc "Returns stale variable reference data for flow nodes."
  defdelegate check_stale_flow_node_variable_references(block_id, project_id), to: References
  @doc "Lists tracked variable usages and their current staleness for one block."
  defdelegate check_stale_variable_references(block_id, project_id), to: References

  @doc "Clamps a value to its block type constraints.\n\nDispatches to the appropriate constraint module based on `block_type`.\nRich text values pass through unclamped.\n"
  @spec clamp_to_constraints(any(), map() | nil, String.t()) :: any()
  defdelegate clamp_to_constraints(value, constraints, type), to: Logic
  @doc "Counts backlinks for a target.\n"
  @spec count_backlinks(String.t(), id()) :: integer()
  defdelegate count_backlinks(target_type, target_id), to: References
  @doc false
  defdelegate count_context_blocks_by_labels(project_id, sheet_id, labels), to: AI
  @doc "Counts stale tracked variable references for multiple blocks in one query."
  defdelegate count_stale_variable_references(block_ids, project_id), to: References
  @doc "Counts tracked variable usages by kind for one block."
  defdelegate count_variable_usage(block_id), to: References
  @doc "Returns the total number of versions for a sheet.\n"
  defdelegate count_versions(sheet_id), to: Versioning
  @doc "Creates a binary asset through the Sheet-owned asset command."
  defdelegate create_binary_asset(binary, attrs, project, user), to: Assets
  @doc "Creates a new block in a sheet.\n"
  @spec create_block(sheet(), attrs()) :: {:ok, block()} | {:error, changeset()}
  defdelegate create_block(sheet, attrs), to: Editor

  @doc "Recreates a block from a snapshot (for undo/redo).\nRestores soft-deleted block if it exists, otherwise creates new.\n"
  defdelegate create_block_from_snapshot(sheet, snapshot), to: Editor
  @doc "Creates a column group from a list of block IDs.\n"
  @spec create_column_group(id(), [id()]) :: {:ok, Ecto.UUID.t()} | {:error, term()}
  defdelegate create_column_group(sheet_id, block_ids), to: Editor
  @doc "Creates a named Sheet version and emits its Sheet-owned fact."
  defdelegate create_named_version(scope, sheet, opts), to: Versioning
  @doc "Creates a new sheet in a project.\n"
  @spec create_sheet(map(), attrs()) :: {:ok, sheet()} | {:error, changeset()}
  defdelegate create_sheet(project, attrs), to: Editor
  defdelegate create_sheet(actor_scope, project, attrs), to: Editor
  @doc false
  defdelegate create_sheet_in_transaction(project, attrs), to: Editor
  defdelegate create_sheet_in_transaction(actor_scope, project, attrs), to: Editor
  defdelegate create_table_column(block, attrs), to: Editor
  defdelegate create_table_column_from_snapshot(block_id, snapshot, cell_values), to: Editor
  defdelegate create_table_row(block, attrs), to: Editor
  defdelegate create_table_row_from_snapshot(block_id, snapshot, cells), to: Editor
  @doc "Creates a new version snapshot of the given sheet.\n"
  defdelegate create_version(sheet, user_id, opts \\ []), to: Versioning
  @doc "Soft-deletes a block by setting deleted_at timestamp.\n"
  @spec delete_block(block()) :: {:ok, block()} | {:error, changeset()}
  defdelegate delete_block(block), to: Editor
  @doc "Deletes all references from a flow node.\nCalled when a node is deleted.\n"
  @spec delete_flow_node_references(integer()) :: {integer(), nil}
  defdelegate delete_flow_node_references(node_id), to: References
  @doc "Soft deletes a sheet (moves to trash).\nAlso soft deletes all descendant sheets.\n"
  @spec delete_sheet(sheet()) :: {:ok, sheet()} | {:error, term()}
  defdelegate delete_sheet(sheet), to: Editor
  defdelegate delete_sheet(actor_scope, sheet), to: Editor

  @doc "Soft deletes a sheet and its descendants, returning the committed cascade\nids (collected under the delete's own locks).\n"
  @spec delete_sheet_subtree(sheet()) ::
          {:ok, %{entity: sheet(), deleted_ids: [integer()]}} | {:error, term()}
  defdelegate delete_sheet_subtree(sheet), to: Editor
  defdelegate delete_sheet_subtree(actor_scope, sheet), to: Editor
  @doc false
  defdelegate delete_sheet_subtree_by_id_in_transaction(actor_scope, project_id, sheet_id),
    to: Editor

  @doc false
  defdelegate delete_sheet_subtree_in_transaction(sheet), to: Editor
  defdelegate delete_sheet_subtree_in_transaction(actor_scope, sheet), to: Editor
  defdelegate delete_table_column(column), to: Editor
  defdelegate delete_table_row(row), to: Editor

  @doc "Deletes all references where a given entity is the target.\nUsed for permanent deletion cleanup.\n"
  @spec delete_target_references(String.t(), integer()) :: {integer(), nil}
  defdelegate delete_target_references(target_type, target_id), to: References
  @doc "Deletes a version and its snapshot.\n"
  defdelegate delete_version(version), to: Versioning
  @doc "Detaches an inherited block, making it a local copy.\n"
  defdelegate detach_block(block), to: Editor
  @doc "Builds the Sheet-owned restore-conflict preview."
  defdelegate detect_version_restore_conflicts(snapshot, sheet), to: Versioning
  @doc "Duplicates a block, placing the copy immediately after the original.\n"
  defdelegate duplicate_block(block), to: Editor
  @doc "Injects computed formula results (`__result`/`__resolved`) into batched table data."
  defdelegate enrich_table_formulas(table_data, project_id), to: Logic
  @doc "Ensures that Sheet version restore is currently enabled."
  defdelegate ensure_version_restore_enabled(), to: Versioning
  @doc "Extracts symbol names from a parsed formula AST."
  defdelegate extract_formula_symbols(ast), to: Logic
  @doc "Renders a parsed formula AST as LaTeX."
  defdelegate formula_to_latex(ast), to: Logic
  @doc "Renders a parsed formula AST as LaTeX with bound values substituted."
  defdelegate formula_to_latex_substituted(ast, resolved), to: Logic
  @doc "Returns the previous and next stored Sheet version numbers."
  defdelegate get_adjacent_version_numbers(sheet_id, current_number), to: Versioning
  @doc "Gets an asset through the Sheet-owned read projection."
  defdelegate get_asset(project_id, asset_id), to: Assets
  defdelegate get_avatar(id), to: Editor
  @doc "Gets backlinks for a target with resolved source information.\n"
  @spec get_backlinks_with_sources(String.t(), id(), id()) :: [map()]
  defdelegate get_backlinks_with_sources(target_type, target_id, project_id), to: References
  @doc "Gets a single block by ID.\n"
  @spec get_block(id()) :: block() | nil
  defdelegate get_block(block_id), to: Editor
  @doc "Gets a single block by ID.\nRaises `Ecto.NoResultsError` if not found.\n"
  @spec get_block!(id()) :: block()
  defdelegate get_block!(block_id), to: Editor

  @doc "Gets a block by ID, ensuring it belongs to the specified project.\nReturns nil if not found or not in project.\n"
  @spec get_block_in_project(id(), id()) :: block() | nil
  defdelegate get_block_in_project(block_id, project_id), to: Editor
  @doc "Gets a block by ID with project validation. Raises if not found.\n"
  @spec get_block_in_project!(id(), id()) :: block()
  defdelegate get_block_in_project!(block_id, project_id), to: Editor
  @doc "Gets the children of a sheet.\n"
  @spec get_children(id()) :: [sheet()]
  defdelegate get_children(sheet_id), to: Editor
  @doc false
  defdelegate get_context_sheet(project_id, sheet_id), to: AI
  defdelegate get_default_avatar(sheet_id), to: Editor
  @doc "Returns all descendant sheet IDs for a given sheet.\n"
  defdelegate get_descendant_sheet_ids(sheet_id), to: Editor
  defdelegate get_first_gallery_image(sheet_id), to: Editor
  defdelegate get_gallery_image(id), to: Editor
  defdelegate get_gallery_image_for_sheet(sheet_id, id), to: Editor
  @doc "Gets the latest version for a sheet.\n"
  defdelegate get_latest_version(sheet_id), to: Versioning
  @doc "Returns a Sheet-owned project projection after authorization."
  defdelegate get_project(scope, project_id), to: Access
  @doc "Returns a Sheet-owned project projection by workspace and project slugs."
  defdelegate get_project_by_slugs(scope, workspace_slug, project_slug), to: Access
  @doc "Gets the reference target (sheet or flow) for display.\nReturns nil if not found.\n"
  @spec get_reference_target(String.t() | nil, id() | nil, id()) :: map() | nil
  defdelegate get_reference_target(target_type, target_id, project_id), to: References
  @doc "Resolves multiple active sheet and flow targets in batch."
  defdelegate get_reference_targets(references, project_id), to: References

  @doc "Gets a single sheet by ID within a project.\nReturns `nil` if the sheet doesn't exist or doesn't belong to the project.\n"
  @spec get_sheet(id(), id()) :: sheet() | nil
  defdelegate get_sheet(project_id, sheet_id), to: Editor
  @doc "Gets a single sheet by ID within a project.\nRaises `Ecto.NoResultsError` if not found.\n"
  @spec get_sheet!(id(), id()) :: sheet()
  defdelegate get_sheet!(project_id, sheet_id), to: Editor

  @doc "Gets a sheet's blocks split into inherited and own groups.\nReturns `{inherited_groups, own_blocks}`.\n"
  defdelegate get_sheet_blocks_grouped(sheet_id), to: Editor
  @doc "Gets a sheet by its shortcut within a project.\nReturns nil if not found.\n"
  @spec get_sheet_by_shortcut(id(), String.t()) :: sheet() | nil
  defdelegate get_sheet_by_shortcut(project_id, shortcut), to: Editor

  @doc "Returns the default image for a sheet using fallback hierarchy:\ndefault avatar → banner → first gallery image → nil.\n"
  defdelegate get_sheet_default_image(sheet), to: Editor

  @doc "Gets a sheet with all associations preloaded (blocks, assets, current_version).\nReturns nil if not found.\n"
  @spec get_sheet_full(id(), id()) :: sheet() | nil
  defdelegate get_sheet_full(project_id, sheet_id), to: Editor

  @doc "Gets a sheet with all associations preloaded (blocks, assets, current_version).\nRaises if not found.\n"
  @spec get_sheet_full!(id(), id()) :: sheet()
  defdelegate get_sheet_full!(project_id, sheet_id), to: Editor
  @doc "Returns the project_id for a sheet by its ID."
  defdelegate get_sheet_project_id(sheet_id), to: Editor

  @doc "Gets a sheet with all its ancestors for breadcrumb.\nReturns a list starting from the root and ending with the sheet itself.\n"
  @spec get_sheet_with_ancestors(id(), id()) :: [sheet()] | nil
  defdelegate get_sheet_with_ancestors(project_id, sheet_id), to: Editor
  @doc "Gets a sheet with all descendants loaded recursively.\n"
  @spec get_sheet_with_descendants(id(), id()) :: sheet() | nil
  defdelegate get_sheet_with_descendants(project_id, sheet_id), to: Editor
  @doc "Returns the source sheet for an inherited block.\n"
  defdelegate get_source_sheet(block), to: Editor
  defdelegate get_table_column(block_id, id), to: Editor
  defdelegate get_table_column!(block_id, id), to: Editor
  defdelegate get_table_row(id), to: Editor
  defdelegate get_table_row!(id), to: Editor
  @doc "Gets a trashed sheet by ID.\n"
  @spec get_trashed_sheet(id(), id()) :: sheet() | nil
  defdelegate get_trashed_sheet(project_id, sheet_id), to: Editor
  @doc "Resolves one active variable definition inside a project."
  defdelegate get_variable_definition(project_id, block_id, qualified_ref), to: Logic
  @doc "Gets a specific version by sheet_id and version_number.\n"
  defdelegate get_version(sheet_id, version_number), to: Versioning
  @spec has_children?(id()) :: boolean()
  defdelegate has_children?(sheet_id), to: Editor
  @doc "Returns the Sheet-owned health severity ordering."
  defdelegate health_severity_rank(severity), to: Health, as: :severity_rank

  @doc "Returns `%{variable_reference => block_type}` for the project — the vocabulary\nboth health surfaces type-check formula bindings against.\n"
  defdelegate health_variable_types(project_id), to: Health
  @doc "Hides an ancestor block from this sheet's children.\n"
  defdelegate hide_for_children(sheet, ancestor_block_id), to: Editor

  @doc "Lists all sheets for a project.\nUsed for speaker selection in dialogue nodes and canvas rendering.\n"
  @spec list_all_sheets(id()) :: [sheet()]
  defdelegate list_all_sheets(project_id), to: Editor
  @doc "Lists active assets through the Sheet-owned read projection."
  defdelegate list_assets(project_id, opts \\ []), to: Assets
  defdelegate list_avatars(sheet_id), to: Editor
  @doc "Lists all blocks for a sheet, ordered by position.\n"
  @spec list_blocks(id()) :: [block()]
  defdelegate list_blocks(sheet_id), to: Editor
  @doc "Lists all non-deleted blocks for the given sheet IDs."
  defdelegate list_blocks_for_sheet_ids(sheet_ids), to: Editor
  @doc false
  defdelegate list_context_blocks(project_id, sheet_id, block_ids, limit), to: AI
  @doc false
  defdelegate list_context_blocks_by_labels(project_id, sheet_id, labels, limit), to: AI
  @doc false
  defdelegate list_context_sheets(project_id, sheet_ids, limit), to: AI
  @doc "Returns the canonical sheet health findings used by the project dashboard overview."
  defdelegate list_dashboard_health_findings(project_id, referenced_ids \\ nil), to: Health
  @doc "Lists dialogue lines spoken by a Sheet for its audio workspace."
  defdelegate list_dialogue_audio_lines(project_id, sheet_id), to: Editor
  @doc "Lists bounded formula cells that read one qualified variable reference."
  defdelegate list_formula_variable_usages(project_id, qualified_ref, opts \\ []), to: Logic
  defdelegate list_gallery_images(block_id), to: Editor
  @doc "Lists all blocks with `scope: \"children\"` for a sheet.\n"
  defdelegate list_inheritable_blocks(sheet_id), to: Editor
  @doc "Lists non-mutating inheritance integrity findings for a sheet.\n"
  defdelegate list_inheritance_health_issues(sheet_id), to: Editor
  @doc "Lists all inherited instance blocks for a parent block.\n"
  defdelegate list_inherited_instances(parent_block_id), to: Editor
  @doc "Lists all leaf sheets (sheets with no children) for a project.\n"
  @spec list_leaf_sheets(id()) :: [sheet()]
  defdelegate list_leaf_sheets(project_id), to: Editor

  @doc "Lists all variables (blocks that can be variables) across all sheets in a project.\nUsed for the condition builder to list available variables.\n"
  @spec list_project_variables(id()) :: [map()]
  defdelegate list_project_variables(project_id), to: Logic

  @doc ~s{Returns project sheets as options for reference columns.\nEach option has `"key"` (shortcut) and `"value"` (name).\n}
  @spec list_reference_options(id()) :: [map()]
  defdelegate list_reference_options(project_id), to: Logic
  @doc "Lists Scene-owned placements that display a Sheet."
  defdelegate list_scene_appearances(sheet_id), to: References

  @doc "Lists brief sheet data (id, name, shortcut) for validator. Opts: [filter_ids: :all | [ids]]."
  defdelegate list_sheets_brief(project_id, opts \\ []), to: Editor

  @doc "Lists sheets by IDs with avatar and banner preloaded.\nUsed by the version viewer for speaker data in flow snapshots.\n"
  @spec list_sheets_by_ids(id(), [id()]) :: [sheet()]
  defdelegate list_sheets_by_ids(project_id, ids), to: Editor

  @doc "Lists all sheets for a project as a tree structure.\nReturns root sheets (no parent) with children preloaded recursively.\n"
  @spec list_sheets_tree(id()) :: [sheet()]
  defdelegate list_sheets_tree(project_id), to: Editor
  @doc "Lists sheets using a specific asset as their avatar."
  defdelegate list_sheets_using_asset_as_avatar(project_id, asset_id), to: References
  @doc "Lists sheets using a specific asset as their banner."
  defdelegate list_sheets_using_asset_as_banner(project_id, asset_id), to: References
  @doc "Returns block IDs with stale tracked sheet/flow entity references."
  defdelegate list_stale_block_reference_source_ids(project_id, block_ids), to: References
  @doc "Lists stale regular (non-table) node IDs in one flow."
  defdelegate list_stale_regular_node_ids(flow_id), to: References
  @doc "Lists stale table node IDs in one flow."
  defdelegate list_stale_table_node_ids(flow_id), to: References
  defdelegate list_table_columns(block_id), to: Editor
  defdelegate list_table_rows(block_id), to: Editor
  @doc "Lists all trashed (soft-deleted) sheets for a project.\n"
  @spec list_trashed_sheets(id()) :: [sheet()]
  defdelegate list_trashed_sheets(project_id), to: Editor
  @doc "Lists sheet IDs referenced through variable_references in a project."
  defdelegate list_variable_referenced_sheet_ids(project_id), to: References
  @doc "Returns variable references with current block info for stale repair."
  defdelegate list_variable_refs_with_block_info_for_repair(project_id), to: References
  @doc "Lists all versions for a sheet, ordered by version number descending.\n"
  defdelegate list_versions(sheet_id, opts \\ []), to: Versioning
  @doc false
  defdelegate load_version_snapshot(version), to: Versioning
  @doc "Returns the block types that contribute player-facing runtime text."
  defdelegate localizable_block_types(), to: Localization
  @doc "Creates a version if enough time has passed since the last version.\n"
  defdelegate maybe_create_version(sheet, user_id, opts \\ []), to: Versioning
  @doc "Moves a block down by swapping with the next block.\n"
  defdelegate move_block_down(block_id, sheet_id), to: Editor
  @doc "Moves a block up by swapping with the previous block.\n"
  defdelegate move_block_up(block_id, sheet_id), to: Editor
  @doc "Moves a sheet to a new parent.\nReturns `{:ok, sheet}` or `{:error, reason}`.\n"
  @spec move_sheet(sheet(), id() | nil, integer() | nil) ::
          {:ok, sheet()} | {:error, validation_error() | changeset()}
  defdelegate move_sheet(sheet, parent_id, position \\ nil), to: Editor
  @doc "Moves a sheet to a new parent at a specific position, reordering siblings as needed.\n"
  @spec move_sheet_to_position(sheet(), id() | nil, integer()) ::
          {:ok, sheet()} | {:error, validation_error() | term()}
  defdelegate move_sheet_to_position(sheet, new_parent_id, new_position), to: Editor
  @doc "Parses a string value, clamps to min/max constraints, and formats back to string.\n"
  defdelegate number_clamp_and_format(value, config), to: Logic
  @doc "Parses a constraint value (from form params or config) into a number or nil.\n"
  defdelegate number_parse_constraint(value), to: Logic
  @doc "Parses a table formula expression into an AST."
  defdelegate parse_formula(expression), to: Logic
  @doc "Permanently deletes a block from the database.\n"
  @spec permanently_delete_block(block()) :: {:ok, block()} | {:error, changeset()}
  defdelegate permanently_delete_block(block), to: Editor

  @doc "Permanently deletes a sheet and all its descendants.\nUse with caution - this cannot be undone.\n"
  @spec permanently_delete_sheet(sheet()) :: {:ok, sheet()} | {:error, changeset()}
  defdelegate permanently_delete_sheet(sheet), to: Editor
  @doc "Decides whether restore must first warn about unsaved changes."
  defdelegate prepare_version_restore(sheet, version), to: Versioning
  @doc "Loads a target Sheet version and builds its restore conflict report."
  defdelegate prepare_version_restore_conflicts(sheet, version), to: Versioning
  @doc "Propagates an inheritable block to selected descendant sheets.\n"
  defdelegate propagate_to_descendants(parent_block, selected_sheet_ids), to: Editor
  @doc "Re-attaches a previously detached block.\n"
  defdelegate reattach_block(block), to: Editor
  @doc "Publishes the product fact for a block created inside a Sheet."
  defdelegate record_block_created(scope, sheet, block, creation_method, block_scope), to: Editor
  @doc "Emits the typed Sheet fact that a version comparison was opened."
  defdelegate record_version_compared(scope, sheet), to: Versioning
  @doc "Emits the typed Sheet fact that the version panel was opened."
  defdelegate record_version_panel_opened(scope, sheet), to: Versioning
  @doc "Returns MapSet of block IDs with at least one variable reference."
  defdelegate referenced_block_ids_for_project(project_id), to: Health
  defdelegate remove_avatar(sheet_id, avatar_id), to: Editor
  defdelegate remove_gallery_image(sheet_id, gallery_image_id), to: Editor
  defdelegate reorder_avatars(sheet_id, ordered_ids), to: Editor
  @doc "Reorders blocks within a sheet.\nTakes a list of block IDs in the desired order.\n"
  @spec reorder_blocks(id(), [id()]) :: {:ok, [block()]} | {:error, term()}
  defdelegate reorder_blocks(sheet_id, block_ids), to: Editor

  @doc "Reorders blocks with column layout information.\nEach item in the list contains id, column_group_id, and column_index.\n"
  @spec reorder_blocks_with_columns(id(), [map()]) :: {:ok, [block()]} | {:error, term()}
  defdelegate reorder_blocks_with_columns(sheet_id, items), to: Editor
  defdelegate reorder_gallery_images(block_id, ordered_ids), to: Editor
  @doc "Reorders sheets within a parent container.\n"
  @spec reorder_sheets(id(), id() | nil, [id()]) :: {:ok, [sheet()]} | {:error, term()}
  defdelegate reorder_sheets(project_id, parent_id, sheet_ids), to: Editor
  defdelegate reorder_table_columns(block_id, ids), to: Editor
  defdelegate reorder_table_rows(block_id, ids), to: Editor
  @doc "Resolves a block ID by sheet shortcut and variable name."
  defdelegate resolve_block_id_by_variable(project_id, sheet_shortcut, variable_name),
    to: References

  @doc "Returns inherited blocks for a sheet, grouped by source sheet.\n"
  defdelegate resolve_inherited_blocks(sheet_id), to: Editor
  @doc "Resolves a table block ID by sheet shortcut, table name, row slug, and column slug."
  defdelegate resolve_table_block_id_by_variable(
                project_id,
                sheet_shortcut,
                table_name,
                row_slug,
                column_slug
              ),
              to: References

  @doc "Resolves current default values for a list of variable references.\nReturns `%{\"ref\" => value}` for each found variable.\n"
  @spec resolve_variable_values(id(), [String.t()]) :: map()
  defdelegate resolve_variable_values(project_id, refs), to: Logic
  @doc "Restores a soft-deleted block.\n"
  @spec restore_block(block()) :: {:ok, block()} | {:error, changeset()}
  defdelegate restore_block(block), to: Editor
  @doc "Returns whether in-place Sheet version restore is enabled."
  defdelegate restore_enabled?(), to: Versioning

  @doc "Restores a soft-deleted sheet from trash.\nNote: Does not automatically restore descendants.\n"
  @spec restore_sheet(sheet()) :: {:ok, sheet()} | {:error, changeset()}
  defdelegate restore_sheet(sheet), to: Editor
  @doc "Restores a Sheet version and emits its Sheet-owned fact on success."
  defdelegate restore_tracked_version(scope, sheet, version, opts), to: Versioning
  @doc "Restores a sheet to a specific version.\n"
  defdelegate restore_version(sheet, version, opts \\ []), to: Versioning

  @doc "Searches for sheets and flows that can be referenced.\n\nReturns a list of maps with :type, :id, :name, :shortcut keys.\n"
  @spec search_referenceable(id(), String.t(), [String.t()]) :: [map()]
  defdelegate search_referenceable(project_id, query, allowed_types \\ ["sheet", "flow"]),
    to: References

  @doc "Searches sheets by name/shortcut with pagination. Options: :limit, :offset."
  defdelegate search_sheets(project_id, query, opts \\ []), to: Editor
  @doc "Searches sheet metadata and authored block, table, and gallery content."
  @spec search_sheets_deep(id(), String.t(), keyword()) :: [sheet()]
  defdelegate search_sheets_deep(project_id, query, opts \\ []), to: Editor

  @doc "Cross-project sheet search over a pre-authorized project set (see `Storyarn.Platform.GlobalSearch`)."
  @spec search_sheets_in_projects([integer()], String.t(), keyword()) :: [sheet()]
  defdelegate search_sheets_in_projects(project_ids, query, opts \\ []), to: Editor
  @doc "Searches bounded variable definitions for an authorized project search."
  defdelegate search_variable_definitions(project_id, filter \\ :all, opts \\ []), to: Logic
  @doc "Searches authored variable initial values after applying a typed predicate."
  defdelegate search_variable_initial_value_matches(
                project_id,
                filter,
                operator,
                literal,
                opts \\ []
              ),
              to: Logic

  @doc "Serializes a stored Sheet snapshot into the read-only viewer block list."
  defdelegate serialize_version_snapshot(snapshot), to: Versioning
  defdelegate set_avatar_default(avatar), to: Editor
  @doc "Sets the current version for a sheet.\n"
  defdelegate set_current_version(sheet, version_or_nil), to: Versioning

  @doc "Returns the canonical health findings for the one sheet open in the editor.\n\nThe Sheets counterpart to the Scene and Flow entity health readers,\nand the same composition point `list_dashboard_health_findings/2` enters: the\neditor and the dashboard cannot feed the checker differently for the same sheet.\n\nExpects the material the editor already holds — `:sheet`, `:project`, `:blocks`,\n`:inherited_groups`, `:table_data`, `:gallery_data`.\n"
  defdelegate sheet_health_findings(material), to: Health
  @doc "Returns the checker-ready snapshot behind `sheet_health_findings/1`."
  defdelegate sheet_health_snapshot(material), to: Health

  @doc "Returns per-sheet block and variable counts. %{sheet_id => %{block_count, variable_count}}."
  defdelegate sheet_stats_for_project(project_id), to: Health

  @doc "Returns per-sheet localizable word counts from runtime sheet fields. %{sheet_id => word_count}."
  defdelegate sheet_word_counts(project_id), to: Health
  @doc false
  defdelegate sync_created_sheet_localization(sheet), to: Editor

  @doc "Soft deletes a sheet and all its descendants (moves to trash).\nAlias for `delete_sheet/1`.\n"
  @spec trash_sheet(sheet()) :: {:ok, sheet()} | {:error, term()}
  defdelegate trash_sheet(sheet), to: Editor
  @doc "Unhides an ancestor block for this sheet's children.\n"
  defdelegate unhide_for_children(sheet, ancestor_block_id), to: Editor
  defdelegate update_avatar(avatar, attrs), to: Editor
  @doc "Updates a block.\n"
  @spec update_block(block(), attrs()) :: {:ok, block()} | {:error, changeset()}
  defdelegate update_block(block, attrs), to: Editor
  @doc "Updates only the config of a block.\n"
  @spec update_block_config(block(), map()) :: {:ok, block()} | {:error, changeset()}
  defdelegate update_block_config(block, config), to: Editor
  @doc "Updates only the value of a block.\n"
  @spec update_block_value(block(), map()) :: {:ok, block()} | {:error, changeset()}
  defdelegate update_block_value(block, value), to: Editor
  @doc "Updates the audio asset assigned to one dialogue line spoken by a Sheet."
  defdelegate update_dialogue_audio(project_id, sheet_id, node_id, audio_asset_id), to: Editor

  @doc "Updates references from a flow node.\nCalled after node data is saved to track mentions and references.\n"
  @spec update_flow_node_references(map(), keyword()) :: :ok | {:error, term()}
  defdelegate update_flow_node_references(node, opts \\ []), to: References
  defdelegate update_gallery_image(gallery_image, attrs), to: Editor
  @doc "Updates a sheet.\n"
  @spec update_sheet(sheet(), attrs()) :: {:ok, sheet()} | {:error, changeset()}
  defdelegate update_sheet(sheet, attrs), to: Editor
  defdelegate update_table_cell(row, column_slug, value), to: Editor
  defdelegate update_table_cells(row, cells_map), to: Editor
  defdelegate update_table_column(column, attrs), to: Editor
  defdelegate update_table_row(row, attrs), to: Editor
  @doc "Updates a block's variable_name directly (user-initiated rename).\n"
  @spec update_variable_name(block(), String.t()) :: {:ok, block()} | {:error, changeset()}
  defdelegate update_variable_name(block, variable_name), to: Editor
  @doc "Updates the name and description of a Sheet version."
  defdelegate update_version(version, attrs), to: Versioning

  @doc "Validates that a reference target exists and belongs to the project.\nReturns {:ok, target} or {:error, reason}.\n"
  @spec validate_reference_target(String.t(), id(), id()) ::
          {:ok, References.reference_target()} | {:error, :not_found | :invalid_type}
  defdelegate validate_reference_target(target_type, target_id, project_id), to: References
  @doc "Resolves normalized predicate aliases without exposing field configuration."
  defdelegate variable_predicate_string_aliases(project_id, definition, operator, literal),
    to: Logic
end
