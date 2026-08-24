defmodule Storyarn.Sheets do
  @moduledoc """
  The Sheets context.

  Manages sheets (tree nodes) and blocks (dynamic content fields) within a project.
  Sheets form a free hierarchy tree, and each sheet can contain multiple blocks.

  This module serves as a facade, delegating to specialized submodules:
  - `SheetCrud` - CRUD operations for sheets
  - `BlockCrud` - CRUD operations for blocks
  - `TreeOperations` - Tree reordering and movement operations
  """

  import Ecto.Query, warn: false

  alias Storyarn.Collaboration
  alias Storyarn.Repo
  alias Storyarn.Sheets.AssetCatalog
  alias Storyarn.Sheets.AssetCommands
  alias Storyarn.Sheets.AvatarCrud
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockCrud
  alias Storyarn.Sheets.Constraints.Number
  alias Storyarn.Sheets.ContextQueries
  alias Storyarn.Sheets.DialogueAudio
  alias Storyarn.Sheets.Events
  alias Storyarn.Sheets.FormulaEngine
  alias Storyarn.Sheets.FormulaResolver
  alias Storyarn.Sheets.GalleryCrud
  alias Storyarn.Sheets.HealthSnapshots
  alias Storyarn.Sheets.Limits
  alias Storyarn.Sheets.LocalizationProjection, as: Localization
  alias Storyarn.Sheets.Persistence.FlowRecord
  alias Storyarn.Sheets.Persistence.ProjectRecord
  alias Storyarn.Sheets.ProjectAccess
  alias Storyarn.Sheets.PropertyInheritance
  alias Storyarn.Sheets.ReferenceTracker
  alias Storyarn.Sheets.SceneReadModel
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Sheets.SheetCrud
  alias Storyarn.Sheets.SheetQueries
  alias Storyarn.Sheets.SheetStats
  alias Storyarn.Sheets.TableCrud
  alias Storyarn.Sheets.TrackedCommands
  alias Storyarn.Sheets.TreeOperations
  alias Storyarn.Sheets.VariableCatalog
  alias Storyarn.Sheets.VariableUsage
  alias Storyarn.Sheets.Versioning
  alias Storyarn.Sheets.Versioning.SnapshotViewer
  alias Storyarn.Sheets.WordCount

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type sheet :: Sheet.t()
  @type block :: Block.t()
  @type id :: integer()
  @type changeset :: Ecto.Changeset.t()
  @type attrs :: map()

  @type validation_error ::
          :cannot_be_own_parent
          | :parent_not_found
          | :parent_different_project
          | :would_create_cycle

  @doc "Lists dialogue lines spoken by a Sheet for its audio workspace."
  defdelegate list_dialogue_audio_lines(project_id, sheet_id), to: DialogueAudio, as: :list_lines

  @doc "Updates the audio asset assigned to one dialogue line spoken by a Sheet."
  defdelegate update_dialogue_audio(project_id, sheet_id, node_id, audio_asset_id),
    to: DialogueAudio,
    as: :update_audio

  # =============================================================================
  # Sheets - Tree Operations
  # =============================================================================

  @doc """
  Lists all sheets for a project as a tree structure.
  Returns root sheets (no parent) with children preloaded recursively.
  """
  @spec list_sheets_tree(id()) :: [sheet()]
  defdelegate list_sheets_tree(project_id), to: SheetQueries

  @doc "Searches sheets by name/shortcut with pagination. Options: :limit, :offset."
  defdelegate search_sheets(project_id, query, opts \\ []), to: SheetQueries

  @doc "Searches sheet metadata and authored block, table, and gallery content."
  @spec search_sheets_deep(id(), String.t(), keyword()) :: [sheet()]
  defdelegate search_sheets_deep(project_id, query, opts \\ []), to: SheetQueries

  @doc "Cross-project sheet search over a pre-authorized project set (see `Storyarn.GlobalSearch`)."
  @spec search_sheets_in_projects([integer()], String.t(), keyword()) :: [sheet()]
  defdelegate search_sheets_in_projects(project_ids, query, opts \\ []), to: SheetQueries

  @doc """
  Gets a single sheet by ID within a project.
  Returns `nil` if the sheet doesn't exist or doesn't belong to the project.
  """
  @spec get_sheet(id(), id()) :: sheet() | nil
  defdelegate get_sheet(project_id, sheet_id), to: SheetQueries

  @doc false
  defdelegate get_context_sheet(project_id, sheet_id), to: ContextQueries, as: :get_sheet_brief

  @doc false
  defdelegate list_context_sheets(project_id, sheet_ids, limit),
    to: ContextQueries,
    as: :list_sheet_briefs

  @doc false
  defdelegate list_context_blocks(project_id, sheet_id, block_ids, limit),
    to: ContextQueries,
    as: :list_blocks

  @doc false
  defdelegate list_context_blocks_by_labels(project_id, sheet_id, labels, limit),
    to: ContextQueries,
    as: :list_blocks_by_labels

  @doc false
  defdelegate count_context_blocks_by_labels(project_id, sheet_id, labels),
    to: ContextQueries,
    as: :count_blocks_by_labels

  @doc """
  Gets a single sheet by ID within a project.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_sheet!(id(), id()) :: sheet()
  defdelegate get_sheet!(project_id, sheet_id), to: SheetQueries

  @doc """
  Gets a sheet with all associations preloaded (blocks, assets, current_version).
  Returns nil if not found.
  """
  @spec get_sheet_full(id(), id()) :: sheet() | nil
  defdelegate get_sheet_full(project_id, sheet_id), to: SheetQueries

  @doc """
  Gets a sheet with all associations preloaded (blocks, assets, current_version).
  Raises if not found.
  """
  @spec get_sheet_full!(id(), id()) :: sheet()
  defdelegate get_sheet_full!(project_id, sheet_id), to: SheetQueries

  @doc """
  Gets a sheet with all its ancestors for breadcrumb.
  Returns a list starting from the root and ending with the sheet itself.
  """
  @spec get_sheet_with_ancestors(id(), id()) :: [sheet()] | nil
  defdelegate get_sheet_with_ancestors(project_id, sheet_id), to: SheetQueries

  @doc """
  Gets a sheet with all descendants loaded recursively.
  """
  @spec get_sheet_with_descendants(id(), id()) :: sheet() | nil
  defdelegate get_sheet_with_descendants(project_id, sheet_id), to: SheetQueries

  @doc """
  Gets the children of a sheet.
  """
  @spec get_children(id()) :: [sheet()]
  defdelegate get_children(sheet_id), to: SheetQueries

  @spec has_children?(id()) :: boolean()
  defdelegate has_children?(sheet_id), to: SheetQueries

  @doc """
  Lists sheets by IDs with avatar and banner preloaded.
  Used by the version viewer for speaker data in flow snapshots.
  """
  @spec list_sheets_by_ids(id(), [id()]) :: [sheet()]
  defdelegate list_sheets_by_ids(project_id, ids), to: SheetQueries

  @doc """
  Lists all sheets for a project.
  Used for speaker selection in dialogue nodes and canvas rendering.
  """
  @spec list_all_sheets(id()) :: [sheet()]
  defdelegate list_all_sheets(project_id), to: SheetQueries

  @doc """
  Lists all leaf sheets (sheets with no children) for a project.
  """
  @spec list_leaf_sheets(id()) :: [sheet()]
  defdelegate list_leaf_sheets(project_id), to: SheetQueries

  @doc """
  Gets a sheet by its shortcut within a project.
  Returns nil if not found.
  """
  @spec get_sheet_by_shortcut(id(), String.t()) :: sheet() | nil
  defdelegate get_sheet_by_shortcut(project_id, shortcut), to: SheetQueries

  @doc """
  Lists all variables (blocks that can be variables) across all sheets in a project.
  Used for the condition builder to list available variables.
  """
  @spec list_project_variables(id()) :: [map()]
  defdelegate list_project_variables(project_id), to: SheetQueries

  @doc "Searches bounded variable definitions for an authorized project search."
  defdelegate search_variable_definitions(project_id, filter \\ :all, opts \\ []),
    to: VariableCatalog,
    as: :list_definitions

  @doc "Searches authored variable initial values after applying a typed predicate."
  defdelegate search_variable_initial_value_matches(project_id, filter, operator, literal, opts \\ []),
    to: VariableCatalog,
    as: :list_initial_value_matches

  @doc "Resolves one active variable definition inside a project."
  defdelegate get_variable_definition(project_id, block_id, qualified_ref),
    to: VariableCatalog,
    as: :get_definition

  @doc "Resolves normalized predicate aliases without exposing field configuration."
  defdelegate variable_predicate_string_aliases(project_id, definition, operator, literal),
    to: VariableCatalog,
    as: :predicate_string_aliases

  @doc "Lists bounded formula cells that read one qualified variable reference."
  defdelegate list_formula_variable_usages(project_id, qualified_ref, opts \\ []),
    to: VariableCatalog,
    as: :list_formula_usages

  @doc """
  Resolves current default values for a list of variable references.
  Returns `%{"ref" => value}` for each found variable.
  """
  @spec resolve_variable_values(id(), [String.t()]) :: map()
  defdelegate resolve_variable_values(project_id, refs), to: SheetQueries

  @doc """
  Returns project sheets as options for reference columns.
  Each option has `"key"` (shortcut) and `"value"` (name).
  """
  @spec list_reference_options(id()) :: [map()]
  defdelegate list_reference_options(project_id), to: SheetQueries

  # =============================================================================
  # Sheets - CRUD Operations
  # =============================================================================

  @doc """
  Creates a new sheet in a project.
  """
  @spec create_sheet(map(), attrs()) :: {:ok, sheet()} | {:error, changeset()}
  defdelegate create_sheet(project, attrs), to: SheetCrud
  defdelegate create_sheet(actor_scope, project, attrs), to: SheetCrud

  @doc false
  defdelegate create_sheet_in_transaction(project, attrs), to: SheetCrud
  defdelegate create_sheet_in_transaction(actor_scope, project, attrs), to: SheetCrud

  @doc false
  defdelegate sync_created_sheet_localization(sheet), to: SheetCrud

  @doc """
  Updates a sheet.
  """
  @spec update_sheet(sheet(), attrs()) :: {:ok, sheet()} | {:error, changeset()}
  defdelegate update_sheet(sheet, attrs), to: SheetCrud

  @doc """
  Soft deletes a sheet (moves to trash).
  Also soft deletes all descendant sheets.
  """
  @spec delete_sheet(sheet()) :: {:ok, sheet()} | {:error, term()}
  defdelegate delete_sheet(sheet), to: SheetCrud
  defdelegate delete_sheet(actor_scope, sheet), to: SheetCrud

  @doc """
  Soft deletes a sheet and its descendants, returning the committed cascade
  ids (collected under the delete's own locks).
  """
  @spec delete_sheet_subtree(sheet()) ::
          {:ok, %{entity: sheet(), deleted_ids: [integer()]}} | {:error, term()}
  defdelegate delete_sheet_subtree(sheet), to: SheetCrud

  @doc false
  defdelegate delete_sheet_subtree_by_id_in_transaction(actor_scope, project_id, sheet_id),
    to: SheetCrud

  defdelegate delete_sheet_subtree(actor_scope, sheet), to: SheetCrud

  @doc false
  defdelegate delete_sheet_subtree_in_transaction(sheet), to: SheetCrud
  defdelegate delete_sheet_subtree_in_transaction(actor_scope, sheet), to: SheetCrud

  @doc """
  Soft deletes a sheet and all its descendants (moves to trash).
  Alias for `delete_sheet/1`.
  """
  @spec trash_sheet(sheet()) :: {:ok, sheet()} | {:error, term()}
  defdelegate trash_sheet(sheet), to: SheetCrud

  @doc """
  Restores a soft-deleted sheet from trash.
  Note: Does not automatically restore descendants.
  """
  @spec restore_sheet(sheet()) :: {:ok, sheet()} | {:error, changeset()}
  defdelegate restore_sheet(sheet), to: SheetCrud

  @doc """
  Permanently deletes a sheet and all its descendants.
  Use with caution - this cannot be undone.
  """
  @spec permanently_delete_sheet(sheet()) :: {:ok, sheet()} | {:error, changeset()}
  defdelegate permanently_delete_sheet(sheet), to: SheetCrud

  @doc """
  Lists all trashed (soft-deleted) sheets for a project.
  """
  @spec list_trashed_sheets(id()) :: [sheet()]
  defdelegate list_trashed_sheets(project_id), to: SheetQueries

  @doc """
  Gets a trashed sheet by ID.
  """
  @spec get_trashed_sheet(id(), id()) :: sheet() | nil
  defdelegate get_trashed_sheet(project_id, sheet_id), to: SheetQueries

  @doc """
  Moves a sheet to a new parent.
  Returns `{:ok, sheet}` or `{:error, reason}`.
  """
  @spec move_sheet(sheet(), id() | nil, integer() | nil) ::
          {:ok, sheet()} | {:error, validation_error() | changeset()}
  defdelegate move_sheet(sheet, parent_id, position \\ nil), to: SheetCrud

  # =============================================================================
  # Sheets - Reordering
  # =============================================================================

  @doc """
  Reorders sheets within a parent container.
  """
  @spec reorder_sheets(id(), id() | nil, [id()]) :: {:ok, [sheet()]} | {:error, term()}
  defdelegate reorder_sheets(project_id, parent_id, sheet_ids), to: TreeOperations

  @doc """
  Moves a sheet to a new parent at a specific position, reordering siblings as needed.
  """
  @spec move_sheet_to_position(sheet(), id() | nil, integer()) ::
          {:ok, sheet()} | {:error, validation_error() | term()}
  def move_sheet_to_position(%Sheet{} = sheet, new_parent_id, new_position) do
    fn ->
      case Repo.one(
             from(project in ProjectRecord,
               where: project.id == ^sheet.project_id,
               lock: "FOR UPDATE"
             )
           ) do
        %ProjectRecord{deleted_at: nil} -> :ok
        %ProjectRecord{} -> Repo.rollback(:project_not_active)
        nil -> Repo.rollback(:project_not_found)
      end

      current_sheet =
        Repo.one(
          from(current in Sheet,
            where:
              current.id == ^sheet.id and
                current.project_id == ^sheet.project_id and
                is_nil(current.deleted_at),
            lock: "FOR UPDATE"
          )
        ) || Repo.rollback(:sheet_not_active)

      move_sheet_to_position_transaction(
        current_sheet,
        new_parent_id,
        new_position
      )
    end
    |> Repo.transaction()
    |> Collaboration.broadcast_dashboard_result(sheet.project_id, :sheets)
  end

  defp move_sheet_to_position_transaction(sheet, new_parent_id, new_position) do
    with {:ok, moved_sheet} <-
           TreeOperations.move_sheet_to_position(sheet, new_parent_id, new_position),
         {:ok, %{sheet_ids: affected_sheet_ids}} <-
           PropertyInheritance.recalculate_on_move_with_sheet_ids(moved_sheet),
         :ok <- Localization.extract_sheet_blocks_for_sheets(affected_sheet_ids) do
      moved_sheet
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # =============================================================================
  # Property Inheritance
  # =============================================================================

  @doc """
  Returns inherited blocks for a sheet, grouped by source sheet.
  """
  defdelegate resolve_inherited_blocks(sheet_id), to: PropertyInheritance

  @doc """
  Lists non-mutating inheritance integrity findings for a sheet.
  """
  defdelegate list_inheritance_health_issues(sheet_id), to: PropertyInheritance, as: :list_health_issues

  @doc """
  Gets a sheet's blocks split into inherited and own groups.
  Returns `{inherited_groups, own_blocks}`.
  """
  defdelegate get_sheet_blocks_grouped(sheet_id), to: SheetQueries

  @doc """
  Propagates an inheritable block to selected descendant sheets.
  """
  def propagate_to_descendants(%Block{} = parent_block, selected_sheet_ids) do
    fn ->
      {:ok, count} = PropertyInheritance.propagate_to_descendants(parent_block, selected_sheet_ids)

      case Localization.extract_block_tree(parent_block.id) do
        :ok -> count
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_block_dashboard_result(parent_block)
  end

  @doc """
  Detaches an inherited block, making it a local copy.
  """
  def detach_block(%Block{} = block) do
    block
    |> PropertyInheritance.detach_block()
    |> broadcast_block_dashboard_result(block)
  end

  @doc """
  Re-attaches a previously detached block.
  """
  def reattach_block(%Block{} = block) do
    fn -> reattach_block_transaction(block) end
    |> Repo.transaction()
    |> broadcast_block_dashboard_result(block)
  end

  defp reattach_block_transaction(block) do
    with {:ok, updated_block} <- PropertyInheritance.reattach_block(block),
         :ok <- Localization.extract_block(updated_block) do
      updated_block
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc """
  Hides an ancestor block from this sheet's children.
  """
  def hide_for_children(%Sheet{} = sheet, ancestor_block_id) do
    sheet
    |> PropertyInheritance.hide_for_children(ancestor_block_id)
    |> broadcast_sheet_dashboard_result(sheet)
  end

  @doc """
  Unhides an ancestor block for this sheet's children.
  """
  def unhide_for_children(%Sheet{} = sheet, ancestor_block_id) do
    sheet
    |> PropertyInheritance.unhide_for_children(ancestor_block_id)
    |> broadcast_sheet_dashboard_result(sheet)
  end

  @doc """
  Returns the source sheet for an inherited block.
  """
  defdelegate get_source_sheet(block), to: PropertyInheritance

  @doc """
  Returns all descendant sheet IDs for a given sheet.
  """
  defdelegate get_descendant_sheet_ids(sheet_id), to: PropertyInheritance

  @doc """
  Lists all blocks with `scope: "children"` for a sheet.
  """
  defdelegate list_inheritable_blocks(sheet_id), to: SheetQueries

  @doc """
  Lists all inherited instance blocks for a parent block.
  """
  defdelegate list_inherited_instances(parent_block_id), to: SheetQueries

  # =============================================================================
  # Blocks - Type Helpers
  # =============================================================================

  @doc """
  Parses a string value, clamps to min/max constraints, and formats back to string.
  """
  defdelegate number_clamp_and_format(value, config),
    to: Number,
    as: :clamp_and_format

  @doc """
  Parses a constraint value (from form params or config) into a number or nil.
  """
  defdelegate number_parse_constraint(value),
    to: Number,
    as: :parse_constraint

  @doc """
  Clamps a value to its block type constraints.

  Dispatches to the appropriate constraint module based on `block_type`.
  Rich text values pass through unclamped.
  """
  @spec clamp_to_constraints(any(), map() | nil, String.t()) :: any()
  def clamp_to_constraints(value, constraints, "number"), do: Number.clamp(value, constraints)

  def clamp_to_constraints(value, constraints, "text"), do: Storyarn.Sheets.Constraints.String.clamp(value, constraints)

  def clamp_to_constraints(value, _constraints, "rich_text"), do: value

  def clamp_to_constraints(value, constraints, type) when type in ["select", "multi_select"],
    do: Storyarn.Sheets.Constraints.Selector.clamp(value, constraints)

  def clamp_to_constraints(value, constraints, "date"), do: Storyarn.Sheets.Constraints.Date.clamp(value, constraints)

  def clamp_to_constraints(value, constraints, "boolean"),
    do: Storyarn.Sheets.Constraints.Boolean.clamp(value, constraints)

  def clamp_to_constraints(value, _constraints, _block_type), do: value

  # =============================================================================
  # Blocks - CRUD Operations
  # =============================================================================

  @doc """
  Lists all blocks for a sheet, ordered by position.
  """
  @spec list_blocks(id()) :: [block()]
  defdelegate list_blocks(sheet_id), to: BlockCrud

  @doc """
  Gets a single block by ID.
  """
  @spec get_block(id()) :: block() | nil
  defdelegate get_block(block_id), to: BlockCrud

  @doc """
  Gets a single block by ID.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_block!(id()) :: block()
  defdelegate get_block!(block_id), to: BlockCrud

  @doc """
  Gets a block by ID, ensuring it belongs to the specified project.
  Returns nil if not found or not in project.
  """
  @spec get_block_in_project(id(), id()) :: block() | nil
  defdelegate get_block_in_project(block_id, project_id), to: BlockCrud

  @doc """
  Gets a block by ID with project validation. Raises if not found.
  """
  @spec get_block_in_project!(id(), id()) :: block()
  defdelegate get_block_in_project!(block_id, project_id), to: BlockCrud

  @doc """
  Creates a new block in a sheet.
  """
  @spec create_block(sheet(), attrs()) :: {:ok, block()} | {:error, changeset()}
  defdelegate create_block(sheet, attrs), to: BlockCrud

  @doc """
  Recreates a block from a snapshot (for undo/redo).
  Restores soft-deleted block if it exists, otherwise creates new.
  """
  defdelegate create_block_from_snapshot(sheet, snapshot), to: BlockCrud

  @doc """
  Updates a block.
  """
  @spec update_block(block(), attrs()) :: {:ok, block()} | {:error, changeset()}
  defdelegate update_block(block, attrs), to: BlockCrud

  @doc """
  Updates a block's variable_name directly (user-initiated rename).
  """
  @spec update_variable_name(block(), String.t()) :: {:ok, block()} | {:error, changeset()}
  defdelegate update_variable_name(block, variable_name), to: BlockCrud

  @doc """
  Updates only the value of a block.
  """
  @spec update_block_value(block(), map()) :: {:ok, block()} | {:error, changeset()}
  defdelegate update_block_value(block, value), to: BlockCrud

  @doc """
  Updates only the config of a block.
  """
  @spec update_block_config(block(), map()) :: {:ok, block()} | {:error, changeset()}
  defdelegate update_block_config(block, config), to: BlockCrud

  @doc """
  Soft-deletes a block by setting deleted_at timestamp.
  """
  @spec delete_block(block()) :: {:ok, block()} | {:error, changeset()}
  defdelegate delete_block(block), to: BlockCrud

  @doc """
  Permanently deletes a block from the database.
  """
  @spec permanently_delete_block(block()) :: {:ok, block()} | {:error, changeset()}
  defdelegate permanently_delete_block(block), to: BlockCrud

  @doc """
  Restores a soft-deleted block.
  """
  @spec restore_block(block()) :: {:ok, block()} | {:error, changeset()}
  defdelegate restore_block(block), to: BlockCrud

  @doc """
  Reorders blocks within a sheet.
  Takes a list of block IDs in the desired order.
  """
  @spec reorder_blocks(id(), [id()]) :: {:ok, [block()]} | {:error, term()}
  defdelegate reorder_blocks(sheet_id, block_ids), to: BlockCrud

  @doc """
  Reorders blocks with column layout information.
  Each item in the list contains id, column_group_id, and column_index.
  """
  @spec reorder_blocks_with_columns(id(), [map()]) :: {:ok, [block()]} | {:error, term()}
  defdelegate reorder_blocks_with_columns(sheet_id, items), to: BlockCrud

  @doc """
  Creates a column group from a list of block IDs.
  """
  @spec create_column_group(id(), [id()]) :: {:ok, Ecto.UUID.t()} | {:error, term()}
  defdelegate create_column_group(sheet_id, block_ids), to: BlockCrud

  @doc """
  Duplicates a block, placing the copy immediately after the original.
  """
  defdelegate duplicate_block(block), to: BlockCrud

  @doc """
  Moves a block up by swapping with the previous block.
  """
  defdelegate move_block_up(block_id, sheet_id), to: BlockCrud

  @doc """
  Moves a block down by swapping with the next block.
  """
  defdelegate move_block_down(block_id, sheet_id), to: BlockCrud

  @doc """
  Returns a changeset for tracking block changes.
  """
  @spec change_block(block(), attrs()) :: changeset()
  defdelegate change_block(block, attrs \\ %{}), to: BlockCrud

  # =============================================================================
  # Table Columns
  # =============================================================================

  defdelegate list_table_columns(block_id), to: TableCrud, as: :list_columns
  defdelegate get_table_column!(block_id, id), to: TableCrud, as: :get_column!
  defdelegate get_table_column(block_id, id), to: TableCrud, as: :get_column
  defdelegate create_table_column(block, attrs), to: TableCrud, as: :create_column

  defdelegate create_table_column_from_snapshot(block_id, snapshot, cell_values),
    to: TableCrud,
    as: :create_column_from_snapshot

  defdelegate update_table_column(column, attrs), to: TableCrud, as: :update_column
  defdelegate delete_table_column(column), to: TableCrud, as: :delete_column
  defdelegate reorder_table_columns(block_id, ids), to: TableCrud, as: :reorder_columns

  # =============================================================================
  # Table Rows
  # =============================================================================

  defdelegate list_table_rows(block_id), to: TableCrud, as: :list_rows
  defdelegate get_table_row!(id), to: TableCrud, as: :get_row!
  defdelegate get_table_row(id), to: TableCrud, as: :get_row
  defdelegate create_table_row(block, attrs), to: TableCrud, as: :create_row

  defdelegate create_table_row_from_snapshot(block_id, snapshot, cells),
    to: TableCrud,
    as: :create_row_from_snapshot

  defdelegate update_table_row(row, attrs), to: TableCrud, as: :update_row
  defdelegate delete_table_row(row), to: TableCrud, as: :delete_row
  defdelegate reorder_table_rows(block_id, ids), to: TableCrud, as: :reorder_rows
  defdelegate update_table_cell(row, column_slug, value), to: TableCrud, as: :update_cell
  defdelegate update_table_cells(row, cells_map), to: TableCrud, as: :update_cells
  defdelegate batch_load_table_data(block_ids), to: TableCrud

  @doc "Injects computed formula results (`__result`/`__resolved`) into batched table data."
  defdelegate enrich_table_formulas(table_data, project_id), to: FormulaResolver, as: :enrich_table_data

  @doc "Gets an asset through the Sheet-owned read projection."
  defdelegate get_asset(project_id, asset_id), to: AssetCatalog

  @doc "Lists active assets through the Sheet-owned read projection."
  defdelegate list_assets(project_id, opts \\ []), to: AssetCatalog

  @doc "Checks whether a content type is allowed for direct Sheet uploads."
  defdelegate allowed_asset_content_type?(content_type),
    to: Storyarn.Sheets.Persistence.AssetRecord,
    as: :allowed_content_type?

  @doc "Creates a binary asset through the Sheet-owned asset command."
  defdelegate create_binary_asset(binary, attrs, project, user), to: AssetCommands

  @doc "Returns a Sheet-owned project projection after authorization."
  defdelegate get_project(scope, project_id), to: ProjectAccess

  @doc "Returns a Sheet-owned project projection by workspace and project slugs."
  defdelegate get_project_by_slugs(scope, workspace_slug, project_slug), to: ProjectAccess

  @doc "Publishes the product fact for a block created inside a Sheet."
  defdelegate record_block_created(scope, sheet, block, creation_method, block_scope),
    to: Events,
    as: :block_created

  @doc "Emits the typed Sheet fact that the version panel was opened."
  defdelegate record_version_panel_opened(scope, sheet), to: TrackedCommands

  @doc "Emits the typed Sheet fact that a version comparison was opened."
  defdelegate record_version_compared(scope, sheet), to: TrackedCommands

  @doc "Creates a named Sheet version and emits its Sheet-owned fact."
  defdelegate create_named_version(scope, sheet, opts), to: TrackedCommands

  @doc "Restores a Sheet version and emits its Sheet-owned fact on success."
  defdelegate restore_tracked_version(scope, sheet, version, opts),
    to: TrackedCommands,
    as: :restore_version

  @doc "Returns the Sheet-owned health severity ordering."
  defdelegate health_severity_rank(severity), to: Storyarn.Sheets.Severity, as: :rank

  @doc "Parses a table formula expression into an AST."
  defdelegate parse_formula(expression), to: FormulaEngine, as: :parse

  @doc "Extracts symbol names from a parsed formula AST."
  defdelegate extract_formula_symbols(ast), to: FormulaEngine, as: :extract_symbols

  @doc "Renders a parsed formula AST as LaTeX."
  defdelegate formula_to_latex(ast), to: FormulaEngine, as: :to_latex

  @doc "Renders a parsed formula AST as LaTeX with bound values substituted."
  defdelegate formula_to_latex_substituted(ast, resolved),
    to: FormulaEngine,
    as: :to_latex_substituted

  # =============================================================================
  # Gallery Images
  # =============================================================================

  defdelegate list_gallery_images(block_id), to: GalleryCrud
  defdelegate get_gallery_image(id), to: GalleryCrud
  defdelegate get_gallery_image_for_sheet(sheet_id, id), to: GalleryCrud
  defdelegate add_gallery_image(block, asset_id), to: GalleryCrud
  defdelegate add_gallery_images(block, asset_ids), to: GalleryCrud
  defdelegate remove_gallery_image(sheet_id, gallery_image_id), to: GalleryCrud
  defdelegate update_gallery_image(gallery_image, attrs), to: GalleryCrud
  defdelegate reorder_gallery_images(block_id, ordered_ids), to: GalleryCrud
  defdelegate batch_load_gallery_data(block_ids), to: GalleryCrud
  defdelegate batch_load_gallery_data_by_sheet(project_id), to: GalleryCrud
  defdelegate get_first_gallery_image(sheet_id), to: GalleryCrud

  # =============================================================================
  # Sheet Avatars
  # =============================================================================

  @type sheet_avatar :: SheetAvatar.t()

  defdelegate list_avatars(sheet_id), to: AvatarCrud
  defdelegate get_avatar(id), to: AvatarCrud
  defdelegate get_default_avatar(sheet_id), to: AvatarCrud
  defdelegate add_avatar(sheet, asset_id, attrs \\ %{}), to: AvatarCrud
  defdelegate update_avatar(avatar, attrs), to: AvatarCrud
  defdelegate remove_avatar(sheet_id, avatar_id), to: AvatarCrud
  defdelegate set_avatar_default(avatar), to: AvatarCrud, as: :set_default
  defdelegate reorder_avatars(sheet_id, ordered_ids), to: AvatarCrud
  defdelegate batch_load_avatars_by_sheet(project_id), to: AvatarCrud

  @doc """
  Returns the default image for a sheet using fallback hierarchy:
  default avatar → banner → first gallery image → nil.
  """
  def get_sheet_default_image(%Sheet{avatars: avatars} = sheet) when is_list(avatars) do
    case Enum.find(avatars, & &1.is_default) do
      %SheetAvatar{asset: asset} when not is_nil(asset) -> asset
      _ -> fallback_sheet_image(sheet)
    end
  end

  def get_sheet_default_image(%Sheet{} = sheet) do
    case get_default_avatar(sheet.id) do
      %SheetAvatar{asset: asset} when not is_nil(asset) -> asset
      _ -> fallback_sheet_image(sheet)
    end
  end

  defp fallback_sheet_image(sheet) do
    if sheet.banner_asset_id do
      sheet.banner_asset
    else
      get_first_gallery_image(sheet.id)
    end
  end

  # =============================================================================
  # Versioning
  # =============================================================================

  @doc "Returns whether in-place Sheet version restore is enabled."
  def restore_enabled?, do: Versioning.restore_enabled?()

  @doc """
  Creates a new version snapshot of the given sheet.
  """
  def create_version(%Sheet{} = sheet, user_id, opts \\ []) do
    Versioning.create_version(sheet, user_id, opts)
  end

  @doc """
  Lists all versions for a sheet, ordered by version number descending.
  """
  def list_versions(sheet_id, opts \\ []) do
    Versioning.list_versions(sheet_id, opts)
  end

  @doc """
  Gets a specific version by sheet_id and version_number.
  """
  def get_version(sheet_id, version_number) do
    Versioning.get_version(sheet_id, version_number)
  end

  @doc """
  Gets the latest version for a sheet.
  """
  def get_latest_version(sheet_id) do
    Versioning.get_latest_version(sheet_id)
  end

  @doc """
  Returns the total number of versions for a sheet.
  """
  def count_versions(sheet_id) do
    Versioning.count_versions(sheet_id)
  end

  @doc """
  Creates a version if enough time has passed since the last version.
  """
  def maybe_create_version(%Sheet{} = sheet, user_id, opts \\ []) do
    Versioning.maybe_create_version(sheet, user_id, opts)
  end

  @doc """
  Deletes a version and its snapshot.
  """
  def delete_version(version) do
    Versioning.delete_version(version)
  end

  @doc "Updates the name and description of a Sheet version."
  def update_version(version, attrs), do: Versioning.update_version(version, attrs)

  @doc false
  def load_version_snapshot(version), do: Versioning.load_version_snapshot(version)

  @doc "Serializes a stored Sheet snapshot into the read-only viewer block list."
  def serialize_version_snapshot(snapshot), do: SnapshotViewer.serialize_sheet(snapshot)

  @doc "Decides whether restore must first warn about unsaved changes."
  def prepare_version_restore(%Sheet{} = sheet, version), do: Versioning.prepare_restore(sheet, version)

  @doc "Loads a target Sheet version and builds its restore conflict report."
  def prepare_version_restore_conflicts(%Sheet{} = sheet, version),
    do: Versioning.prepare_restore_conflicts(sheet, version)

  @doc """
  Restores a sheet to a specific version.
  """
  def restore_version(%Sheet{} = sheet, version, opts \\ []) do
    Versioning.restore_version(sheet, version, opts)
  end

  @doc "Ensures that Sheet version restore is currently enabled."
  def ensure_version_restore_enabled, do: Versioning.ensure_restore_enabled()

  @doc "Builds the Sheet-owned restore-conflict preview."
  def detect_version_restore_conflicts(snapshot, %Sheet{} = sheet),
    do: Versioning.detect_restore_conflicts(snapshot, sheet)

  @doc "Returns the previous and next stored Sheet version numbers."
  def get_adjacent_version_numbers(sheet_id, current_number),
    do: Versioning.get_adjacent_version_numbers(sheet_id, current_number)

  @doc "Returns whether this project can create another named Sheet version."
  defdelegate can_create_named_version?(project_id, workspace_id), to: Limits

  @doc """
  Sets the current version for a sheet.
  """
  def set_current_version(%Sheet{} = sheet, version_or_nil) do
    version_id = if version_or_nil, do: version_or_nil.id

    sheet
    |> Sheet.version_changeset(%{current_version_id: version_id})
    |> Repo.update()
  end

  # =============================================================================
  # Reference Search & Validation
  # =============================================================================

  @doc """
  Validates that a reference target exists and belongs to the project.
  Returns {:ok, target} or {:error, reason}.
  """
  @spec validate_reference_target(String.t(), id(), id()) ::
          {:ok, Sheet.t() | FlowRecord.t()} | {:error, :not_found | :invalid_type}
  defdelegate validate_reference_target(target_type, target_id, project_id), to: SheetQueries

  @doc """
  Searches for sheets and flows that can be referenced.

  Returns a list of maps with :type, :id, :name, :shortcut keys.
  """
  @spec search_referenceable(id(), String.t(), [String.t()]) :: [map()]
  def search_referenceable(project_id, query, allowed_types \\ ["sheet", "flow"]) do
    query = String.trim(query)

    results = []

    results =
      if "sheet" in allowed_types do
        sheets = SheetQueries.search_sheets(project_id, query)

        sheet_results =
          Enum.map(sheets, fn sheet ->
            %{type: "sheet", id: sheet.id, name: sheet.name, shortcut: sheet.shortcut}
          end)

        results ++ sheet_results
      else
        results
      end

    results =
      if "flow" in allowed_types do
        flows = SheetQueries.search_reference_flows(project_id, query)

        flow_results =
          Enum.map(flows, fn flow ->
            %{type: "flow", id: flow.id, name: flow.name, shortcut: flow.shortcut}
          end)

        results ++ flow_results
      else
        results
      end

    # Sort by name and limit to 20 results
    results
    |> Enum.sort_by(& &1.name)
    |> Enum.take(20)
  end

  @doc """
  Gets the reference target (sheet or flow) for display.
  Returns nil if not found.
  """
  @spec get_reference_target(String.t() | nil, id() | nil, id()) :: map() | nil
  def get_reference_target(nil, _target_id, _project_id), do: nil
  def get_reference_target(_target_type, nil, _project_id), do: nil

  def get_reference_target("sheet", target_id, project_id) do
    case SheetQueries.get_sheet(project_id, target_id) do
      nil -> nil
      sheet -> %{type: "sheet", id: sheet.id, name: sheet.name, shortcut: sheet.shortcut}
    end
  end

  def get_reference_target("flow", target_id, project_id) do
    case SheetQueries.get_reference_flow(project_id, target_id) do
      nil -> nil
      flow -> %{type: "flow", id: flow.id, name: flow.name, shortcut: flow.shortcut}
    end
  end

  def get_reference_target(_target_type, _target_id, _project_id), do: nil

  @doc "Resolves multiple active sheet and flow targets in batch."
  defdelegate get_reference_targets(references, project_id), to: ReferenceTracker

  @doc "Returns block IDs with stale tracked sheet/flow entity references."
  defdelegate list_stale_block_reference_source_ids(project_id, block_ids), to: ReferenceTracker

  @doc "Counts tracked variable usages by kind for one block."
  defdelegate count_variable_usage(block_id), to: VariableUsage

  @doc "Counts stale tracked variable references for multiple blocks in one query."
  defdelegate count_stale_variable_references(block_ids, project_id),
    to: VariableUsage,
    as: :count_stale_references

  @doc "Lists tracked variable usages and their current staleness for one block."
  defdelegate check_stale_variable_references(block_id, project_id),
    to: VariableUsage,
    as: :check_stale_references

  # =============================================================================
  # Reference Tracking (Backlinks)
  # =============================================================================

  @doc """
  Gets backlinks for a target with resolved source information.
  """
  @spec get_backlinks_with_sources(String.t(), id(), id()) :: [map()]
  defdelegate get_backlinks_with_sources(target_type, target_id, project_id), to: ReferenceTracker

  @doc """
  Counts backlinks for a target.
  """
  @spec count_backlinks(String.t(), id()) :: integer()
  defdelegate count_backlinks(target_type, target_id), to: ReferenceTracker

  @doc """
  Updates references from a flow node.
  Called after node data is saved to track mentions and references.
  """
  @spec update_flow_node_references(map(), keyword()) :: :ok | {:error, term()}
  defdelegate update_flow_node_references(node, opts \\ []), to: ReferenceTracker

  @doc """
  Deletes all references from a flow node.
  Called when a node is deleted.
  """
  @spec delete_flow_node_references(integer()) :: {integer(), nil}
  defdelegate delete_flow_node_references(node_id), to: ReferenceTracker

  @doc """
  Deletes all references where a given entity is the target.
  Used for permanent deletion cleanup.
  """
  @spec delete_target_references(String.t(), integer()) :: {integer(), nil}
  defdelegate delete_target_references(target_type, target_id), to: ReferenceTracker

  # =============================================================================
  # Export / Import helpers
  # =============================================================================

  @doc "Returns the project_id for a sheet by its ID."
  defdelegate get_sheet_project_id(sheet_id), to: SheetQueries

  @doc "Lists sheets with blocks and table data preloaded. Opts: [filter_ids: :all | [ids]]."
  defdelegate list_sheets_for_export(project_id, opts \\ []), to: SheetQueries

  @doc "Counts non-deleted sheets for a project."
  defdelegate count_sheets(project_id), to: SheetQueries

  @doc "Lists all non-deleted blocks for the given sheet IDs."
  defdelegate list_blocks_for_sheet_ids(sheet_ids), to: SheetQueries

  @doc "Lists brief sheet data (id, name, shortcut) for validator. Opts: [filter_ids: :all | [ids]]."
  defdelegate list_sheets_brief(project_id, opts \\ []), to: SheetQueries

  @doc "Lists existing sheet shortcuts for a project."
  defdelegate list_sheet_shortcuts(project_id), to: SheetQueries, as: :list_shortcuts

  @doc "Detects shortcut conflicts between imported sheets and existing ones."
  defdelegate detect_sheet_shortcut_conflicts(project_id, shortcuts),
    to: SheetQueries,
    as: :detect_shortcut_conflicts

  @doc "Soft-deletes existing sheets with the given shortcut (overwrite import strategy)."
  defdelegate soft_delete_sheet_by_shortcut(project_id, shortcut),
    to: SheetQueries,
    as: :soft_delete_by_shortcut

  @doc "Returns stale variable reference data for flow nodes."
  defdelegate check_stale_flow_node_variable_references(block_id, project_id), to: SheetQueries

  @doc "Returns variable references with current block info for stale repair."
  defdelegate list_variable_refs_with_block_info_for_repair(project_id), to: SheetQueries

  @doc "Lists stale regular (non-table) node IDs in one flow."
  defdelegate list_stale_regular_node_ids(flow_id), to: SheetQueries

  @doc "Lists stale table node IDs in one flow."
  defdelegate list_stale_table_node_ids(flow_id), to: SheetQueries

  @doc "Resolves a block ID by sheet shortcut and variable name."
  defdelegate resolve_block_id_by_variable(project_id, sheet_shortcut, variable_name),
    to: SheetQueries

  @doc "Resolves a table block ID by sheet shortcut, table name, row slug, and column slug."
  defdelegate resolve_table_block_id_by_variable(
                project_id,
                sheet_shortcut,
                table_name,
                row_slug,
                column_slug
              ),
              to: SheetQueries

  @doc "Lists sheet IDs referenced through variable_references in a project."
  defdelegate list_variable_referenced_sheet_ids(project_id), to: SheetQueries

  @doc "Lists sheets using a specific asset as their avatar."
  defdelegate list_sheets_using_asset_as_avatar(project_id, asset_id), to: SheetQueries

  @doc "Lists sheets using a specific asset as their banner."
  defdelegate list_sheets_using_asset_as_banner(project_id, asset_id), to: SheetQueries

  @doc "Lists sheet IDs referenced by scene pins in a project."
  defdelegate list_pin_referenced_sheet_ids(project_id), to: SheetQueries

  @doc "Lists Scene-owned placements that display a Sheet."
  defdelegate list_scene_appearances(sheet_id), to: SceneReadModel, as: :list_sheet_appearances

  @doc "Creates a sheet for import (raw insert, no side effects)."
  defdelegate import_sheet(project_id, attrs), to: SheetCrud

  @doc "Updates a sheet's parent_id after import."
  defdelegate link_sheet_import_parent(sheet, parent_id), to: SheetCrud, as: :link_import_parent

  @doc "Creates a block for import (raw insert, no side effects)."
  defdelegate import_block(sheet_id, attrs), to: BlockCrud

  @doc "Creates a table column for import (raw insert, no side effects)."
  defdelegate import_table_column(block_id, attrs), to: TableCrud, as: :import_column

  @doc "Creates a table row for import (raw insert, no side effects)."
  defdelegate import_table_row(block_id, attrs), to: TableCrud, as: :import_row

  # =============================================================================
  # Dashboard Stats
  # =============================================================================

  @doc "Returns per-sheet block and variable counts. %{sheet_id => %{block_count, variable_count}}."
  defdelegate sheet_stats_for_project(project_id), to: SheetStats

  @doc "Returns per-sheet localizable word counts from runtime sheet fields. %{sheet_id => word_count}."
  defdelegate sheet_word_counts(project_id), to: SheetStats

  @doc "Returns the block types that contribute player-facing runtime text."
  defdelegate localizable_block_types(), to: Storyarn.Sheets.ContentContract

  @doc "Computes the player-facing word count for one Sheet block."
  defdelegate block_word_count(type, value), to: WordCount, as: :for_block

  @doc "Returns MapSet of block IDs with at least one variable reference."
  defdelegate referenced_block_ids_for_project(project_id), to: SheetStats

  @doc "Returns the canonical sheet health findings used by the project dashboard overview."
  defdelegate list_dashboard_health_findings(project_id, referenced_ids \\ nil), to: SheetStats

  @doc """
  Returns the canonical health findings for the one sheet open in the editor.

  The Sheets counterpart to the Scene and Flow entity health readers,
  and the same composition point `list_dashboard_health_findings/2` enters: the
  editor and the dashboard cannot feed the checker differently for the same sheet.

  Expects the material the editor already holds — `:sheet`, `:project`, `:blocks`,
  `:inherited_groups`, `:table_data`, `:gallery_data`.
  """
  defdelegate sheet_health_findings(material), to: HealthSnapshots, as: :findings

  @doc "Returns the checker-ready snapshot behind `sheet_health_findings/1`."
  defdelegate sheet_health_snapshot(material), to: HealthSnapshots, as: :snapshot

  @doc """
  Returns `%{variable_reference => block_type}` for the project — the vocabulary
  both health surfaces type-check formula bindings against.
  """
  defdelegate health_variable_types(project_id), to: HealthSnapshots, as: :variable_types

  defp broadcast_block_dashboard_result({:ok, _value} = result, %Block{} = block) do
    case Repo.get(Sheet, block.sheet_id) do
      %Sheet{project_id: project_id} -> Collaboration.broadcast_dashboard_change(project_id, :sheets)
      nil -> :ok
    end

    result
  end

  defp broadcast_block_dashboard_result(result, _block), do: result

  defp broadcast_sheet_dashboard_result({:ok, _value} = result, %Sheet{project_id: project_id}) do
    Collaboration.broadcast_dashboard_change(project_id, :sheets)
    result
  end

  defp broadcast_sheet_dashboard_result(result, _sheet), do: result
end
