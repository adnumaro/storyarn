defmodule StoryarnWeb.SheetLive.Helpers.PropsSerializer do
  @moduledoc """
  Pure functions to serialize Elixir data structures into component-ready props.
  """

  alias Storyarn.Sheets
  alias StoryarnWeb.PrivateMedia

  def prepare_sheet_for_vue(nil), do: nil

  def prepare_sheet_for_vue(sheet) do
    avatars =
      case sheet.avatars do
        list when is_list(list) ->
          list
          |> Enum.sort_by(& &1.position)
          |> Enum.map(fn a ->
            %{
              id: a.id,
              url: PrivateMedia.asset_url(a.asset),
              name: a.name,
              notes: a.notes,
              is_default: a.is_default
            }
          end)

        _ ->
          []
      end

    %{
      id: sheet.id,
      name: sheet.name,
      shortcut: sheet.shortcut,
      color: sheet.color,
      bannerUrl: banner_url(sheet),
      avatars: avatars
    }
  end

  def prepare_inherited_groups_for_vue(groups, gallery_data, table_data, project_id) do
    Enum.map(groups, fn group ->
      %{
        sourceSheet: %{
          id: group.source_sheet.id,
          name: group.source_sheet.name
        },
        blocks: prepare_blocks_for_vue_raw(group.blocks, gallery_data, table_data, project_id)
      }
    end)
  end

  def prepare_blocks_for_vue(blocks, gallery_data, table_data, project_id, inherited_groups) do
    reattachable_source_ids =
      inherited_groups
      |> Enum.flat_map(fn g -> Enum.map(g.blocks, & &1.inherited_from_block_id) end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    can_reattach_ids =
      blocks
      |> Enum.filter(fn b ->
        (b.detached || false) && b.inherited_from_block_id &&
          MapSet.member?(reattachable_source_ids, b.inherited_from_block_id)
      end)
      |> MapSet.new(& &1.id)

    raw =
      blocks
      |> Enum.sort_by(& &1.position)
      |> prepare_blocks_for_vue_raw(gallery_data, table_data, project_id)
      |> Enum.map(fn b ->
        Map.put(b, :can_reattach, MapSet.member?(can_reattach_ids, b.id))
      end)

    raw
    |> Enum.chunk_by(& &1.column_group_id)
    |> Enum.flat_map(&serialize_layout_chunk/1)
  end

  def serialize_block_locks(locks) when is_map(locks) do
    Map.new(locks, fn {entity_id, lock} ->
      {to_string(entity_id),
       %{
         userId: lock.user_id,
         userEmail: lock.user_email,
         userColor: lock.user_color
       }}
    end)
  end

  def serialize_block_locks(_), do: %{}

  def prepare_tree(nodes) do
    Enum.map(nodes, fn node ->
      %{
        id: node.id,
        name: node.name,
        avatar_url: extract_avatar_url(node),
        children: prepare_tree(Map.get(node, :children, []))
      }
    end)
  end

  # Private

  defp banner_url(%{banner_asset: %{} = asset}), do: PrivateMedia.asset_url(asset)
  defp banner_url(_), do: nil

  defp extract_avatar_url(%{avatars: avatars}) when is_list(avatars) do
    case Enum.find(avatars, & &1.is_default) || List.first(avatars) do
      %{asset: asset} -> PrivateMedia.asset_url(asset)
      _ -> nil
    end
  end

  defp extract_avatar_url(_), do: nil

  defp prepare_blocks_for_vue_raw(blocks, gallery_data, table_data, project_id) do
    Enum.map(blocks, &prepare_block_for_vue(&1, gallery_data, table_data, project_id))
  end

  defp serialize_layout_chunk([%{column_group_id: nil} | _] = chunk) do
    Enum.map(chunk, &full_width_layout_item/1)
  end

  defp serialize_layout_chunk([%{column_group_id: group_id} | _] = chunk) when not is_nil(group_id) do
    sorted = Enum.sort_by(chunk, & &1.column_index)
    [%{type: "column_group", group_id: group_id, blocks: sorted, column_count: length(sorted)}]
  end

  defp serialize_layout_chunk(chunk) do
    Enum.map(chunk, &full_width_layout_item/1)
  end

  defp full_width_layout_item(block), do: %{type: "full_width", block: block}

  defp prepare_block_for_vue(block, gallery_data, table_data, project_id) do
    block
    |> base_block_props()
    |> add_type_specific_block_props(block, gallery_data, table_data, project_id)
  end

  defp base_block_props(block) do
    %{
      id: block.id,
      type: block.type,
      position: block.position,
      is_constant: block.is_constant,
      variable_name: block.variable_name,
      scope: block.scope || "self",
      inherited: block.inherited_from_block_id != nil && !block.detached,
      detached: block.detached || false,
      required: block.required || false,
      column_group_id: block.column_group_id,
      column_index: block.column_index || 0,
      config: block.config || %{},
      value: block.value || %{}
    }
  end

  defp add_type_specific_block_props(base, %{type: "gallery"} = block, gallery_data, _table_data, _project_id) do
    images =
      gallery_data
      |> Map.get(block.id, [])
      |> Enum.map(&serialize_gallery_image/1)

    Map.put(base, :gallery_images, images)
  end

  defp add_type_specific_block_props(base, %{type: "table"} = block, _gallery_data, table_data, _project_id) do
    table = Map.get(table_data, block.id, %{columns: [], rows: []})

    base
    |> Map.put(:columns, Enum.map(table.columns, &serialize_table_column/1))
    |> Map.put(:rows, Enum.map(table.rows, &serialize_table_row/1))
    |> Map.put(:collapsed, get_in(block.config, ["collapsed"]) || false)
  end

  defp add_type_specific_block_props(base, %{type: "reference"} = block, _gallery_data, _table_data, project_id) do
    target_type = get_in(block.value, ["target_type"])
    target_id = get_in(block.value, ["target_id"])

    Map.put(base, :reference_target, reference_target(target_type, target_id, project_id))
  end

  defp add_type_specific_block_props(base, _block, _gallery_data, _table_data, _project_id), do: base

  defp serialize_gallery_image(gallery_image) do
    %{
      id: gallery_image.id,
      url: PrivateMedia.asset_url(gallery_image.asset),
      label: gallery_image.label,
      description: gallery_image.description
    }
  end

  defp serialize_table_column(column) do
    %{
      id: column.id,
      name: column.name,
      slug: column.slug,
      type: column.type,
      position: column.position,
      is_constant: column.is_constant,
      required: column.required,
      config: column.config || %{}
    }
  end

  defp serialize_table_row(row) do
    %{id: row.id, name: row.name, slug: row.slug, position: row.position, cells: row.cells || %{}}
  end

  defp reference_target(target_type, target_id, project_id)
       when not is_nil(target_type) and not is_nil(target_id) and not is_nil(project_id) do
    Sheets.get_reference_target(target_type, target_id, project_id)
  end

  defp reference_target(_target_type, _target_id, _project_id), do: nil
end
