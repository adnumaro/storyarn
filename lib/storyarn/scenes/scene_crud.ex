defmodule Storyarn.Scenes.SceneCrud do
  @moduledoc """
  CRUD operations for scenes with hierarchical tree structure.

  Handles scene creation (with auto-shortcut and default layer), updates,
  soft-delete/restore with recursive children handling, tree queries,
  and sidebar element preloading.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneReferenceIntegrity
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Scenes.TreeOperations
  alias Storyarn.Shared.ImportHelpers
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Shared.SearchHelpers
  alias Storyarn.Shared.ShortcutHelpers
  alias Storyarn.Shared.SoftDelete
  alias Storyarn.Shared.TreeOperations, as: SharedTree
  alias Storyarn.Shortcuts

  @doc """
  Lists all non-deleted scenes for a project.
  Returns scenes ordered by position then name.
  """
  def list_scenes(project_id) do
    Repo.all(
      from(m in Scene,
        where: m.project_id == ^project_id and is_nil(m.deleted_at),
        order_by: [asc: m.position, asc: m.name]
      )
    )
  end

  @doc """
  Lists scenes as a tree structure (without sidebar elements).
  For the scene editor sidebar with zone/pin previews, use `list_scenes_tree_with_elements/1`.
  """
  def list_scenes_tree(project_id) do
    all_scenes = project_id |> base_scenes_query() |> Repo.all()
    SharedTree.build_tree_from_flat_list(all_scenes)
  end

  @sidebar_element_limit 10

  @doc """
  Lists scenes as a tree with limited zone/pin elements for the sidebar.
  Each scene gets :sidebar_zones, :sidebar_pins, :zone_count, :pin_count.
  """
  def list_scenes_tree_with_elements(project_id) do
    all_scenes = project_id |> base_scenes_query() |> Repo.all()

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

    SharedTree.build_tree_from_flat_list(all_scenes)
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

  @default_search_limit 20

  @doc """
  Searches scenes by name or shortcut across a pre-authorized set of projects.

  Callers OWN the authorization of `project_ids` (see `Storyarn.GlobalSearch`);
  this function never widens the set. Empty queries return no results — the
  cross-project variant is a search surface, not a browsing one.
  """
  @spec search_scenes_in_projects([integer()], String.t(), keyword()) :: [Scene.t()]
  def search_scenes_in_projects(project_ids, query, opts \\ []) when is_list(project_ids) and is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_search_limit)
    query_str = String.trim(query)

    if project_ids == [] or query_str == "" do
      []
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query_str)}%"

      Repo.all(
        from(m in Scene,
          where: m.project_id in ^project_ids and is_nil(m.deleted_at),
          where: ilike(m.name, ^search_term) or ilike(m.shortcut, ^search_term),
          order_by: [asc: m.name],
          limit: ^limit
        )
      )
    end
  end

  @doc """
  Searches scenes by name or shortcut for reference selection.

  ## Options
    - `:limit` - Max results (default #{@default_search_limit})
    - `:offset` - Skip N results (default 0)
  """
  def search_scenes(project_id, query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_search_limit)
    offset = Keyword.get(opts, :offset, 0)
    query_str = String.trim(query)

    if query_str == "" do
      Repo.all(
        from(m in Scene,
          where: m.project_id == ^project_id and is_nil(m.deleted_at),
          order_by: [desc: m.updated_at],
          limit: ^limit,
          offset: ^offset
        )
      )
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query_str)}%"

      Repo.all(
        from(m in Scene,
          where: m.project_id == ^project_id and is_nil(m.deleted_at),
          where: ilike(m.name, ^search_term) or ilike(m.shortcut, ^search_term),
          order_by: [asc: m.name],
          limit: ^limit,
          offset: ^offset
        )
      )
    end
  end

  @scene_preloads [
    :layers,
    [zones: [:label_icon_asset]],
    [pins: [:icon_asset, sheet: [avatars: :asset]]],
    :annotations,
    :background_asset,
    connections: [:from_pin, :to_pin]
  ]

  @doc """
  Gets a scene by project and scene ID with all associations preloaded.
  Returns nil if not found or deleted.
  """
  def get_scene(project_id, scene_id) do
    Repo.one(
      from(m in Scene,
        where: m.project_id == ^project_id and m.id == ^scene_id and is_nil(m.deleted_at),
        preload: ^@scene_preloads
      )
    )
  end

  @doc """
  Gets a scene by project and scene ID with all associations preloaded.
  Raises if not found or deleted.
  """
  def get_scene!(project_id, scene_id) do
    Repo.one!(
      from(m in Scene,
        where: m.project_id == ^project_id and m.id == ^scene_id and is_nil(m.deleted_at),
        preload: ^@scene_preloads
      )
    )
  end

  @doc """
  Gets a scene by ID without project scoping (no preloads).
  Used for canvas data enrichment where the scene reference is already project-scoped.
  """
  def get_scene_by_id(scene_id) do
    Repo.one(from(m in Scene, where: m.id == ^scene_id and is_nil(m.deleted_at)))
  end

  @doc """
  Gets a scene with only basic fields (no preloads).
  Used for breadcrumbs and lightweight lookups.
  """
  def get_scene_brief(project_id, scene_id) do
    Repo.one(from(m in Scene, where: m.project_id == ^project_id and m.id == ^scene_id and is_nil(m.deleted_at)))
  end

  @doc """
  Gets a scene including soft-deleted ones (for trash/restore).
  """
  def get_scene_including_deleted(project_id, scene_id) do
    Repo.one(
      from(m in Scene,
        where: m.project_id == ^project_id and m.id == ^scene_id,
        preload: [:layers, :zones, :pins, connections: [:from_pin, :to_pin]]
      )
    )
  end

  @doc """
  Creates a scene with auto-generated shortcut and default layer.
  Auto-assigns position if not provided.
  """
  def create_scene(%Project{} = project, attrs) do
    result = do_create_scene(project, attrs)

    case result do
      {:ok, _scene} ->
        Collaboration.broadcast_dashboard_change(project.id, :scenes)

      _ ->
        :ok
    end

    result
  end

  defp do_create_scene(project, attrs) do
    fn -> create_scene_transaction(project, attrs) end
    |> Repo.transaction()
    |> normalize_item_limit_result()
  end

  defp create_scene_transaction(project, attrs) do
    with {:ok, locked_project} <-
           SceneReferenceIntegrity.lock_active_project(project.id, :update),
         :ok <- Billing.can_create_item?(locked_project),
         attrs = maybe_generate_shortcut(attrs, locked_project.id, nil),
         {:ok, attrs} <-
           SceneReferenceIntegrity.lock_scene_root_references(
             %Scene{project_id: locked_project.id},
             attrs
           ) do
      attrs = maybe_assign_position(attrs, locked_project.id, attrs["parent_id"])
      insert_scene_with_default_layer(locked_project.id, attrs)
    else
      {:error, reason, details} -> Repo.rollback({reason, details})
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp insert_scene_with_default_layer(project_id, attrs) do
    case %Scene{project_id: project_id}
         |> Scene.create_changeset(attrs)
         |> Repo.insert() do
      {:ok, scene} ->
        %SceneLayer{scene_id: scene.id}
        |> SceneLayer.create_changeset(%{name: "Default", is_default: true, position: 0})
        |> Repo.insert!()

        scene

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp normalize_item_limit_result({:error, {:limit_reached, details}}), do: {:error, :limit_reached, details}

  defp normalize_item_limit_result(result), do: result

  @doc """
  Updates a scene. Regenerates shortcut if name changes.
  """
  def update_scene(%Scene{} = scene, attrs) do
    SceneReferenceIntegrity.with_active_scene_lock(
      scene.id,
      [project_lock: :update],
      fn locked_scene ->
        attrs = maybe_generate_shortcut_on_update(locked_scene, attrs)

        with {:ok, attrs} <-
               SceneReferenceIntegrity.lock_scene_root_references(
                 locked_scene,
                 attrs
               ),
             {:ok, updated_scene} <-
               locked_scene
               |> Scene.update_changeset(attrs)
               |> Repo.update() do
          {:ok, Repo.preload(updated_scene, @scene_preloads, force: true)}
        end
      end
    )
  end

  @doc """
  Soft-deletes a scene by setting deleted_at.
  Also soft-deletes all children recursively.
  """
  def delete_scene(%Scene{} = scene) do
    result =
      SceneReferenceIntegrity.with_active_scene_lock(
        scene.id,
        [project_lock: :update],
        fn locked_scene ->
          case locked_scene |> Scene.delete_changeset() |> Repo.update() do
            {:ok, deleted_scene} ->
              SoftDelete.soft_delete_children(
                Scene,
                locked_scene.project_id,
                locked_scene.id
              )

              {:ok, deleted_scene}

            {:error, changeset} ->
              {:error, changeset}
          end
        end
      )

    case result do
      {:ok, deleted_scene} ->
        Collaboration.broadcast_dashboard_change(deleted_scene.project_id, :scenes)

      _ ->
        :ok
    end

    result
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
  def restore_scene(%Scene{id: scene_id}) when is_integer(scene_id) do
    Repo.transaction(fn ->
      project_id =
        Repo.one(from(scene in Scene, where: scene.id == ^scene_id, select: scene.project_id)) ||
          Repo.rollback(:scene_not_found)

      with {:ok, _project} <-
             SceneReferenceIntegrity.lock_active_project(project_id, :update),
           %Scene{} = locked_scene <-
             Repo.one(
               from(scene in Scene,
                 where:
                   scene.id == ^scene_id and scene.project_id == ^project_id and
                     not is_nil(scene.deleted_at),
                 lock: "FOR UPDATE"
               )
             ),
           {:ok, restored_scene} <-
             locked_scene
             |> Scene.restore_changeset()
             |> Repo.update() do
        restore_children(project_id, locked_scene.id, locked_scene.deleted_at)
        restored_scene
      else
        nil -> Repo.rollback(:scene_not_deleted)
        {:error, reason} -> Repo.rollback(reason)
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

    cte_query = union_all(anchor, ^recursion)

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
      Repo.all(
        from(m in Scene,
          where:
            m.project_id == ^project_id and m.parent_id == ^parent_id and not is_nil(m.deleted_at) and
              m.deleted_at >= ^since_threshold
        )
      )

    Enum.each(children, fn child ->
      Repo.update_all(from(m in Scene, where: m.id == ^child.id), set: [deleted_at: nil])
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
    Repo.one(from(m in Scene, where: m.id == ^scene_id and is_nil(m.deleted_at), preload: [:background_asset]))
  end

  @doc """
  Returns the project_id for a given scene_id.
  Used by reference trackers that need the project scope from a scene.
  """
  def get_scene_project_id(scene_id) do
    Repo.one(from(m in Scene, where: m.id == ^scene_id, select: m.project_id))
  end

  defp maybe_assign_position(attrs, project_id, parent_id) do
    ShortcutHelpers.maybe_assign_position(
      attrs,
      project_id,
      parent_id,
      &TreeOperations.next_position/2
    )
  end

  # =============================================================================
  # Export / Import helpers
  # =============================================================================

  @doc """
  Lists all non-deleted scenes with all associations preloaded.
  Used by the export DataCollector.
  """
  def list_scenes_for_export(project_id, opts \\ []) do
    filter_ids = Keyword.get(opts, :filter_ids, :all)

    query =
      from(s in Scene,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        preload: [:layers, :pins, :zones, :connections, :annotations],
        order_by: [asc: s.position, asc: s.name]
      )

    query
    |> maybe_filter_export_ids(filter_ids)
    |> Repo.all()
  end

  @doc """
  Counts non-deleted scenes for a project.
  """
  def count_scenes(project_id) do
    Repo.aggregate(from(s in Scene, where: s.project_id == ^project_id and is_nil(s.deleted_at)), :count)
  end

  @doc """
  Returns variable usage for a block from scene zones.
  Joins variable_references with scene_zones and scenes to return enriched data.
  Used by the Flows.VariableReferenceTracker to avoid cross-context schema queries.
  """
  def get_scene_zone_variable_usage(block_id, project_id) do
    alias Storyarn.Flows.VariableReference

    Repo.all(
      from(vr in VariableReference,
        join: z in SceneZone,
        on: vr.source_type == "scene_zone" and z.id == vr.source_id,
        join: m in Scene,
        on: m.id == z.scene_id,
        where: vr.block_id == ^block_id,
        where: m.project_id == ^project_id,
        where: is_nil(m.deleted_at),
        select: %{
          source_type: vr.source_type,
          kind: vr.kind,
          scene_id: m.id,
          scene_name: m.name,
          zone_id: z.id,
          zone_name: z.name,
          zone_action_data: z.action_data
        },
        order_by: [asc: vr.kind, asc: m.name]
      )
    )
  end

  @doc """
  Returns variable usage for a block from scene pins.
  Joins variable_references with scene_pins and scenes to return enriched data.
  Used by the Flows.VariableReferenceTracker to avoid cross-context schema queries.
  """
  def get_scene_pin_variable_usage(block_id, project_id) do
    alias Storyarn.Flows.VariableReference

    Repo.all(
      from(vr in VariableReference,
        join: p in ScenePin,
        on: vr.source_type == "scene_pin" and p.id == vr.source_id,
        join: m in Scene,
        on: m.id == p.scene_id,
        where: vr.block_id == ^block_id,
        where: m.project_id == ^project_id,
        where: is_nil(m.deleted_at),
        select: %{
          source_type: vr.source_type,
          kind: vr.kind,
          scene_id: m.id,
          scene_name: m.name,
          pin_id: p.id,
          pin_label: p.label
        },
        order_by: [asc: vr.kind, asc: m.name]
      )
    )
  end

  @doc """
  Returns stale variable reference data for scene zones.
  Joins variable_references with scene_zones, scenes, blocks, and sheets
  to detect staleness via SQL comparison of stored vs current names.
  Used by the Flows.VariableReferenceTracker for stale reference detection.
  """
  def check_stale_scene_zone_variable_references(block_id, project_id) do
    alias Storyarn.Flows.VariableReference
    alias Storyarn.Sheets.Block
    alias Storyarn.Sheets.Sheet

    Repo.all(
      from(vr in VariableReference,
        join: z in SceneZone,
        on: vr.source_type == "scene_zone" and z.id == vr.source_id,
        join: m in Scene,
        on: m.id == z.scene_id,
        join: b in Block,
        on: b.id == vr.block_id,
        join: s in Sheet,
        on: s.id == b.sheet_id,
        where: vr.block_id == ^block_id,
        where: m.project_id == ^project_id,
        where: is_nil(m.deleted_at),
        where: is_nil(s.deleted_at),
        where: is_nil(b.deleted_at),
        select: %{
          source_type: vr.source_type,
          kind: vr.kind,
          scene_id: m.id,
          scene_name: m.name,
          zone_id: z.id,
          zone_name: z.name,
          zone_action_data: z.action_data,
          source_sheet: vr.source_sheet,
          source_variable: vr.source_variable,
          stale:
            fragment(
              """
              CASE WHEN ? = 'table' THEN
                ? != ? OR NOT EXISTS (
                  SELECT 1 FROM table_rows tr
                  JOIN table_columns tc ON tc.block_id = tr.block_id
                  WHERE tr.block_id = ?
                    AND ? = ? || '.' || tr.slug || '.' || tc.slug
                )
              ELSE
                ? != ? OR ? != ?
              END
              """,
              b.type,
              vr.source_sheet,
              s.shortcut,
              b.id,
              vr.source_variable,
              b.variable_name,
              vr.source_sheet,
              s.shortcut,
              vr.source_variable,
              b.variable_name
            )
        },
        order_by: [asc: vr.kind, asc: m.name]
      )
    )
  end

  @doc """
  Returns stale variable reference data for scene pins.
  Joins variable_references with scene_pins, scenes, blocks, and sheets
  to detect staleness via SQL comparison of stored vs current names.
  Used by the Flows.VariableReferenceTracker for stale reference detection.
  """
  def check_stale_scene_pin_variable_references(block_id, project_id) do
    alias Storyarn.Flows.VariableReference
    alias Storyarn.Sheets.Block
    alias Storyarn.Sheets.Sheet

    Repo.all(
      from(vr in VariableReference,
        join: p in ScenePin,
        on: vr.source_type == "scene_pin" and p.id == vr.source_id,
        join: m in Scene,
        on: m.id == p.scene_id,
        join: b in Block,
        on: b.id == vr.block_id,
        join: s in Sheet,
        on: s.id == b.sheet_id,
        where: vr.block_id == ^block_id,
        where: m.project_id == ^project_id,
        where: is_nil(m.deleted_at),
        where: is_nil(s.deleted_at),
        where: is_nil(b.deleted_at),
        select: %{
          source_type: vr.source_type,
          kind: vr.kind,
          scene_id: m.id,
          scene_name: m.name,
          pin_id: p.id,
          pin_label: p.label,
          source_sheet: vr.source_sheet,
          source_variable: vr.source_variable,
          stale:
            fragment(
              """
              CASE WHEN ? = 'table' THEN
                ? != ? OR NOT EXISTS (
                  SELECT 1 FROM table_rows tr
                  JOIN table_columns tc ON tc.block_id = tr.block_id
                  WHERE tr.block_id = ?
                    AND ? = ? || '.' || tr.slug || '.' || tc.slug
                )
              ELSE
                ? != ? OR ? != ?
              END
              """,
              b.type,
              vr.source_sheet,
              s.shortcut,
              b.id,
              vr.source_variable,
              b.variable_name,
              vr.source_sheet,
              s.shortcut,
              vr.source_variable,
              b.variable_name
            )
        },
        order_by: [asc: vr.kind, asc: m.name]
      )
    )
  end

  @doc """
  Resolves scene pin source info for entity reference backlinks.
  Joins entity_references with scene_pins and scenes to return enriched backlink data.
  Used by the Sheets.ReferenceTracker to avoid cross-context schema queries.
  """
  def query_scene_pin_backlinks(target_type, target_id, project_id) do
    alias Storyarn.Sheets.EntityReference

    from(r in EntityReference,
      join: p in ScenePin,
      on: r.source_type == "scene_pin" and r.source_id == p.id,
      join: m in Scene,
      on: p.scene_id == m.id,
      where: r.target_type == ^target_type and r.target_id == ^target_id,
      where: m.project_id == ^project_id,
      select: %{
        id: r.id,
        source_type: r.source_type,
        source_id: r.source_id,
        context: r.context,
        inserted_at: r.inserted_at,
        pin_label: p.label,
        scene_id: m.id,
        scene_name: m.name
      },
      order_by: [desc: r.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(fn ref ->
      %{
        id: ref.id,
        source_type: "scene_pin",
        source_id: ref.source_id,
        context: ref.context,
        inserted_at: ref.inserted_at,
        source_info: %{
          type: :scene,
          scene_id: ref.scene_id,
          scene_name: ref.scene_name,
          element_type: "pin",
          element_label: ref.pin_label
        }
      }
    end)
  end

  @doc """
  Resolves scene zone source info for entity reference backlinks.
  Joins entity_references with scene_zones and scenes to return enriched backlink data.
  Used by the Sheets.ReferenceTracker to avoid cross-context schema queries.
  """
  def query_scene_zone_backlinks(target_type, target_id, project_id) do
    alias Storyarn.Sheets.EntityReference

    from(r in EntityReference,
      join: z in SceneZone,
      on: r.source_type == "scene_zone" and r.source_id == z.id,
      join: m in Scene,
      on: z.scene_id == m.id,
      where: r.target_type == ^target_type and r.target_id == ^target_id,
      where: m.project_id == ^project_id,
      select: %{
        id: r.id,
        source_type: r.source_type,
        source_id: r.source_id,
        context: r.context,
        inserted_at: r.inserted_at,
        zone_name: z.name,
        scene_id: m.id,
        scene_name: m.name
      },
      order_by: [desc: r.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(fn ref ->
      %{
        id: ref.id,
        source_type: "scene_zone",
        source_id: ref.source_id,
        context: ref.context,
        inserted_at: ref.inserted_at,
        source_info: %{
          type: :scene,
          scene_id: ref.scene_id,
          scene_name: ref.scene_name,
          element_type: "zone",
          element_label: ref.zone_name
        }
      }
    end)
  end

  @doc """
  Lists sheet IDs referenced by scene pins in a project.
  Used by the export Validator for orphan sheet detection.
  """
  def list_pin_referenced_sheet_ids(project_id) do
    from(p in ScenePin,
      join: s in Scene,
      on: p.scene_id == s.id,
      where: s.project_id == ^project_id and not is_nil(p.sheet_id),
      select: p.sheet_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Lists active scene IDs for a project.
  Used by the export Validator.
  """
  def list_active_scene_ids(project_id) do
    from(s in Scene,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      select: s.id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Lists existing shortcuts for scenes in a project.
  """
  def list_shortcuts(project_id) do
    from(s in Scene,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      select: s.shortcut
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Detects shortcut conflicts between imported scenes and existing ones.
  """
  def detect_shortcut_conflicts(project_id, shortcuts) when is_list(shortcuts) do
    ImportHelpers.detect_shortcut_conflicts(Scene, project_id, shortcuts)
  end

  @doc """
  Soft-deletes existing scenes with the given shortcut (for overwrite import strategy).
  """
  def soft_delete_by_shortcut(project_id, shortcut) do
    ImportHelpers.soft_delete_by_shortcut(Scene, project_id, shortcut)
  end

  @doc """
  Bulk-inserts scene connections from a list of attr maps.
  """
  def bulk_import_connections(attrs_list) do
    ImportHelpers.bulk_insert(Storyarn.Scenes.SceneConnection, attrs_list)
  end

  @doc """
  Bulk-inserts scene annotations from a list of attr maps.
  """
  def bulk_import_annotations(attrs_list) do
    ImportHelpers.bulk_insert(Storyarn.Scenes.SceneAnnotation, attrs_list)
  end

  # =============================================================================
  # Import helpers (raw insert, no side effects)
  # =============================================================================

  @doc """
  Creates a scene for import. Raw insert — no auto-shortcut, no auto-position,
  no default layer creation. Returns `{:ok, scene}` or `{:error, changeset}`.
  """
  def import_scene(project_id, attrs) do
    %Scene{project_id: project_id}
    |> Scene.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a scene layer for import. Raw insert — no auto-position.
  Returns `{:ok, layer}` or `{:error, changeset}`.
  """
  def import_layer(scene_id, attrs) do
    %SceneLayer{scene_id: scene_id}
    |> SceneLayer.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a scene pin for import. Raw insert — no auto-position,
  no reference tracking. Returns `{:ok, pin}` or `{:error, changeset}`.
  """
  def import_pin(scene_id, attrs) do
    %ScenePin{scene_id: scene_id}
    |> ScenePin.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a scene zone for import. Raw insert — no auto-position,
  no reference tracking. Returns `{:ok, zone}` or `{:error, changeset}`.
  """
  def import_zone(scene_id, attrs) do
    %SceneZone{scene_id: scene_id}
    |> SceneZone.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a scene's parent_id after import (two-pass parent linking).
  """
  def link_import_parent(%Scene{} = scene, parent_id) do
    scene
    |> Ecto.Changeset.change(%{parent_id: parent_id})
    |> Repo.update!()
  end

  @doc """
  Links a pin's flow_id after import. Used in the second pass since
  scenes are imported before flows, so flow_id isn't available at pin creation time.
  """
  def link_pin_import_flow_id(pin_id, flow_id) do
    ScenePin
    |> Repo.get!(pin_id)
    |> Ecto.Changeset.change(%{flow_id: flow_id})
    |> Repo.update!()
  end

  @doc """
  Links a zone's target_id after import. Used in the second pass since
  scenes are imported before flows, so flow target_ids aren't available at zone creation time.
  """
  def link_zone_import_target(zone_id, target_type, target_id) do
    SceneZone
    |> Repo.get!(zone_id)
    |> SceneZone.update_changeset(%{target_type: target_type, target_id: target_id})
    |> Repo.update!()
  end

  # =============================================================================
  # Variable Queries (for condition/instruction builders)
  # =============================================================================

  @doc """
  Lists pin boolean properties as variable descriptors.
  For each pin with a shortcut, emits entries for: hidden, is_playable, is_leader.
  """
  def list_pin_variables(project_id) do
    from(p in ScenePin,
      join: s in Scene,
      on: p.scene_id == s.id,
      where:
        s.project_id == ^project_id and is_nil(s.deleted_at) and
          not is_nil(p.shortcut),
      select: %{
        id: p.id,
        shortcut: p.shortcut,
        label: p.label,
        hidden: p.hidden,
        is_playable: p.is_playable,
        is_leader: p.is_leader
      }
    )
    |> Repo.all()
    |> Enum.flat_map(&expand_pin_variables/1)
  end

  defp expand_pin_variables(pin) do
    base = %{
      source_type: "pin",
      source_id: pin.id,
      sheet_shortcut: pin.shortcut,
      sheet_name: pin.label || pin.shortcut,
      block_id: nil,
      options: nil,
      constraints: nil
    }

    [
      Map.merge(base, %{
        variable_name: "hidden",
        block_type: "boolean",
        value: %{"content" => pin.hidden}
      }),
      Map.merge(base, %{
        variable_name: "is_playable",
        block_type: "boolean",
        value: %{"content" => pin.is_playable}
      }),
      Map.merge(base, %{
        variable_name: "is_leader",
        block_type: "boolean",
        value: %{"content" => pin.is_leader}
      })
    ]
  end

  @doc """
  Lists zone boolean properties as variable descriptors.
  For each zone with a shortcut, emits entries for: hidden.
  """
  def list_zone_variables(project_id) do
    from(z in SceneZone,
      join: s in Scene,
      on: z.scene_id == s.id,
      where:
        s.project_id == ^project_id and is_nil(s.deleted_at) and
          not is_nil(z.shortcut),
      select: %{
        id: z.id,
        shortcut: z.shortcut,
        name: z.name,
        hidden: z.hidden
      }
    )
    |> Repo.all()
    |> Enum.flat_map(&expand_zone_variables/1)
  end

  defp expand_zone_variables(zone) do
    base = %{
      source_type: "zone",
      source_id: zone.id,
      sheet_shortcut: zone.shortcut,
      sheet_name: zone.name || zone.shortcut,
      block_id: nil,
      options: nil,
      constraints: nil
    }

    [
      Map.merge(base, %{
        variable_name: "hidden",
        block_type: "boolean",
        value: %{"content" => zone.hidden}
      })
    ]
  end

  defp maybe_filter_export_ids(query, :all), do: query

  defp maybe_filter_export_ids(query, ids) when is_list(ids) do
    from(q in query, where: q.id in ^ids)
  end
end
