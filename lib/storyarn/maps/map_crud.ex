defmodule Storyarn.Maps.MapCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Maps.{Map, MapLayer, TreeOperations}
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils
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
  Lists maps as a tree structure.
  Returns root-level maps with their children preloaded recursively.
  """
  def list_maps_tree(project_id) do
    all_maps =
      from(m in Map,
        where: m.project_id == ^project_id and is_nil(m.deleted_at),
        order_by: [asc: m.position, asc: m.name]
      )
      |> Repo.all()

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
      %{map | children: children}
    end)
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
      sanitized = query |> String.replace("\\", "\\\\") |> String.replace("%", "\\%") |> String.replace("_", "\\_")
      search_term = "%#{sanitized}%"

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

  def get_map(project_id, map_id) do
    from(m in Map,
      where: m.project_id == ^project_id and m.id == ^map_id and is_nil(m.deleted_at),
      preload: ^@map_preloads
    )
    |> Repo.one()
  end

  def get_map!(project_id, map_id) do
    from(m in Map,
      where: m.project_id == ^project_id and m.id == ^map_id and is_nil(m.deleted_at),
      preload: ^@map_preloads
    )
    |> Repo.one!()
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
          soft_delete_children(map.project_id, map.id)
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
  def list_deleted_maps(project_id) do
    from(m in Map,
      where: m.project_id == ^project_id and not is_nil(m.deleted_at),
      order_by: [desc: m.deleted_at]
    )
    |> Repo.all()
  end

  def change_map(%Map{} = map, attrs \\ %{}) do
    Map.update_changeset(map, attrs)
  end

  # Private functions

  defp soft_delete_children(project_id, parent_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    children =
      from(m in Map,
        where: m.project_id == ^project_id and m.parent_id == ^parent_id and is_nil(m.deleted_at)
      )
      |> Repo.all()

    Enum.each(children, fn child ->
      from(m in Map, where: m.id == ^child.id)
      |> Repo.update_all(set: [deleted_at: now])

      soft_delete_children(project_id, child.id)
    end)
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
    attrs = stringify_keys(attrs)
    has_shortcut = Elixir.Map.has_key?(attrs, "shortcut")
    name = attrs["name"]

    if has_shortcut || is_nil(name) || name == "" do
      attrs
    else
      shortcut = Shortcuts.generate_map_shortcut(name, project_id, exclude_map_id)
      Elixir.Map.put(attrs, "shortcut", shortcut)
    end
  end

  defp maybe_generate_shortcut_on_update(%Map{} = map, attrs) do
    attrs = stringify_keys(attrs)

    cond do
      Elixir.Map.has_key?(attrs, "shortcut") ->
        attrs

      name_changing?(attrs, map) ->
        shortcut = Shortcuts.generate_map_shortcut(attrs["name"], map.project_id, map.id)
        Elixir.Map.put(attrs, "shortcut", shortcut)

      missing_shortcut?(map) ->
        generate_shortcut_from_current_name(map, attrs)

      true ->
        attrs
    end
  end

  defp name_changing?(attrs, map) do
    new_name = attrs["name"]
    new_name && new_name != "" && new_name != map.name
  end

  defp missing_shortcut?(map) do
    is_nil(map.shortcut) || map.shortcut == ""
  end

  defp generate_shortcut_from_current_name(map, attrs) do
    name = map.name

    if name && name != "" do
      shortcut = Shortcuts.generate_map_shortcut(name, map.project_id, map.id)
      Elixir.Map.put(attrs, "shortcut", shortcut)
    else
      attrs
    end
  end

  defp stringify_keys(map), do: MapUtils.stringify_keys(map)

  defp maybe_assign_position(attrs, project_id, parent_id) do
    if Elixir.Map.has_key?(attrs, "position") do
      attrs
    else
      position = TreeOperations.next_position(project_id, parent_id)
      Elixir.Map.put(attrs, "position", position)
    end
  end
end
