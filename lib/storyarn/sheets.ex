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
    AvatarCrud,
    Block,
    BlockCrud,
    GalleryCrud,
    PropertyInheritance,
    Sheet,
    SheetAvatar,
    SheetCrud,
    SheetQueries,
    SheetStats,
    TableCrud,
    TreeOperations
  }

  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Versioning
  alias Storyarn.Versioning.EntityVersion

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

  # =============================================================================
  # Gallery Images
  # =============================================================================

  defdelegate list_gallery_images(block_id), to: GalleryCrud
  defdelegate get_gallery_image(id), to: GalleryCrud
  defdelegate add_gallery_image(block, asset_id), to: GalleryCrud
  defdelegate add_gallery_images(block, asset_ids), to: GalleryCrud
  defdelegate remove_gallery_image(gallery_image_id), to: GalleryCrud
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
  defdelegate remove_avatar(avatar_id), to: AvatarCrud
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

  @type version :: EntityVersion.t()

  @doc """
  Creates a new version snapshot of the given sheet.
  """
  def create_version(sheet, user_or_id, opts \\ [])

  def create_version(%Sheet{} = sheet, %Storyarn.Accounts.User{} = user, opts) do
    create_version(sheet, user.id, opts)
  end

  def create_version(%Sheet{} = sheet, user_id, opts) when is_integer(user_id) do
    Versioning.create_version("sheet", sheet, sheet.project_id, user_id, opts)
  end

  @doc """
  Lists all versions for a sheet, ordered by version number descending.
  """
  def list_versions(sheet_id, opts \\ []) do
    Versioning.list_versions("sheet", sheet_id, opts)
  end

  @doc """
  Gets a specific version by sheet_id and version_number.
  """
  def get_version(sheet_id, version_number) do
    Versioning.get_version("sheet", sheet_id, version_number)
  end

  @doc """
  Gets the latest version for a sheet.
  """
  def get_latest_version(sheet_id) do
    Versioning.get_latest_version("sheet", sheet_id)
  end

  @doc """
  Returns the total number of versions for a sheet.
  """
  def count_versions(sheet_id) do
    Versioning.count_versions("sheet", sheet_id)
  end

  @doc """
  Creates a version if enough time has passed since the last version.
  """
  def maybe_create_version(sheet, user_or_id, opts \\ [])

  def maybe_create_version(%Sheet{} = sheet, %Storyarn.Accounts.User{} = user, opts) do
    maybe_create_version(sheet, user.id, opts)
  end

  def maybe_create_version(%Sheet{} = sheet, user_id, opts) when is_integer(user_id) do
    opts = Keyword.put_new(opts, :is_auto, true)

    if Keyword.get(opts, :is_auto) and
         not Projects.auto_versioning_enabled?(sheet.project_id, :sheet) do
      {:skipped, :auto_versioning_disabled}
    else
      Versioning.maybe_create_version("sheet", sheet, sheet.project_id, user_id, opts)
    end
  end

  @doc """
  Deletes a version and its snapshot.
  """
  def delete_version(version) do
    Versioning.delete_version(version)
  end

  @doc """
  Restores a sheet to a specific version.
  """
  def restore_version(%Sheet{} = sheet, version) do
    Versioning.restore_version("sheet", sheet, version)
  end

  @doc """
  Sets the current version for a sheet.
  """
  def set_current_version(%Sheet{} = sheet, version_or_nil) do
    version_id = if version_or_nil, do: version_or_nil.id, else: nil

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

  alias Storyarn.References

  @doc """
  Gets backlinks for a target with resolved source information.
  """
  @spec get_backlinks_with_sources(String.t(), id(), id()) :: [map()]
  defdelegate get_backlinks_with_sources(target_type, target_id, project_id), to: References

  @doc """
  Counts backlinks for a target.
  """
  @spec count_backlinks(String.t(), id()) :: integer()
  defdelegate count_backlinks(target_type, target_id), to: References

  @doc """
  Updates references from a flow node.
  Called after node data is saved to track mentions and references.
  """
  @spec update_flow_node_references(map()) :: :ok
  defdelegate update_flow_node_references(node),
    to: References,
    as: :update_flow_node_entity_references

  @doc """
  Deletes all references from a flow node.
  Called when a node is deleted.
  """
  @spec delete_flow_node_references(integer()) :: {integer(), nil}
  defdelegate delete_flow_node_references(node_id),
    to: References,
    as: :delete_flow_node_entity_references

  @doc """
  Updates references from a scene zone.
  Called after zone data is saved to track target references.
  """
  @spec update_scene_zone_references(map()) :: :ok
  defdelegate update_scene_zone_references(zone),
    to: References,
    as: :update_scene_zone_entity_references

  @doc """
  Deletes all references from a scene zone.
  Called when a zone is deleted.
  """
  @spec delete_map_zone_references(integer()) :: {integer(), nil}
  defdelegate delete_map_zone_references(zone_id),
    to: References,
    as: :delete_scene_zone_entity_references

  @doc """
  Updates references from a scene pin.
  Called after pin data is saved to track target references.
  """
  @spec update_scene_pin_references(map()) :: :ok
  defdelegate update_scene_pin_references(pin),
    to: References,
    as: :update_scene_pin_entity_references

  @doc """
  Deletes all references from a scene pin.
  Called when a pin is deleted.
  """
  @spec delete_map_pin_references(integer()) :: {integer(), nil}
  defdelegate delete_map_pin_references(pin_id),
    to: References,
    as: :delete_scene_pin_entity_references

  @doc """
  Deletes all references where a given entity is the target.
  Used for permanent deletion cleanup.
  """
  @spec delete_target_references(String.t(), integer()) :: {integer(), nil}
  defdelegate delete_target_references(target_type, target_id), to: References

  @doc """
  Updates references from a screenplay element.
  Called after element content is saved to track character sheet refs and mentions.
  """
  @spec update_screenplay_element_references(map()) :: :ok
  defdelegate update_screenplay_element_references(element), to: References

  @doc """
  Deletes all references from a screenplay element.
  Called when an element is deleted.
  """
  @spec delete_screenplay_element_references(id()) :: {integer(), nil}
  defdelegate delete_screenplay_element_references(element_id), to: References

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

  # =============================================================================
  # Dashboard Stats
  # =============================================================================

  @doc "Returns per-sheet block and variable counts. %{sheet_id => %{block_count, variable_count}}."
  defdelegate sheet_stats_for_project(project_id), to: SheetStats

  @doc "Returns per-sheet word counts from text/rich_text blocks. %{sheet_id => word_count}."
  defdelegate sheet_word_counts(project_id), to: SheetStats

  @doc "Returns MapSet of block IDs with at least one variable reference."
  defdelegate referenced_block_ids_for_project(project_id), to: SheetStats

  @doc "Detects issues in sheets. Returns [%{issue_type, sheet_id, sheet_name, ...}]."
  defdelegate detect_sheet_issues(project_id, referenced_ids \\ nil), to: SheetStats
end
