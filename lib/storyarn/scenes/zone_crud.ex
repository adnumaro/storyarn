defmodule Storyarn.Scenes.ZoneCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.{PositionUtils, SceneZone}
  alias Storyarn.Sheets

  @doc """
  Lists zones for a map, with optional layer_id filter.
  """
  def list_zones(scene_id, opts \\ []) do
    query =
      from(z in SceneZone,
        where: z.scene_id == ^scene_id,
        order_by: [asc: z.position]
      )

    query =
      case Keyword.get(opts, :layer_id) do
        nil -> query
        layer_id -> where(query, [z], z.layer_id == ^layer_id)
      end

    Repo.all(query)
  end

  def get_zone(zone_id) do
    Repo.get(SceneZone, zone_id)
  end

  def get_zone!(zone_id) do
    Repo.get!(SceneZone, zone_id)
  end

  @doc """
  Gets a zone by ID, scoped to a specific map. Returns `nil` if not found.
  """
  def get_zone(scene_id, zone_id) do
    from(z in SceneZone, where: z.scene_id == ^scene_id and z.id == ^zone_id)
    |> Repo.one()
  end

  @doc """
  Gets a zone by ID, scoped to a specific map. Raises if not found.
  """
  def get_zone!(scene_id, zone_id) do
    from(z in SceneZone, where: z.scene_id == ^scene_id and z.id == ^zone_id)
    |> Repo.one!()
  end

  def create_zone(scene_id, attrs) do
    position = PositionUtils.next_position(SceneZone, scene_id)
    attrs = Storyarn.Shared.MapUtils.stringify_keys(attrs)

    result =
      %SceneZone{scene_id: scene_id}
      |> SceneZone.create_changeset(Map.put(attrs, "position", position))
      |> Repo.insert()

    case result do
      {:ok, zone} ->
        project_id = Scenes.get_scene_project_id(scene_id)
        Sheets.update_scene_zone_references(zone)
        Flows.update_scene_zone_references(zone, project_id: project_id)

      _ ->
        :ok
    end

    result
  end

  def update_zone(%SceneZone{} = zone, attrs) do
    result =
      zone
      |> SceneZone.update_changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_zone} ->
        project_id = Scenes.get_scene_project_id(zone.scene_id)
        Sheets.update_scene_zone_references(updated_zone)

        Flows.update_scene_zone_references(updated_zone,
          project_id: project_id
        )

      _ ->
        :ok
    end

    result
  end

  @doc """
  Updates only vertices (optimized for drag operations).
  """
  def update_zone_vertices(%SceneZone{} = zone, attrs) do
    zone
    |> SceneZone.update_vertices_changeset(attrs)
    |> Repo.update()
  end

  def delete_zone(%SceneZone{} = zone) do
    Sheets.delete_map_zone_references(zone.id)
    Flows.delete_map_zone_references(zone.id)
    Repo.delete(zone)
  end

  def change_zone(%SceneZone{} = zone, attrs \\ %{}) do
    SceneZone.update_changeset(zone, attrs)
  end

  @doc """
  Lists zones with a non-none action_type, ordered by position.
  """
  def list_actionable_zones(scene_id) do
    from(z in SceneZone,
      where: z.scene_id == ^scene_id and z.action_type != "none",
      order_by: [asc: z.position]
    )
    |> Repo.all()
  end

  @doc """
  Finds the zone on a given map that targets a specific child map.
  Returns `nil` if no linking zone is found.
  """
  def get_zone_linking_to_scene(parent_scene_id, child_scene_id) do
    from(z in SceneZone,
      where:
        z.scene_id == ^parent_scene_id and
          z.target_type == "scene" and
          z.target_id == ^child_scene_id,
      limit: 1
    )
    |> Repo.one()
  end
end
