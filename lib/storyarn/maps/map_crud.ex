defmodule Storyarn.Maps.MapCrud do
  @moduledoc """
  CRUD operations for maps with hierarchical tree structure.

  Handles map creation (with auto-shortcut and default layer), updates,
  soft-delete/restore with recursive children handling, tree queries,
  and sidebar element preloading.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Maps.{Map, MapLayer, MapPin, MapZone, TreeOperations}
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.{MapUtils, SearchHelpers, ShortcutHelpers, SoftDelete}
  alias Storyarn.Shortcuts

  @doc """
  Lists all non-deleted maps for a project.
  Returns maps ordered by position then name.
  """
  def list_maps(project_id) do
    from(m in Map,
      where: m.project_id == ^project_id and is_nil(m.deleted_at),
      order_by: [asc: m.position, asc: m.name]
    )
    |> Repo.all()
  end

  @doc """
  Lists maps as a tree structure (without sidebar elements).
  For the map editor sidebar with zone/pin previews, use `list_maps_tree_with_elements/1`.
  """
  def list_maps_tree(project_id) do
    all_maps = base_maps_query(project_id) |> Repo.all()
    build_tree(all_maps)
  end

  defp build_tree(all_maps) do
    grouped = Enum.group_by(all_maps, & &1.parent_id)
    build_subtree(grouped, nil)
  end

  defp build_subtree(grouped, parent_id) do
    (Elixir.Map.get(grouped, parent_id) || [])
    |> Enum.map(fn map ->
      children = build_subtree(grouped, map.id)
      Elixir.Map.put(map, :children, children)
    end)
  end

  @sidebar_element_limit 10

  @doc """
  Lists maps as a tree with limited zone/pin elements for the sidebar.
  Each map gets :sidebar_zones, :sidebar_pins, :zone_count, :pin_count.
  """
  def list_maps_tree_with_elements(project_id) do
    all_maps = base_maps_query(project_id) |> Repo.all()

    map_ids = Enum.map(all_maps, & &1.id)

    zones_by_map = load_sidebar_zones(map_ids)
    pins_by_map = load_sidebar_pins(map_ids)
    zone_counts = count_elements_by_map(MapZone, map_ids)
    pin_counts = count_elements_by_map(MapPin, map_ids)

    all_maps =
      Enum.map(all_maps, fn map ->
        map
        |> Elixir.Map.from_struct()
        |> Elixir.Map.put(:sidebar_zones, Elixir.Map.get(zones_by_map, map.id, []))
        |> Elixir.Map.put(:sidebar_pins, Elixir.Map.get(pins_by_map, map.id, []))
        |> Elixir.Map.put(:zone_count, Elixir.Map.get(zone_counts, map.id, 0))
        |> Elixir.Map.put(:pin_count, Elixir.Map.get(pin_counts, map.id, 0))
      end)

    build_tree(all_maps)
  end

  defp load_sidebar_zones([]), do: %{}

  defp load_sidebar_zones(map_ids) do
    inner =
      from(z in MapZone,
        where: z.map_id in ^map_ids,
        where: not is_nil(z.name) and z.name != "",
        order_by: [asc: z.position, asc: z.name],
        select: %{
          id: z.id,
          name: z.name,
          map_id: z.map_id,
          row: over(row_number(), partition_by: z.map_id, order_by: [asc: z.position])
        }
      )

    from(s in subquery(inner), where: s.row <= ^@sidebar_element_limit)
    |> Repo.all()
    |> Enum.group_by(& &1.map_id)
  end

  defp load_sidebar_pins([]), do: %{}

  defp load_sidebar_pins(map_ids) do
    inner =
      from(p in MapPin,
        where: p.map_id in ^map_ids,
        order_by: [asc: p.position, asc: p.label],
        select: %{
          id: p.id,
          label: p.label,
          map_id: p.map_id,
          row: over(row_number(), partition_by: p.map_id, order_by: [asc: p.position])
        }
      )

    from(s in subquery(inner), where: s.row <= ^@sidebar_element_limit)
    |> Repo.all()
    |> Enum.group_by(& &1.map_id)
  end

  defp count_elements_by_map(_schema, []), do: %{}

  defp count_elements_by_map(schema, map_ids) do
    from(e in schema,
      where: e.map_id in ^map_ids,
      group_by: e.map_id,
      select: {e.map_id, count(e.id)}
    )
    |> Repo.all()
    |> Elixir.Map.new()
  end

  @doc """
  Searches maps by name or shortcut for reference selection.
  Returns maps matching the query, limited to 10 results.
  """
  def search_maps(project_id, query) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      from(m in Map,
        where: m.project_id == ^project_id and is_nil(m.deleted_at),
        order_by: [desc: m.updated_at],
        limit: 10
      )
      |> Repo.all()
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query)}%"

      from(m in Map,
        where: m.project_id == ^project_id and is_nil(m.deleted_at),
        where: ilike(m.name, ^search_term) or ilike(m.shortcut, ^search_term),
        order_by: [asc: m.name],
        limit: 10
      )
      |> Repo.all()
    end
  end

  @map_preloads [
    :layers,
    :zones,
    [pins: [:icon_asset, sheet: :avatar_asset]],
    :annotations,
    :background_asset,
    connections: [:from_pin, :to_pin]
  ]

  @doc """
  Gets a map by project and map ID with all associations preloaded.
  Returns nil if not found or deleted.
  """
  def get_map(project_id, map_id) do
    from(m in Map,
      where: m.project_id == ^project_id and m.id == ^map_id and is_nil(m.deleted_at),
      preload: ^@map_preloads
    )
    |> Repo.one()
  end

  @doc """
  Gets a map by project and map ID with all associations preloaded.
  Raises if not found or deleted.
  """
  def get_map!(project_id, map_id) do
    from(m in Map,
      where: m.project_id == ^project_id and m.id == ^map_id and is_nil(m.deleted_at),
      preload: ^@map_preloads
    )
    |> Repo.one!()
  end

  @doc """
  Gets a map by ID without project scoping (no preloads).
  Used for canvas data enrichment where the map reference is already project-scoped.
  """
  def get_map_by_id(map_id) do
    from(m in Map,
      where: m.id == ^map_id and is_nil(m.deleted_at)
    )
    |> Repo.one()
  end

  @doc """
  Gets a map with only basic fields (no preloads).
  Used for breadcrumbs and lightweight lookups.
  """
  def get_map_brief(project_id, map_id) do
    from(m in Map,
      where: m.project_id == ^project_id and m.id == ^map_id and is_nil(m.deleted_at)
    )
    |> Repo.one()
  end

  @doc """
  Gets a map including soft-deleted ones (for trash/restore).
  """
  def get_map_including_deleted(project_id, map_id) do
    from(m in Map,
      where: m.project_id == ^project_id and m.id == ^map_id,
      preload: [:layers, :zones, :pins, connections: [:from_pin, :to_pin]]
    )
    |> Repo.one()
  end

  @doc """
  Creates a map with auto-generated shortcut and default layer.
  Auto-assigns position if not provided.
  """
  def create_map(%Project{} = project, attrs) do
    # Auto-generate shortcut from name if not provided
    attrs = maybe_generate_shortcut(attrs, project.id, nil)

    # Auto-assign position if not provided
    parent_id = attrs["parent_id"]
    attrs = maybe_assign_position(attrs, project.id, parent_id)

    Repo.transaction(fn ->
      case %Map{project_id: project.id}
           |> Map.create_changeset(attrs)
           |> Repo.insert() do
        {:ok, map} ->
          # Auto-create default layer
          %MapLayer{map_id: map.id}
          |> MapLayer.create_changeset(%{name: "Default", is_default: true, position: 0})
          |> Repo.insert!()

          map

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Updates a map. Regenerates shortcut if name changes.
  """
  def update_map(%Map{} = map, attrs) do
    attrs = maybe_generate_shortcut_on_update(map, attrs)

    map
    |> Map.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft-deletes a map by setting deleted_at.
  Also soft-deletes all children recursively.
  """
  def delete_map(%Map{} = map) do
    Repo.transaction(fn ->
      # Soft delete the map itself
      case map |> Map.delete_changeset() |> Repo.update() do
        {:ok, deleted_map} ->
          # Also soft-delete all children recursively
          SoftDelete.soft_delete_children(Map, map.project_id, map.id)
          deleted_map

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Permanently deletes a map from the database.
  Use with caution - this cannot be undone.
  """
  def hard_delete_map(%Map{} = map) do
    Repo.delete(map)
  end

  @doc """
  Restores a soft-deleted map.
  """
  def restore_map(%Map{} = map) do
    Repo.transaction(fn ->
      case map |> Map.restore_changeset() |> Repo.update() do
        {:ok, restored_map} ->
          restore_children(map.project_id, map.id, map.deleted_at)
          restored_map

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Lists all soft-deleted maps for a project (trash).
  """
  def list_deleted_maps(project_id), do: SoftDelete.list_deleted(Map, project_id)

  @max_ancestor_depth 50

  @doc """
  Returns ancestors from root to direct parent, ordered top-down.
  """
  def list_ancestors(map) do
    do_collect_ancestors(map.parent_id, [], MapSet.new(), 0)
  end

  defp do_collect_ancestors(nil, acc, _visited, _depth), do: acc
  defp do_collect_ancestors(_id, acc, _visited, depth) when depth > @max_ancestor_depth, do: acc

  defp do_collect_ancestors(parent_id, acc, visited, depth) do
    if MapSet.member?(visited, parent_id) do
      acc
    else
      case Repo.get(Map, parent_id) do
        nil ->
          acc

        parent ->
          do_collect_ancestors(
            parent.parent_id,
            [parent | acc],
            MapSet.put(visited, parent_id),
            depth + 1
          )
      end
    end
  end

  @doc """
  Returns a changeset for tracking map form changes.
  """
  def change_map(%Map{} = map, attrs \\ %{}) do
    Map.update_changeset(map, attrs)
  end

  # Private functions

  defp base_maps_query(project_id) do
    from(m in Map,
      where: m.project_id == ^project_id and is_nil(m.deleted_at),
      order_by: [asc: m.position, asc: m.name]
    )
  end

  defp restore_children(project_id, parent_id, since) do
    # Only restore children that were deleted at the same time as the parent
    # (within 1 second), to avoid restoring children deleted independently.
    since_threshold = DateTime.add(since, -1, :second)

    children =
      from(m in Map,
        where:
          m.project_id == ^project_id and
            m.parent_id == ^parent_id and
            not is_nil(m.deleted_at) and
            m.deleted_at >= ^since_threshold
      )
      |> Repo.all()

    Enum.each(children, fn child ->
      from(m in Map, where: m.id == ^child.id)
      |> Repo.update_all(set: [deleted_at: nil])

      restore_children(project_id, child.id, since)
    end)
  end

  defp maybe_generate_shortcut(attrs, project_id, exclude_map_id) do
    attrs
    |> stringify_keys()
    |> ShortcutHelpers.maybe_generate_shortcut(
      project_id,
      exclude_map_id,
      &Shortcuts.generate_map_shortcut/3
    )
  end

  defp maybe_generate_shortcut_on_update(%Map{} = map, attrs) do
    ShortcutHelpers.maybe_generate_shortcut_on_update(
      map,
      attrs,
      &Shortcuts.generate_map_shortcut/3
    )
  end

  defp stringify_keys(map), do: MapUtils.stringify_keys(map)

  @doc """
  Gets a map with only background_asset preloaded.
  Used for rendering scene backdrops in the flow player.
  """
  def get_map_backdrop(map_id) do
    from(m in Map,
      where: m.id == ^map_id and is_nil(m.deleted_at),
      preload: [:background_asset]
    )
    |> Repo.one()
  end

  @doc """
  Returns the project_id for a given map_id.
  Used by reference trackers that need the project scope from a map.
  """
  def get_map_project_id(map_id) do
    from(m in Map, where: m.id == ^map_id, select: m.project_id)
    |> Repo.one()
  end

  defp maybe_assign_position(attrs, project_id, parent_id) do
    ShortcutHelpers.maybe_assign_position(
      attrs,
      project_id,
      parent_id,
      &TreeOperations.next_position/2
    )
  end
end
