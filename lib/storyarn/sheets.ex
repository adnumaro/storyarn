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

  alias Storyarn.Sheets.{
    Block,
    BlockCrud,
    PropertyInheritance,
    Sheet,
    SheetCrud,
    SheetQueries,
    SheetVersion,
    TableCrud,
    TreeOperations,
    Versioning
  }

  alias Storyarn.Projects.Project

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

  # =============================================================================
  # Sheets - Tree Operations
  # =============================================================================

  @doc """
  Lists all sheets for a project as a tree structure.
  Returns root sheets (no parent) with children preloaded recursively.
  """
  @spec list_sheets_tree(id()) :: [sheet()]
  defdelegate list_sheets_tree(project_id), to: SheetQueries

  @doc """
  Gets a single sheet by ID within a project.
  Returns `nil` if the sheet doesn't exist or doesn't belong to the project.
  """
  @spec get_sheet(id(), id()) :: sheet() | nil
  defdelegate get_sheet(project_id, sheet_id), to: SheetQueries

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
  @spec create_sheet(Project.t(), attrs()) :: {:ok, sheet()} | {:error, changeset()}
  defdelegate create_sheet(project, attrs), to: SheetCrud

  @doc """
  Updates a sheet.
  """
  @spec update_sheet(sheet(), attrs()) :: {:ok, sheet()} | {:error, changeset()}
  defdelegate update_sheet(sheet, attrs), to: SheetCrud

  @doc """
  Soft deletes a sheet (moves to trash).
  Also soft deletes all descendant sheets.
  """
  @spec delete_sheet(sheet()) :: {:ok, sheet()} | {:error, changeset()}
  defdelegate delete_sheet(sheet), to: SheetCrud

  @doc """
  Soft deletes a sheet and all its descendants (moves to trash).
  Alias for `delete_sheet/1`.
  """
  @spec trash_sheet(sheet()) :: {:ok, sheet()} | {:error, changeset()}
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

  @doc """
  Returns a changeset for tracking sheet changes.
  """
  @spec change_sheet(sheet(), attrs()) :: changeset()
  defdelegate change_sheet(sheet, attrs \\ %{}), to: SheetCrud

  @doc """
  Validates if a parent_id is valid for a sheet.
  Returns `:ok` if valid, `{:error, reason}` if invalid.
  """
  @spec validate_parent(sheet(), id() | nil) :: :ok | {:error, validation_error()}
  defdelegate validate_parent(sheet, parent_id), to: SheetCrud

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
    with :ok <- SheetCrud.validate_parent(sheet, new_parent_id) do
      TreeOperations.move_sheet_to_position(sheet, new_parent_id, new_position)
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
  Gets a sheet's blocks split into inherited and own groups.
  Returns `{inherited_groups, own_blocks}`.
  """
  defdelegate get_sheet_blocks_grouped(sheet_id), to: SheetQueries

  @doc """
  Propagates an inheritable block to selected descendant sheets.
  """
  defdelegate propagate_to_descendants(parent_block, selected_sheet_ids),
    to: PropertyInheritance

  @doc """
  Detaches an inherited block, making it a local copy.
  """
  defdelegate detach_block(block), to: PropertyInheritance

  @doc """
  Re-attaches a previously detached block.
  """
  defdelegate reattach_block(block), to: PropertyInheritance

  @doc """
  Hides an ancestor block from this sheet's children.
  """
  defdelegate hide_for_children(sheet, ancestor_block_id), to: PropertyInheritance

  @doc """
  Unhides an ancestor block for this sheet's children.
  """
  defdelegate unhide_for_children(sheet, ancestor_block_id), to: PropertyInheritance

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
  Returns true if the given block type can act as a variable.
  """
  @spec can_be_variable?(String.t()) :: boolean()
  defdelegate can_be_variable?(block_type), to: Block

  @doc """
  Returns true if the block is inherited from a parent sheet.
  """
  @spec inherited?(block()) :: boolean()
  defdelegate inherited?(block), to: Block

  @doc """
  Parses a string value, clamps to min/max constraints, and formats back to string.
  """
  defdelegate number_clamp_and_format(value, config),
    to: Storyarn.Sheets.Constraints.Number,
    as: :clamp_and_format

  @doc """
  Parses a constraint value (from form params or config) into a number or nil.
  """
  defdelegate number_parse_constraint(value),
    to: Storyarn.Sheets.Constraints.Number,
    as: :parse_constraint

  @doc """
  Clamps a value to its block type constraints.

  Dispatches to the appropriate constraint module based on `block_type`.
  Rich text values pass through unclamped.
  """
  @spec clamp_to_constraints(any(), map() | nil, String.t()) :: any()
  def clamp_to_constraints(value, constraints, "number"),
    do: Storyarn.Sheets.Constraints.Number.clamp(value, constraints)

  def clamp_to_constraints(value, constraints, "text"),
    do: Storyarn.Sheets.Constraints.String.clamp(value, constraints)

  def clamp_to_constraints(value, _constraints, "rich_text"), do: value

  def clamp_to_constraints(value, constraints, type) when type in ["select", "multi_select"],
    do: Storyarn.Sheets.Constraints.Selector.clamp(value, constraints)

  def clamp_to_constraints(value, constraints, "date"),
    do: Storyarn.Sheets.Constraints.Date.clamp(value, constraints)

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

  # =============================================================================
  # Versioning
  # =============================================================================

  @type version :: SheetVersion.t()

  @doc """
  Creates a new version snapshot of the given sheet.
  The snapshot includes sheet metadata and all blocks.

  ## Options
  - `:title` - Custom title for the version (for manual versions)
  - `:description` - Optional description of changes
  """
  @spec create_version(sheet(), Storyarn.Accounts.User.t() | integer() | nil, keyword()) ::
          {:ok, version()} | {:error, changeset()}
  defdelegate create_version(sheet, user_or_id, opts \\ []), to: Versioning

  @doc """
  Lists all versions for a sheet, ordered by version number descending.
  """
  @spec list_versions(id(), keyword()) :: [version()]
  defdelegate list_versions(sheet_id, opts \\ []), to: Versioning

  @doc """
  Gets a specific version by sheet_id and version_number.
  """
  @spec get_version(id(), integer()) :: version() | nil
  defdelegate get_version(sheet_id, version_number), to: Versioning

  @doc """
  Gets the latest version for a sheet.
  """
  @spec get_latest_version(id()) :: version() | nil
  defdelegate get_latest_version(sheet_id), to: Versioning

  @doc """
  Returns the total number of versions for a sheet.
  """
  @spec count_versions(id()) :: integer()
  defdelegate count_versions(sheet_id), to: Versioning

  @doc """
  Creates a version if enough time has passed since the last version (rate limited).
  Returns `{:ok, version}`, `{:skipped, :too_recent}`, or `{:error, changeset}`.
  """
  @spec maybe_create_version(sheet(), Storyarn.Accounts.User.t() | integer() | nil, keyword()) ::
          {:ok, version()} | {:skipped, :too_recent} | {:error, changeset()}
  defdelegate maybe_create_version(sheet, user_or_id, opts \\ []), to: Versioning

  @doc """
  Deletes a version.
  If the deleted version is the current_version of its sheet, clears the reference.
  """
  @spec delete_version(version()) :: {:ok, version()} | {:error, changeset()}
  defdelegate delete_version(version), to: Versioning

  @doc """
  Sets the current version for a sheet.
  This marks the version as "active" without modifying sheet content.
  """
  @spec set_current_version(sheet(), version() | nil) :: {:ok, sheet()} | {:error, changeset()}
  defdelegate set_current_version(sheet, version), to: Versioning

  @doc """
  Restores a sheet to a specific version.
  Applies the snapshot (metadata and blocks) and sets as current version.
  Does NOT create a new version.
  """
  @spec restore_version(sheet(), version()) :: {:ok, sheet()} | {:error, term()}
  defdelegate restore_version(sheet, version), to: Versioning

  # =============================================================================
  # Reference Search & Validation
  # =============================================================================

  @doc """
  Validates that a reference target exists and belongs to the project.
  Returns {:ok, target} or {:error, reason}.
  """
  @spec validate_reference_target(String.t(), id(), id()) ::
          {:ok, Sheet.t() | Storyarn.Flows.Flow.t()} | {:error, :not_found | :invalid_type}
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
        flows = Storyarn.Flows.search_flows(project_id, query)

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
    case Storyarn.Flows.get_flow(project_id, target_id) do
      nil -> nil
      flow -> %{type: "flow", id: flow.id, name: flow.name, shortcut: flow.shortcut}
    end
  end

  # =============================================================================
  # Reference Tracking (Backlinks)
  # =============================================================================

  alias Storyarn.Sheets.ReferenceTracker

  @doc """
  Updates references from a block.
  Called after block content is saved to track mentions and references.
  """
  @spec update_block_references(block()) :: :ok
  defdelegate update_block_references(block), to: ReferenceTracker

  @doc """
  Deletes all references from a block.
  Called when a block is deleted.
  """
  @spec delete_block_references(id()) :: {integer(), nil}
  defdelegate delete_block_references(block_id), to: ReferenceTracker

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
  @spec update_flow_node_references(map()) :: :ok
  defdelegate update_flow_node_references(node), to: ReferenceTracker

  @doc """
  Deletes all references from a flow node.
  Called when a node is deleted.
  """
  @spec delete_flow_node_references(integer()) :: {integer(), nil}
  defdelegate delete_flow_node_references(node_id), to: ReferenceTracker

  @doc """
  Updates references from a scene zone.
  Called after zone data is saved to track target references.
  """
  @spec update_scene_zone_references(map()) :: :ok
  defdelegate update_scene_zone_references(zone), to: ReferenceTracker

  @doc """
  Deletes all references from a scene zone.
  Called when a zone is deleted.
  """
  @spec delete_map_zone_references(integer()) :: {integer(), nil}
  defdelegate delete_map_zone_references(zone_id), to: ReferenceTracker

  @doc """
  Updates references from a scene pin.
  Called after pin data is saved to track target references.
  """
  @spec update_scene_pin_references(map()) :: :ok
  defdelegate update_scene_pin_references(pin), to: ReferenceTracker

  @doc """
  Deletes all references from a scene pin.
  Called when a pin is deleted.
  """
  @spec delete_map_pin_references(integer()) :: {integer(), nil}
  defdelegate delete_map_pin_references(pin_id), to: ReferenceTracker

  @doc """
  Deletes all references where a given entity is the target.
  Used for permanent deletion cleanup.
  """
  @spec delete_target_references(String.t(), integer()) :: {integer(), nil}
  defdelegate delete_target_references(target_type, target_id), to: ReferenceTracker

  @doc """
  Updates references from a screenplay element.
  Called after element content is saved to track character sheet refs and mentions.
  """
  @spec update_screenplay_element_references(map()) :: :ok
  defdelegate update_screenplay_element_references(element), to: ReferenceTracker

  @doc """
  Deletes all references from a screenplay element.
  Called when an element is deleted.
  """
  @spec delete_screenplay_element_references(id()) :: {integer(), nil}
  defdelegate delete_screenplay_element_references(element_id), to: ReferenceTracker

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

  @doc "Lists brief sheet data (id, name, shortcut) for validator."
  defdelegate list_sheets_brief(project_id), to: SheetQueries

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

  @doc "Lists stale regular (non-table) node IDs in a flow."
  defdelegate list_stale_regular_node_ids(flow_id), to: SheetQueries

  @doc "Lists stale table node IDs in a flow."
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
end
