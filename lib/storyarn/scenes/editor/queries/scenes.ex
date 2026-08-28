defmodule Storyarn.Scenes.Editor.Queries.Scenes do
  @moduledoc """
  Read side for the Scene editor.

  These queries deliberately live apart from editor commands so callers can
  consume Scene-owned projections without depending on mutation workflows.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.SearchHelpers
  alias Storyarn.Repo
  alias Storyarn.Scenes.Editor.Rules.Tree
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone

  @sidebar_element_limit 10
  @default_search_limit 20
  @max_deep_search_limit 50
  @max_deep_search_offset 10_000

  @scene_preloads [
    :layers,
    [zones: [:label_icon_asset]],
    [pins: [:icon_asset, sheet: [avatars: :asset]]],
    :annotations,
    :background_asset,
    connections: [:from_pin, :to_pin]
  ]

  @doc """
  Lists all active scenes for a project in deterministic editor order.
  """
  def list_scenes(project_id) do
    Repo.all(
      from(scene in Scene,
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        order_by: [asc: scene.position, asc: scene.name, asc: scene.id]
      )
    )
  end

  @doc "Lists the active project scenes as an editor tree."
  def list_scenes_tree(project_id) do
    project_id
    |> base_scenes_query()
    |> Repo.all()
    |> Tree.build_tree_from_flat_list()
  end

  @doc """
  Lists the scene tree with the bounded pin and zone projections used by the
  editor sidebar.
  """
  def list_scenes_tree_with_elements(project_id) do
    all_scenes = project_id |> base_scenes_query() |> Repo.all()
    scene_ids = Enum.map(all_scenes, & &1.id)

    zones_by_scene = load_sidebar_zones(scene_ids)
    pins_by_scene = load_sidebar_pins(scene_ids)
    zone_counts = count_elements_by_scene(SceneZone, scene_ids)
    pin_counts = count_elements_by_scene(ScenePin, scene_ids)

    all_scenes
    |> Enum.map(fn scene ->
      scene
      |> Map.from_struct()
      |> Map.put(:sidebar_zones, Map.get(zones_by_scene, scene.id, []))
      |> Map.put(:sidebar_pins, Map.get(pins_by_scene, scene.id, []))
      |> Map.put(:zone_count, Map.get(zone_counts, scene.id, 0))
      |> Map.put(:pin_count, Map.get(pin_counts, scene.id, 0))
    end)
    |> Tree.build_tree_from_flat_list()
  end

  @doc "Searches scenes by name or shortcut for reference selection."
  def search_scenes(project_id, query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_search_limit)
    offset = Keyword.get(opts, :offset, 0)
    query_str = String.trim(query)

    if query_str == "" do
      Repo.all(
        from(scene in Scene,
          where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
          order_by: [desc: scene.updated_at],
          limit: ^limit,
          offset: ^offset
        ),
        log: false
      )
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query_str)}%"

      Repo.all(
        from(scene in Scene,
          where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
          where: ilike(scene.name, ^search_term) or ilike(scene.shortcut, ^search_term),
          order_by: [asc: scene.name],
          limit: ^limit,
          offset: ^offset
        ),
        log: false
      )
    end
  end

  @doc """
  Searches scene metadata and authored text inside layers, pins, zones,
  annotations and connections.
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

  @doc "Gets an active scene with the editor associations preloaded."
  def get_scene(project_id, scene_id) do
    Repo.one(
      from(scene in Scene,
        where:
          scene.project_id == ^project_id and scene.id == ^scene_id and
            is_nil(scene.deleted_at),
        preload: ^@scene_preloads
      )
    )
  end

  @doc "Gets an active editor scene, raising when it is not found."
  def get_scene!(project_id, scene_id) do
    Repo.one!(
      from(scene in Scene,
        where:
          scene.project_id == ^project_id and scene.id == ^scene_id and
            is_nil(scene.deleted_at),
        preload: ^@scene_preloads
      )
    )
  end

  @doc "Gets an active scene by id without project scoping or preloads."
  def get_scene_by_id(scene_id) do
    Repo.one(from(scene in Scene, where: scene.id == ^scene_id and is_nil(scene.deleted_at)))
  end

  @doc "Gets an active scene without editor preloads."
  def get_scene_brief(project_id, scene_id) do
    Repo.one(
      from(scene in Scene,
        where:
          scene.project_id == ^project_id and scene.id == ^scene_id and
            is_nil(scene.deleted_at)
      )
    )
  end

  @doc "Gets a project scene including soft-deleted records."
  def get_scene_including_deleted(project_id, scene_id) do
    Repo.one(
      from(scene in Scene,
        where: scene.project_id == ^project_id and scene.id == ^scene_id,
        preload: [:layers, :zones, :pins, connections: [:from_pin, :to_pin]]
      )
    )
  end

  @doc "Lists soft-deleted project scenes in deletion order."
  def list_deleted_scenes(project_id) do
    Repo.all(
      from(scene in Scene,
        where: scene.project_id == ^project_id and not is_nil(scene.deleted_at),
        order_by: [desc: scene.deleted_at]
      )
    )
  end

  @doc "Returns active ancestors from the root to the direct parent."
  def list_ancestors(%Scene{parent_id: nil}), do: []

  def list_ancestors(%Scene{id: scene_id}) do
    anchor =
      from(scene in "scenes",
        where: scene.id == ^scene_id and is_nil(scene.deleted_at),
        select: %{parent_id: scene.parent_id, depth: 0}
      )

    recursion =
      from(scene in "scenes",
        join: ancestor in "ancestors",
        on: scene.id == ancestor.parent_id,
        where: is_nil(scene.deleted_at),
        select: %{parent_id: scene.parent_id, depth: ancestor.depth + 1}
      )

    cte_query = union_all(anchor, ^recursion)

    ancestor_ids =
      from("ancestors")
      |> recursive_ctes(true)
      |> with_cte("ancestors", as: ^cte_query)
      |> where([ancestor], not is_nil(ancestor.parent_id))
      |> select([ancestor], ancestor.parent_id)
      |> Repo.all()

    if ancestor_ids == [] do
      []
    else
      ancestors_by_id =
        from(scene in Scene,
          where: scene.id in ^ancestor_ids and is_nil(scene.deleted_at)
        )
        |> Repo.all()
        |> Map.new(fn scene -> {scene.id, scene} end)

      ancestor_ids
      |> Enum.map(&Map.get(ancestors_by_id, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.reverse()
    end
  end

  defp load_sidebar_zones([]), do: %{}

  defp load_sidebar_zones(scene_ids) do
    inner =
      from(zone in SceneZone,
        where: zone.scene_id in ^scene_ids,
        where: not is_nil(zone.name) and zone.name != "",
        order_by: [asc: zone.position, asc: zone.name],
        select: %{
          id: zone.id,
          name: zone.name,
          scene_id: zone.scene_id,
          row:
            over(row_number(),
              partition_by: zone.scene_id,
              order_by: [asc: zone.position]
            )
        }
      )

    from(sidebar_zone in subquery(inner),
      where: sidebar_zone.row <= ^@sidebar_element_limit
    )
    |> Repo.all()
    |> Enum.group_by(& &1.scene_id)
  end

  defp load_sidebar_pins([]), do: %{}

  defp load_sidebar_pins(scene_ids) do
    inner =
      from(pin in ScenePin,
        where: pin.scene_id in ^scene_ids,
        order_by: [asc: pin.position, asc: pin.label],
        select: %{
          id: pin.id,
          label: pin.label,
          scene_id: pin.scene_id,
          row:
            over(row_number(),
              partition_by: pin.scene_id,
              order_by: [asc: pin.position]
            )
        }
      )

    from(sidebar_pin in subquery(inner),
      where: sidebar_pin.row <= ^@sidebar_element_limit
    )
    |> Repo.all()
    |> Enum.group_by(& &1.scene_id)
  end

  defp count_elements_by_scene(_schema, []), do: %{}

  defp count_elements_by_scene(schema, scene_ids) do
    from(element in schema,
      where: element.scene_id in ^scene_ids,
      group_by: element.scene_id,
      select: {element.scene_id, count(element.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp run_deep_search(project_id, search_term, limit, offset) do
    Repo.all(
      from(scene in Scene,
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        where:
          ilike(scene.name, ^search_term) or
            ilike(scene.shortcut, ^search_term) or
            ilike(scene.description, ^search_term) or
            scene.id in subquery(scene_ids_matching_layers(project_id, search_term)) or
            scene.id in subquery(scene_ids_matching_pins(project_id, search_term)) or
            scene.id in subquery(scene_ids_matching_zones(project_id, search_term)) or
            scene.id in subquery(scene_ids_matching_annotations(project_id, search_term)) or
            scene.id in subquery(scene_ids_matching_connections(project_id, search_term)),
        order_by: [asc: scene.name, asc: scene.id],
        limit: ^limit,
        offset: ^offset
      ),
      log: false
    )
  end

  defp scene_ids_matching_layers(project_id, search_term) do
    from(layer in SceneLayer,
      join: scene in Scene,
      on: scene.id == layer.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      where: ilike(layer.name, ^search_term),
      select: layer.scene_id
    )
  end

  defp scene_ids_matching_pins(project_id, search_term) do
    from(pin in ScenePin,
      join: scene in Scene,
      on: scene.id == pin.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      where:
        ilike(pin.label, ^search_term) or ilike(pin.shortcut, ^search_term) or
          ilike(pin.tooltip, ^search_term),
      select: pin.scene_id
    )
  end

  defp scene_ids_matching_zones(project_id, search_term) do
    from(zone in SceneZone,
      join: scene in Scene,
      on: scene.id == zone.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      where:
        ilike(zone.name, ^search_term) or ilike(zone.shortcut, ^search_term) or
          ilike(zone.tooltip, ^search_term),
      select: zone.scene_id
    )
  end

  defp scene_ids_matching_annotations(project_id, search_term) do
    from(annotation in SceneAnnotation,
      join: scene in Scene,
      on: scene.id == annotation.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      where: ilike(annotation.text, ^search_term),
      select: annotation.scene_id
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

  defp base_scenes_query(project_id) do
    from(scene in Scene,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      order_by: [asc: scene.position, asc: scene.name, asc: scene.id]
    )
  end
end
