defmodule StoryarnWeb.SheetLive.Helpers.PropsSerializer do
  @moduledoc """
  Pure functions to serialize Elixir data structures into component-ready props.
  """

  alias Storyarn.Assets
  alias Storyarn.Sheets

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
              url: Assets.display_url(a.asset),
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
      |> Enum.map(& &1.id)
      |> MapSet.new()

    raw =
      blocks
      |> Enum.sort_by(& &1.position)
      |> prepare_blocks_for_vue_raw(gallery_data, table_data, project_id)
      |> Enum.map(fn b ->
        Map.put(b, :can_reattach, MapSet.member?(can_reattach_ids, b.id))
      end)

    raw
    |> Enum.chunk_by(& &1.column_group_id)
    |> Enum.flat_map(fn chunk ->
      case chunk do
        [%{column_group_id: nil} | _] ->
          Enum.map(chunk, fn b -> %{type: "full_width", block: b} end)

        [%{column_group_id: gid} | _] when not is_nil(gid) ->
          sorted = Enum.sort_by(chunk, & &1.column_index)
          [%{type: "column_group", group_id: gid, blocks: sorted, column_count: length(sorted)}]

        other ->
          Enum.map(other, fn b -> %{type: "full_width", block: b} end)
      end
    end)
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

  defp banner_url(%{banner_asset: %{} = asset}), do: Assets.display_url(asset)
  defp banner_url(_), do: nil

  defp extract_avatar_url(%{avatars: avatars}) when is_list(avatars) do
    case Enum.find(avatars, & &1.is_default) || List.first(avatars) do
      %{asset: %{url: url}} when is_binary(url) -> url
      _ -> nil
    end
  end

  defp extract_avatar_url(_), do: nil

  defp prepare_blocks_for_vue_raw(blocks, gallery_data, table_data, project_id) do
    Enum.map(blocks, fn b ->
      base = %{
        id: b.id,
        type: b.type,
        position: b.position,
        is_constant: b.is_constant,
        variable_name: b.variable_name,
        scope: b.scope || "self",
        inherited: b.inherited_from_block_id != nil && !b.detached,
        detached: b.detached || false,
        required: b.required || false,
        column_group_id: b.column_group_id,
        column_index: b.column_index || 0,
        config: b.config || %{},
        value: b.value || %{}
      }

      cond do
        b.type == "gallery" ->
          images =
            Map.get(gallery_data, b.id, [])
            |> Enum.map(fn gi ->
              %{
                id: gi.id,
                url: Assets.display_url(gi.asset),
                label: gi.label,
                description: gi.description
              }
            end)

          Map.put(base, :gallery_images, images)

        b.type == "table" ->
          td = Map.get(table_data, b.id, %{columns: [], rows: []})

          columns =
            Enum.map(td.columns, fn c ->
              %{
                id: c.id,
                name: c.name,
                slug: c.slug,
                type: c.type,
                position: c.position,
                is_constant: c.is_constant,
                required: c.required,
                config: c.config || %{}
              }
            end)

          rows =
            Enum.map(td.rows, fn r ->
              %{id: r.id, name: r.name, slug: r.slug, position: r.position, cells: r.cells || %{}}
            end)

          collapsed = get_in(b.config, ["collapsed"]) || false

          base
          |> Map.put(:columns, columns)
          |> Map.put(:rows, rows)
          |> Map.put(:collapsed, collapsed)

        b.type == "reference" ->
          target_type = get_in(b.value, ["target_type"])
          target_id = get_in(b.value, ["target_id"])

          reference_target =
            if target_type && target_id && project_id do
              Sheets.get_reference_target(target_type, target_id, project_id)
            end

          Map.put(base, :reference_target, reference_target)

        true ->
          base
      end
    end)
  end
end
