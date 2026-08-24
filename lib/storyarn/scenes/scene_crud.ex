defmodule Storyarn.Scenes.SceneCrud do
  @moduledoc """
  CRUD operations for scenes with hierarchical tree structure.

  Handles scene creation (with auto-shortcut and default layer), updates,
  soft-delete/restore with recursive children handling, tree queries,
  and sidebar element preloading.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Collaboration
  alias Storyarn.Platform
  alias Storyarn.Platform.Shared.MapUtils
  alias Storyarn.Platform.Shared.SearchHelpers
  alias Storyarn.Repo
  alias Storyarn.Scenes.AssetReferences
  alias Storyarn.Scenes.Limits
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneReferenceIntegrity
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Scenes.ShortcutGenerator
  alias Storyarn.Scenes.SoftDelete
  alias Storyarn.Scenes.TreeOperations

  @doc """
  Lists all non-deleted scenes for a project.
  Returns scenes ordered by position, then name, then id.

  The id is a tiebreak, not decoration: siblings created together share a
  position and may share a name, and this feeds the project-wide health sweep —
  whose results must not reorder between runs on `Repo.all`'s unspecified order.
  The same deterministic ordering is required by the structural health sweep.
  """
  def list_scenes(project_id) do
    Repo.all(
      from(m in Scene,
        where: m.project_id == ^project_id and is_nil(m.deleted_at),
        order_by: [asc: m.position, asc: m.name, asc: m.id]
      )
    )
  end

  @doc """
  Lists scenes as a tree structure (without sidebar elements).
  For the scene editor sidebar with zone/pin previews, use `list_scenes_tree_with_elements/1`.
  """
  def list_scenes_tree(project_id) do
    all_scenes = project_id |> base_scenes_query() |> Repo.all()
    TreeOperations.build_tree_from_flat_list(all_scenes)
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

    TreeOperations.build_tree_from_flat_list(all_scenes)
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
  @max_deep_search_limit 50
  @max_deep_search_offset 10_000

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
        ),
        log: false
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
        ),
        log: false
      )
    end
  end

  @doc """
  Searches scene metadata and authored text inside layers, pins, zones, and
  annotations.

  The search remains scoped to one project and returns matching scenes rather
  than the individual child records that matched.

  ## Options
    - `:limit` - Max results (default #{@default_search_limit}, max #{@max_deep_search_limit})
    - `:offset` - Skip N results (default 0, max #{@max_deep_search_offset})
  """
  @spec search_scenes_deep(integer(), String.t(), keyword()) :: [Scene.t()]
  def search_scenes_deep(project_id, query, opts \\ []) when is_binary(query) do
    limit = bounded_deep_search_limit(opts)
    offset = bounded_deep_search_offset(opts)
    query_str = String.trim(query)

    if query_str == "" do
      search_scenes(project_id, query_str, limit: limit, offset: offset)
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query_str)}%"
      run_deep_search(project_id, search_term, limit, offset)
    end
  end

  defp run_deep_search(project_id, search_term, limit, offset) do
    Repo.all(
      from(m in Scene,
        where: m.project_id == ^project_id and is_nil(m.deleted_at),
        where:
          ilike(m.name, ^search_term) or
            ilike(m.shortcut, ^search_term) or
            ilike(m.description, ^search_term) or
            m.id in subquery(scene_ids_matching_layers(project_id, search_term)) or
            m.id in subquery(scene_ids_matching_pins(project_id, search_term)) or
            m.id in subquery(scene_ids_matching_zones(project_id, search_term)) or
            m.id in subquery(scene_ids_matching_annotations(project_id, search_term)) or
            m.id in subquery(scene_ids_matching_connections(project_id, search_term)),
        order_by: [asc: m.name, asc: m.id],
        limit: ^limit,
        offset: ^offset
      ),
      log: false
    )
  end

  defp scene_ids_matching_layers(project_id, search_term) do
    from(l in SceneLayer,
      join: m in Scene,
      on: m.id == l.scene_id,
      where: m.project_id == ^project_id and is_nil(m.deleted_at),
      where: ilike(l.name, ^search_term),
      select: l.scene_id
    )
  end

  defp scene_ids_matching_pins(project_id, search_term) do
    from(p in ScenePin,
      join: m in Scene,
      on: m.id == p.scene_id,
      where: m.project_id == ^project_id and is_nil(m.deleted_at),
      where:
        ilike(p.label, ^search_term) or
          ilike(p.shortcut, ^search_term) or
          ilike(p.tooltip, ^search_term),
      select: p.scene_id
    )
  end

  defp scene_ids_matching_zones(project_id, search_term) do
    from(z in SceneZone,
      join: m in Scene,
      on: m.id == z.scene_id,
      where: m.project_id == ^project_id and is_nil(m.deleted_at),
      where:
        ilike(z.name, ^search_term) or
          ilike(z.shortcut, ^search_term) or
          ilike(z.tooltip, ^search_term),
      select: z.scene_id
    )
  end

  defp scene_ids_matching_annotations(project_id, search_term) do
    from(a in SceneAnnotation,
      join: m in Scene,
      on: m.id == a.scene_id,
      where: m.project_id == ^project_id and is_nil(m.deleted_at),
      where: ilike(a.text, ^search_term),
      select: a.scene_id
    )
  end

  defp scene_ids_matching_connections(project_id, search_term) do
    from(connection in SceneConnection,
      join: scene in Scene,
      on: scene.id == connection.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      where: ilike(connection.label, ^search_term),
      select: connection.scene_id
    )
  end

  defp bounded_deep_search_limit(opts) do
    case Keyword.get(opts, :limit, @default_search_limit) do
      limit when is_integer(limit) -> limit |> max(1) |> min(@max_deep_search_limit)
      _invalid -> @default_search_limit
    end
  end

  defp bounded_deep_search_offset(opts) do
    case Keyword.get(opts, :offset, 0) do
      offset when is_integer(offset) -> offset |> max(0) |> min(@max_deep_search_offset)
      _invalid -> 0
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
  Invalidates the scenes dashboard for the project owning `scene_id`, after a
  successful write to one of a scene's child tables.

  Child tables carry no `project_id`, so the owning project is resolved here
  rather than copied into every child CRUD. Callers pass the whole result and
  get it back unchanged, so this can sit at the end of a pipeline.

  It matters beyond the ≤30s cache TTL, for two different reasons depending on
  the child table. Pin and zone shortcuts ARE referenceable variables
  (`Scenes.VariableCatalog.list_referenceable/1`), so a write that adds or removes one
  changes the vocabulary every health surface type-checks against. Layers carry
  no shortcut and are not vocabulary, but their existence and `is_default` are
  finding inputs (`missing_scene_layer`, `missing_default_layer`,
  `multiple_default_layers`), and deleting one nilifies the `layer_id` behind
  `invalid_layer_reference`.
  """
  @spec broadcast_scene_dashboard_result(term(), term()) :: term()
  def broadcast_scene_dashboard_result(result, scene_id)

  def broadcast_scene_dashboard_result({:ok, _value} = result, scene_id) do
    project_id = Repo.one(from(s in Scene, where: s.id == ^scene_id, select: s.project_id))

    if project_id, do: Collaboration.broadcast_dashboard_change(project_id, :scenes)

    result
  end

  def broadcast_scene_dashboard_result(result, _scene_id), do: result

  @doc false
  @spec broadcast_scene_dashboard_project_result(term()) :: term()
  def broadcast_scene_dashboard_project_result({:ok, {value, project_id}}) do
    Collaboration.broadcast_dashboard_change(project_id, :scenes)
    {:ok, value}
  end

  def broadcast_scene_dashboard_project_result(result), do: result

  @doc """
  Creates a scene with auto-generated shortcut and default layer.
  Auto-assigns position if not provided.
  """
  def create_scene(%{user: %{id: actor_id}}, project, attrs) when is_integer(actor_id) and actor_id > 0 do
    project_id = project_id!(project)

    result =
      fn ->
        scene = create_scene_in_transaction(project_id, attrs)
        {scene, deliver_content_activity!(actor_id, project_id, :created, scene)}
      end
      |> Repo.transaction()
      |> normalize_item_limit_result()

    case result do
      {:ok, {scene, notification_outcome}} ->
        Platform.publish_notification_delivery(notification_outcome)
        Collaboration.broadcast_dashboard_change(project_id, :scenes)
        {:ok, scene}

      other ->
        other
    end
  end

  def create_scene(project, attrs) do
    project_id = project_id!(project)
    result = do_create_scene(project, attrs)

    case result do
      {:ok, _scene} ->
        Collaboration.broadcast_dashboard_change(project_id, :scenes)

      _ ->
        :ok
    end

    result
  end

  defp do_create_scene(project, attrs) do
    fn -> create_scene_in_transaction(project_id!(project), attrs) end
    |> Repo.transaction()
    |> normalize_item_limit_result()
  end

  @doc false
  def create_scene_in_transaction(project, attrs) do
    project_id = project_id!(project)

    with {:ok, locked_project} <-
           SceneReferenceIntegrity.lock_active_project(project_id, :update),
         :ok <- Limits.can_create_item?(locked_project),
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

  @doc false
  def create_scene_in_transaction(%{user: %{id: actor_id}}, project, attrs) when is_integer(actor_id) and actor_id > 0 do
    project_id = project_id!(project)
    scene = create_scene_in_transaction(project_id, attrs)
    {scene, deliver_content_activity!(actor_id, project_id, :created, scene)}
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
    scene.id
    |> SceneReferenceIntegrity.with_active_scene_lock(
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
    |> broadcast_scene_dashboard_result(scene.id)
  end

  @doc """
  Soft-deletes a scene by setting deleted_at.
  Also soft-deletes all children recursively.
  """
  def delete_scene(%Scene{} = scene) do
    with {:ok, %{entity: entity}} <- delete_scene_subtree(scene), do: {:ok, entity}
  end

  def delete_scene(%{user: %{id: actor_id}} = actor_scope, %Scene{} = scene) when is_integer(actor_id) and actor_id > 0 do
    with {:ok, %{entity: entity}} <- delete_scene_subtree(actor_scope, scene), do: {:ok, entity}
  end

  @doc """
  Same soft-delete as `delete_scene/1`, additionally returning `deleted_ids` —
  the committed cascade set, collected by the deletion itself under the same
  lock. Callers that broadcast about the deletion MUST use these ids: a
  separate pre-delete traversal can desync from concurrent tree changes.
  """
  def delete_scene_subtree(%Scene{} = scene) do
    result = Repo.transaction(fn -> delete_scene_subtree_in_transaction(scene) end)

    case result do
      {:ok, %{entity: deleted_scene}} ->
        Collaboration.broadcast_dashboard_change(deleted_scene.project_id, :scenes)

      _ ->
        :ok
    end

    result
  end

  def delete_scene_subtree(%{user: %{id: actor_id}} = actor_scope, %Scene{} = scene)
      when is_integer(actor_id) and actor_id > 0 do
    result = Repo.transaction(fn -> delete_scene_subtree_in_transaction(actor_scope, scene) end)

    case result do
      {:ok, %{entity: deleted_scene, notification_outcome: notification_outcome} = deleted} ->
        Platform.publish_notification_delivery(notification_outcome)
        Collaboration.broadcast_dashboard_change(deleted_scene.project_id, :scenes)
        {:ok, Map.delete(deleted, :notification_outcome)}

      _ ->
        result
    end
  end

  @doc false
  def delete_scene_subtree_in_transaction(%Scene{} = scene) do
    SceneReferenceIntegrity.with_active_scene_lock_in_transaction(
      scene.id,
      [project_lock: :update],
      fn locked_scene ->
        case locked_scene |> Scene.delete_changeset() |> Repo.update() do
          {:ok, deleted_scene} ->
            child_ids =
              SoftDelete.soft_delete_children(
                Scene,
                locked_scene.project_id,
                locked_scene.id
              )

            {:ok, %{entity: deleted_scene, deleted_ids: [deleted_scene.id | child_ids]}}

          {:error, changeset} ->
            {:error, changeset}
        end
      end
    )
  end

  @doc false
  def delete_scene_subtree_in_transaction(%{user: %{id: actor_id}}, %Scene{} = scene)
      when is_integer(actor_id) and actor_id > 0 do
    deleted = delete_scene_subtree_in_transaction(scene)

    outcome =
      deliver_content_activity!(actor_id, deleted.entity.project_id, :deleted, deleted.entity)

    Map.put(deleted, :notification_outcome, outcome)
  end

  @doc false
  def delete_scene_subtree_by_id_in_transaction(%{user: %{id: actor_id}} = actor_scope, project_id, scene_id)
      when is_integer(actor_id) and actor_id > 0 do
    case get_scene_brief(project_id, scene_id) do
      %Scene{} = scene -> delete_scene_subtree_in_transaction(actor_scope, scene)
      nil -> Repo.rollback(:not_found)
    end
  end

  defp deliver_content_activity!(actor_id, project_id, action, scene) do
    case Platform.deliver_content_activity_by_ids(actor_id, project_id, action, "scene", scene) do
      {:ok, outcome} -> outcome
      {:error, reason} -> Repo.rollback(reason)
    end
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
    fn ->
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
           restore_children =
             lock_scene_restore_children(
               project_id,
               locked_scene.id,
               locked_scene.deleted_at
             ),
           :ok <-
             AssetReferences.lock_active_for_restore(project_id,
               scene_ids: [locked_scene.id | Enum.map(restore_children, & &1.id)]
             ),
           {:ok, restored_scene} <-
             locked_scene
             |> Scene.restore_changeset()
             |> Repo.update() do
        restore_locked_scene_children(restore_children)
        {restored_scene, project_id}
      else
        nil -> Repo.rollback(:scene_not_deleted)
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_scene_dashboard_project_result()
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

  # Same total order as `list_scenes/1`, so the sidebar tree and the dashboard
  # cannot present siblings that share a position in two different orders.
  defp base_scenes_query(project_id) do
    from(m in Scene,
      where: m.project_id == ^project_id and is_nil(m.deleted_at),
      order_by: [asc: m.position, asc: m.name, asc: m.id]
    )
  end

  defp lock_scene_restore_children(project_id, parent_id, since) do
    # Only restore children that were deleted at the same time as the parent
    # (within 1 second), to avoid restoring children deleted independently.
    since_threshold = DateTime.add(since, -1, :second)

    children =
      Repo.all(
        from(m in Scene,
          where:
            m.project_id == ^project_id and m.parent_id == ^parent_id and not is_nil(m.deleted_at) and
              m.deleted_at >= ^since_threshold,
          order_by: [asc: m.id],
          lock: "FOR UPDATE"
        )
      )

    children ++
      Enum.flat_map(children, fn child ->
        lock_scene_restore_children(project_id, child.id, since)
      end)
  end

  defp restore_locked_scene_children([]), do: :ok

  defp restore_locked_scene_children(children) do
    child_ids = Enum.map(children, & &1.id)
    {_count, _rows} = Repo.update_all(from(scene in Scene, where: scene.id in ^child_ids), set: [deleted_at: nil])
    :ok
  end

  defp maybe_generate_shortcut(attrs, project_id, exclude_scene_id) do
    attrs
    |> stringify_keys()
    |> ShortcutGenerator.prepare_create(project_id, exclude_scene_id)
  end

  defp maybe_generate_shortcut_on_update(%Scene{} = scene, attrs) do
    ShortcutGenerator.prepare_update(scene, attrs)
  end

  defp stringify_keys(attrs), do: MapUtils.stringify_keys(attrs)

  defp maybe_assign_position(attrs, project_id, parent_id) do
    ShortcutGenerator.assign_position(attrs, project_id, parent_id)
  end

  defp project_id!(%{id: project_id}), do: project_id!(project_id)
  defp project_id!(project_id) when is_integer(project_id) and project_id > 0, do: project_id

  defp project_id!(project) do
    raise ArgumentError, "expected a Scene project identity, got: #{inspect(project)}"
  end
end
