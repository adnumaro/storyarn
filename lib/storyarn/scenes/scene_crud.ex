defmodule Storyarn.Scenes.SceneCrud do
  @moduledoc """
  CRUD operations for scenes with hierarchical tree structure.

  Handles scene creation (with auto-shortcut and default layer), updates,
  soft-delete/restore with recursive children handling, tree queries,
  and sidebar element preloading.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Scenes.{Scene, SceneLayer, ScenePin, SceneZone, TreeOperations}
  alias Storyarn.Shared.{MapUtils, SearchHelpers, ShortcutHelpers, SoftDelete}
  alias Storyarn.Shortcuts

  @doc """
  Lists all non-deleted scenes for a project.
  Returns scenes ordered by position then name.
  """
  def list_scenes(project_id) do
    from(m in Scene,
      where: m.project_id == ^project_id and is_nil(m.deleted_at),
      order_by: [asc: m.position, asc: m.name]
    )
    |> Repo.all()
  end

  @doc """
  Lists scenes as a tree structure (without sidebar elements).
  For the scene editor sidebar with zone/pin previews, use `list_scenes_tree_with_elements/1`.
  """
  def list_scenes_tree(project_id) do
    all_scenes = base_scenes_query(project_id) |> Repo.all()
    build_tree(all_scenes)
  end

  defp build_tree(all_scenes) do
    grouped = Enum.group_by(all_scenes, & &1.parent_id)
    build_subtree(grouped, nil)
  end

  defp build_subtree(grouped, parent_id) do
    (Elixir.Map.get(grouped, parent_id) || [])
    |> Enum.map(fn scene ->
      children = build_subtree(grouped, scene.id)
      Elixir.Map.put(scene, :children, children)
    end)
  end

  @sidebar_element_limit 10

  @doc """
  Lists scenes as a tree with limited zone/pin elements for the sidebar.
  Each scene gets :sidebar_zones, :sidebar_pins, :zone_count, :pin_count.
  """
  def list_scenes_tree_with_elements(project_id) do
    all_scenes = base_scenes_query(project_id) |> Repo.all()

    scene_ids = Enum.map(all_scenes, & &1.id)

    zones_by_scene = load_sidebar_zones(scene_ids)
    pins_by_scene = load_sidebar_pins(scene_ids)
    zone_counts = count_elements_by_scene(SceneZone, scene_ids)
    pin_counts = count_elements_by_scene(ScenePin, scene_ids)

    all_scenes =
      Enum.map(all_scenes, fn scene ->
        scene
        |> Elixir.Map.from_struct()
        |> Elixir.Map.put(:sidebar_zones, Elixir.Map.get(zones_by_scene, scene.id, []))
        |> Elixir.Map.put(:sidebar_pins, Elixir.Map.get(pins_by_scene, scene.id, []))
        |> Elixir.Map.put(:zone_count, Elixir.Map.get(zone_counts, scene.id, 0))
        |> Elixir.Map.put(:pin_count, Elixir.Map.get(pin_counts, scene.id, 0))
      end)

    build_tree(all_scenes)
  end

  defp load_sidebar_zones([]), do: %{}

  defp load_sidebar_zones(scene_ids) do
    inner =
      from(z in SceneZone,
        where: z.scene_id in ^scene_ids,
        where: not is_nil(z.name) and z.name != "",
        order_by: [asc: z.position, asc: z.name],
        select: %{
          id: z.id,
          name: z.name,
          scene_id: z.scene_id,
          row: over(row_number(), partition_by: z.scene_id, order_by: [asc: z.position])
        }
      )

    from(s in subquery(inner), where: s.row <= ^@sidebar_element_limit)
    |> Repo.all()
    |> Enum.group_by(& &1.scene_id)
  end

  defp load_sidebar_pins([]), do: %{}

  defp load_sidebar_pins(scene_ids) do
    inner =
      from(p in ScenePin,
        where: p.scene_id in ^scene_ids,
        order_by: [asc: p.position, asc: p.label],
        select: %{
          id: p.id,
          label: p.label,
          scene_id: p.scene_id,
          row: over(row_number(), partition_by: p.scene_id, order_by: [asc: p.position])
        }
      )

    from(s in subquery(inner), where: s.row <= ^@sidebar_element_limit)
    |> Repo.all()
    |> Enum.group_by(& &1.scene_id)
  end

  defp count_elements_by_scene(_schema, []), do: %{}

  defp count_elements_by_scene(schema, scene_ids) do
    from(e in schema,
      where: e.scene_id in ^scene_ids,
      group_by: e.scene_id,
      select: {e.scene_id, count(e.id)}
    )
    |> Repo.all()
    |> Elixir.Map.new()
  end

  @doc """
  Searches scenes by name or shortcut for reference selection.
  Returns scenes matching the query, limited to 10 results.
  """
  def search_scenes(project_id, query) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      from(m in Scene,
        where: m.project_id == ^project_id and is_nil(m.deleted_at),
        order_by: [desc: m.updated_at],
        limit: 10
      )
      |> Repo.all()
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query)}%"

      from(m in Scene,
        where: m.project_id == ^project_id and is_nil(m.deleted_at),
        where: ilike(m.name, ^search_term) or ilike(m.shortcut, ^search_term),
        order_by: [asc: m.name],
        limit: 10
      )
      |> Repo.all()
    end
  end

  @scene_preloads [
    :layers,
    :zones,
    [pins: [:icon_asset, sheet: :avatar_asset]],
    :annotations,
    :background_asset,
    connections: [:from_pin, :to_pin]
  ]

  @doc """
  Gets a scene by project and scene ID with all associations preloaded.
  Returns nil if not found or deleted.
  """
  def get_scene(project_id, scene_id) do
    from(m in Scene,
      where: m.project_id == ^project_id and m.id == ^scene_id and is_nil(m.deleted_at),
      preload: ^@scene_preloads
    )
    |> Repo.one()
  end

  @doc """
  Gets a scene by project and scene ID with all associations preloaded.
  Raises if not found or deleted.
  """
  def get_scene!(project_id, scene_id) do
    from(m in Scene,
      where: m.project_id == ^project_id and m.id == ^scene_id and is_nil(m.deleted_at),
      preload: ^@scene_preloads
    )
    |> Repo.one!()
  end

  @doc """
  Gets a scene by ID without project scoping (no preloads).
  Used for canvas data enrichment where the scene reference is already project-scoped.
  """
  def get_scene_by_id(scene_id) do
    from(m in Scene,
      where: m.id == ^scene_id and is_nil(m.deleted_at)
    )
    |> Repo.one()
  end

  @doc """
  Gets a scene with only basic fields (no preloads).
  Used for breadcrumbs and lightweight lookups.
  """
  def get_scene_brief(project_id, scene_id) do
    from(m in Scene,
      where: m.project_id == ^project_id and m.id == ^scene_id and is_nil(m.deleted_at)
    )
    |> Repo.one()
  end

  @doc """
  Gets a scene including soft-deleted ones (for trash/restore).
  """
  def get_scene_including_deleted(project_id, scene_id) do
    from(m in Scene,
      where: m.project_id == ^project_id and m.id == ^scene_id,
      preload: [:layers, :zones, :pins, connections: [:from_pin, :to_pin]]
    )
    |> Repo.one()
  end

  @doc """
  Creates a scene with auto-generated shortcut and default layer.
  Auto-assigns position if not provided.
  """
  def create_scene(%Project{} = project, attrs) do
    # Auto-generate shortcut from name if not provided
    attrs = maybe_generate_shortcut(attrs, project.id, nil)

    # Auto-assign position if not provided
    parent_id = attrs["parent_id"]
    attrs = maybe_assign_position(attrs, project.id, parent_id)

    Repo.transaction(fn ->
      case %Scene{project_id: project.id}
           |> Scene.create_changeset(attrs)
           |> Repo.insert() do
        {:ok, scene} ->
          # Auto-create default layer
          %SceneLayer{scene_id: scene.id}
          |> SceneLayer.create_changeset(%{name: "Default", is_default: true, position: 0})
          |> Repo.insert!()

          scene

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Updates a scene. Regenerates shortcut if name changes.
  """
  def update_scene(%Scene{} = scene, attrs) do
    attrs = maybe_generate_shortcut_on_update(scene, attrs)

    scene
    |> Scene.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft-deletes a scene by setting deleted_at.
  Also soft-deletes all children recursively.
  """
  def delete_scene(%Scene{} = scene) do
    Repo.transaction(fn ->
      # Soft delete the scene itself
      case scene |> Scene.delete_changeset() |> Repo.update() do
        {:ok, deleted_scene} ->
          # Also soft-delete all children recursively
          SoftDelete.soft_delete_children(Scene, scene.project_id, scene.id)
          deleted_scene

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Permanently deletes a scene from the database.
  Use with caution - this cannot be undone.
  """
  def hard_delete_scene(%Scene{} = scene) do
    Repo.delete(scene)
  end

  @doc """
  Restores a soft-deleted scene.
  """
  def restore_scene(%Scene{} = scene) do
    Repo.transaction(fn ->
      case scene |> Scene.restore_changeset() |> Repo.update() do
        {:ok, restored_scene} ->
          restore_children(scene.project_id, scene.id, scene.deleted_at)
          restored_scene

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Lists all soft-deleted scenes for a project (trash).
  """
  def list_deleted_scenes(project_id), do: SoftDelete.list_deleted(Scene, project_id)

  @doc """
  Returns ancestors from root to direct parent, ordered top-down.
  Uses a recursive CTE for O(1) queries regardless of tree depth.
  """
  def list_ancestors(%Scene{parent_id: nil}), do: []

  def list_ancestors(%Scene{id: scene_id}) do
    anchor =
      from(m in "scenes",
        where: m.id == ^scene_id and is_nil(m.deleted_at),
        select: %{parent_id: m.parent_id, depth: 0}
      )

    recursion =
      from(m in "scenes",
        join: a in "ancestors",
        on: m.id == a.parent_id,
        where: is_nil(m.deleted_at),
        select: %{parent_id: m.parent_id, depth: a.depth + 1}
      )

    cte_query = anchor |> union_all(^recursion)

    # Get ordered ancestor IDs from the CTE (child-first order)
    ancestor_ids =
      from("ancestors")
      |> recursive_ctes(true)
      |> with_cte("ancestors", as: ^cte_query)
      |> where([a], not is_nil(a.parent_id))
      |> select([a], a.parent_id)
      |> Repo.all()

    if ancestor_ids == [] do
      []
    else
      ancestors_map =
        from(m in Scene,
          where: m.id in ^ancestor_ids and is_nil(m.deleted_at)
        )
        |> Repo.all()
        |> Elixir.Map.new(fn m -> {m.id, m} end)

      # CTE returns child-first; reverse for root-first (top-down) order
      ancestor_ids
      |> Enum.map(&Elixir.Map.get(ancestors_map, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.reverse()
    end
  end

  @doc """
  Returns a changeset for tracking scene form changes.
  """
  def change_scene(%Scene{} = scene, attrs \\ %{}) do
    Scene.update_changeset(scene, attrs)
  end

  # Private functions

  defp base_scenes_query(project_id) do
    from(m in Scene,
      where: m.project_id == ^project_id and is_nil(m.deleted_at),
      order_by: [asc: m.position, asc: m.name]
    )
  end

  defp restore_children(project_id, parent_id, since) do
    # Only restore children that were deleted at the same time as the parent
    # (within 1 second), to avoid restoring children deleted independently.
    since_threshold = DateTime.add(since, -1, :second)

    children =
      from(m in Scene,
        where:
          m.project_id == ^project_id and
            m.parent_id == ^parent_id and
            not is_nil(m.deleted_at) and
            m.deleted_at >= ^since_threshold
      )
      |> Repo.all()

    Enum.each(children, fn child ->
      from(m in Scene, where: m.id == ^child.id)
      |> Repo.update_all(set: [deleted_at: nil])

      restore_children(project_id, child.id, since)
    end)
  end

  defp maybe_generate_shortcut(attrs, project_id, exclude_scene_id) do
    attrs
    |> stringify_keys()
    |> ShortcutHelpers.maybe_generate_shortcut(
      project_id,
      exclude_scene_id,
      &Shortcuts.generate_scene_shortcut/3
    )
  end

  defp maybe_generate_shortcut_on_update(%Scene{} = scene, attrs) do
    ShortcutHelpers.maybe_generate_shortcut_on_update(
      scene,
      attrs,
      &Shortcuts.generate_scene_shortcut/3
    )
  end

  defp stringify_keys(attrs), do: MapUtils.stringify_keys(attrs)

  @doc """
  Gets a scene with only background_asset preloaded.
  Used for rendering scene backdrops in the flow player.
  """
  def get_scene_backdrop(scene_id) do
    from(m in Scene,
      where: m.id == ^scene_id and is_nil(m.deleted_at),
      preload: [:background_asset]
    )
    |> Repo.one()
  end

  @doc """
  Returns the project_id for a given scene_id.
  Used by reference trackers that need the project scope from a scene.
  """
  def get_scene_project_id(scene_id) do
    from(m in Scene, where: m.id == ^scene_id, select: m.project_id)
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
