defmodule Storyarn.Sheets.Editor do
  @moduledoc """
  Public capability boundary for authored Sheet structure and content.

  It exposes the Sheet aggregate, blocks, tables, galleries, avatars, tree
  operations, inheritance, and the Sheet-owned dialogue-audio workspace. Its
  private commands, queries, data projections, and rules remain internal.
  """

  alias Storyarn.Sheets.Editor.Adapters.Flows.DialogueAudio, as: DialogueAudioWriter
  alias Storyarn.Sheets.Editor.Commands.Avatars
  alias Storyarn.Sheets.Editor.Commands.Blocks
  alias Storyarn.Sheets.Editor.Commands.Galleries
  alias Storyarn.Sheets.Editor.Commands.Inheritance
  alias Storyarn.Sheets.Editor.Commands.InheritanceWorkflows
  alias Storyarn.Sheets.Editor.Commands.SheetMovement
  alias Storyarn.Sheets.Editor.Commands.Sheets
  alias Storyarn.Sheets.Editor.Commands.Tables
  alias Storyarn.Sheets.Editor.Commands.Tree
  alias Storyarn.Sheets.Editor.Events
  alias Storyarn.Sheets.Editor.Projections.FlowNodeRecord
  alias Storyarn.Sheets.Editor.Queries.Avatars, as: AvatarQueries
  alias Storyarn.Sheets.Editor.Queries.DefaultImage
  alias Storyarn.Sheets.Editor.Queries.DialogueAudio
  alias Storyarn.Sheets.Editor.Queries.Galleries, as: GalleryQueries
  alias Storyarn.Sheets.Editor.Queries.Sheets, as: SheetQueries

  defdelegate list_dialogue_audio_lines(project_id, sheet_id), to: DialogueAudio, as: :list_lines

  @dialogue_audio_node_fields [
    :id,
    :type,
    :position_x,
    :position_y,
    :data,
    :word_count,
    :derivatives_fingerprint,
    :deleted_at,
    :flow_id,
    :parent_id,
    :inserted_at,
    :updated_at
  ]

  # Keep the established Sheets facade result while the write itself crosses
  # the boundary through a transport-neutral Flow receipt. Materializing the
  # committed snapshot locally avoids a second, non-atomic database read while
  # still preventing a Flow schema from crossing into Sheets.
  def update_dialogue_audio(project_id, sheet_id, node_id, audio_asset_id) do
    with {:ok, receipt} <-
           DialogueAudioWriter.assign(project_id, sheet_id, node_id, audio_asset_id),
         {:ok, %FlowNodeRecord{} = node} <- local_dialogue_audio_node(receipt) do
      {:ok, node}
    end
  end

  defp local_dialogue_audio_node(%{
         node_id: node_id,
         audio_asset_id: audio_asset_id,
         node_snapshot: %{id: node_id, data: data} = snapshot
       })
       when is_integer(node_id) and node_id > 0 and is_map(data) do
    if Map.get(data, "audio_asset_id") == audio_asset_id do
      node = struct(FlowNodeRecord, Map.take(snapshot, @dialogue_audio_node_fields))
      {:ok, Ecto.put_meta(node, state: :loaded)}
    else
      {:error, :invalid_dialogue_audio_receipt}
    end
  end

  defp local_dialogue_audio_node(_receipt), do: {:error, :invalid_dialogue_audio_receipt}

  defdelegate list_sheets_tree(project_id), to: SheetQueries
  defdelegate search_sheets(project_id, query, opts \\ []), to: SheetQueries
  defdelegate search_sheets_deep(project_id, query, opts \\ []), to: SheetQueries
  defdelegate search_sheets_in_projects(project_ids, query, opts \\ []), to: SheetQueries
  defdelegate get_sheet(project_id, sheet_id), to: SheetQueries
  defdelegate get_sheet!(project_id, sheet_id), to: SheetQueries
  defdelegate get_sheet_full(project_id, sheet_id), to: SheetQueries
  defdelegate get_sheet_full!(project_id, sheet_id), to: SheetQueries
  defdelegate get_sheet_with_ancestors(project_id, sheet_id), to: SheetQueries
  defdelegate get_sheet_with_descendants(project_id, sheet_id), to: SheetQueries
  defdelegate get_children(sheet_id), to: SheetQueries
  defdelegate has_children?(sheet_id), to: SheetQueries
  defdelegate list_sheets_by_ids(project_id, ids), to: SheetQueries
  defdelegate list_all_sheets(project_id), to: SheetQueries
  defdelegate list_leaf_sheets(project_id), to: SheetQueries
  defdelegate get_sheet_by_shortcut(project_id, shortcut), to: SheetQueries
  defdelegate get_sheet_blocks_grouped(sheet_id), to: SheetQueries
  defdelegate list_project_blocks_grouped(sheets), to: SheetQueries
  defdelegate list_inheritable_blocks(sheet_id), to: SheetQueries
  defdelegate list_inherited_instances(parent_block_id), to: SheetQueries
  defdelegate list_trashed_sheets(project_id), to: SheetQueries
  defdelegate get_trashed_sheet(project_id, sheet_id), to: SheetQueries
  defdelegate get_sheet_project_id(sheet_id), to: SheetQueries
  defdelegate list_sheets_unpreloaded(project_id), to: SheetQueries
  defdelegate list_blocks_for_sheet_ids(sheet_ids), to: SheetQueries
  defdelegate list_sheets_brief(project_id, opts \\ []), to: SheetQueries

  defdelegate create_sheet(project, attrs), to: Sheets
  defdelegate create_sheet(actor_scope, project, attrs), to: Sheets
  defdelegate create_sheet_in_transaction(project, attrs), to: Sheets
  defdelegate create_sheet_in_transaction(actor_scope, project, attrs), to: Sheets
  defdelegate sync_created_sheet_localization(sheet), to: Sheets
  defdelegate update_sheet(sheet, attrs), to: Sheets
  defdelegate delete_sheet(sheet), to: Sheets
  defdelegate delete_sheet(actor_scope, sheet), to: Sheets
  defdelegate delete_sheet_subtree(sheet), to: Sheets
  defdelegate delete_sheet_subtree(actor_scope, sheet), to: Sheets
  defdelegate delete_sheet_subtree_by_id_in_transaction(actor_scope, project_id, sheet_id), to: Sheets
  defdelegate delete_sheet_subtree_in_transaction(sheet), to: Sheets
  defdelegate delete_sheet_subtree_in_transaction(actor_scope, sheet), to: Sheets
  defdelegate trash_sheet(sheet), to: Sheets
  defdelegate restore_sheet(sheet), to: Sheets
  defdelegate permanently_delete_sheet(sheet), to: Sheets
  defdelegate move_sheet(sheet, parent_id, position \\ nil), to: Sheets
  defdelegate change_sheet(sheet, attrs \\ %{}), to: Sheets

  defdelegate reorder_sheets(project_id, parent_id, sheet_ids), to: Tree
  defdelegate move_sheet_to_position(sheet, parent_id, position), to: SheetMovement, as: :move_to_position

  defdelegate resolve_inherited_blocks(sheet_id), to: Inheritance
  defdelegate list_inheritance_health_issues(sheet_id), to: Inheritance, as: :list_health_issues

  defdelegate list_project_inheritance_health_issues(sheets, table_data \\ nil),
    to: Inheritance,
    as: :list_project_health_issues

  defdelegate propagate_to_descendants(parent_block, sheet_ids), to: InheritanceWorkflows
  defdelegate detach_block(block), to: InheritanceWorkflows
  defdelegate reattach_block(block), to: InheritanceWorkflows
  defdelegate hide_for_children(sheet, block_id), to: InheritanceWorkflows
  defdelegate unhide_for_children(sheet, block_id), to: InheritanceWorkflows
  defdelegate get_source_sheet(block), to: Inheritance
  defdelegate get_descendant_sheet_ids(sheet_id), to: Inheritance
  @doc false
  defdelegate delete_inherited_instances(block), to: Inheritance
  @doc false
  defdelegate sync_inheritance_definition(block, opts \\ []),
    to: Inheritance,
    as: :sync_definition_change

  defdelegate list_blocks(sheet_id), to: Blocks
  defdelegate get_block(block_id), to: Blocks
  defdelegate get_block!(block_id), to: Blocks
  defdelegate get_block_in_project(block_id, project_id), to: Blocks
  defdelegate get_block_in_project!(block_id, project_id), to: Blocks
  defdelegate create_block(sheet, attrs), to: Blocks
  defdelegate create_block_from_snapshot(sheet, snapshot), to: Blocks
  defdelegate update_block(block, attrs), to: Blocks
  defdelegate update_variable_name(block, name), to: Blocks
  defdelegate update_block_value(block, value), to: Blocks
  defdelegate update_block_config(block, config), to: Blocks
  defdelegate delete_block(block), to: Blocks
  defdelegate permanently_delete_block(block), to: Blocks
  defdelegate restore_block(block), to: Blocks
  defdelegate reorder_blocks(sheet_id, block_ids), to: Blocks
  defdelegate reorder_blocks_with_columns(sheet_id, items), to: Blocks
  defdelegate create_column_group(sheet_id, block_ids), to: Blocks
  defdelegate duplicate_block(block), to: Blocks
  defdelegate move_block_up(block_id, sheet_id), to: Blocks
  defdelegate move_block_down(block_id, sheet_id), to: Blocks
  defdelegate change_block(block, attrs \\ %{}), to: Blocks

  defdelegate list_table_columns(block_id), to: Tables, as: :list_columns
  defdelegate get_table_column!(block_id, id), to: Tables, as: :get_column!
  defdelegate get_table_column(block_id, id), to: Tables, as: :get_column
  defdelegate create_table_column(block, attrs), to: Tables, as: :create_column

  defdelegate create_table_column_from_snapshot(block_id, snapshot, values),
    to: Tables,
    as: :create_column_from_snapshot

  defdelegate update_table_column(column, attrs), to: Tables, as: :update_column
  defdelegate delete_table_column(column), to: Tables, as: :delete_column
  defdelegate reorder_table_columns(block_id, ids), to: Tables, as: :reorder_columns
  defdelegate list_table_rows(block_id), to: Tables, as: :list_rows
  defdelegate get_table_row!(id), to: Tables, as: :get_row!
  defdelegate get_table_row(id), to: Tables, as: :get_row
  defdelegate create_table_row(block, attrs), to: Tables, as: :create_row

  defdelegate create_table_row_from_snapshot(block_id, snapshot, cells),
    to: Tables,
    as: :create_row_from_snapshot

  defdelegate update_table_row(row, attrs), to: Tables, as: :update_row
  defdelegate delete_table_row(row), to: Tables, as: :delete_row
  defdelegate reorder_table_rows(block_id, ids), to: Tables, as: :reorder_rows
  defdelegate update_table_cell(row, slug, value), to: Tables, as: :update_cell
  defdelegate update_table_cells(row, cells), to: Tables, as: :update_cells
  defdelegate batch_load_table_data(block_ids), to: Tables

  defdelegate list_gallery_images(block_id), to: GalleryQueries, as: :list
  defdelegate get_gallery_image(id), to: GalleryQueries, as: :get
  defdelegate get_gallery_image_for_sheet(sheet_id, id), to: GalleryQueries, as: :get_for_sheet
  defdelegate add_gallery_image(block, asset_id), to: Galleries
  defdelegate add_gallery_images(block, asset_ids), to: Galleries
  defdelegate remove_gallery_image(sheet_id, id), to: Galleries
  defdelegate update_gallery_image(image, attrs), to: Galleries
  defdelegate reorder_gallery_images(block_id, ids), to: Galleries
  defdelegate batch_load_gallery_data(block_ids), to: GalleryQueries, as: :batch_by_blocks
  defdelegate batch_load_gallery_data_by_sheet(project_id), to: GalleryQueries, as: :batch_by_sheet
  defdelegate get_first_gallery_image(sheet_id), to: GalleryQueries, as: :get_first_for_sheet

  defdelegate list_avatars(sheet_id), to: AvatarQueries, as: :list
  defdelegate get_avatar(id), to: AvatarQueries, as: :get
  defdelegate get_default_avatar(sheet_id), to: AvatarQueries, as: :get_default
  defdelegate add_avatar(sheet, asset_id, attrs \\ %{}), to: Avatars
  defdelegate update_avatar(avatar, attrs), to: Avatars
  defdelegate remove_avatar(sheet_id, avatar_id), to: Avatars
  defdelegate set_avatar_default(avatar), to: Avatars, as: :set_default
  defdelegate reorder_avatars(sheet_id, ids), to: Avatars
  defdelegate batch_load_avatars_by_sheet(project_id), to: AvatarQueries, as: :batch_by_sheet

  defdelegate get_sheet_default_image(sheet), to: DefaultImage, as: :get

  defdelegate record_block_created(scope, sheet, block, creation_method, block_scope),
    to: Events,
    as: :block_created
end
