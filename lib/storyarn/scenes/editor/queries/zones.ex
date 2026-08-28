defmodule Storyarn.Scenes.Editor.Queries.Zones do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.SceneZone

  def list_zones(scene_id, opts \\ []) do
    query =
      from(zone in SceneZone,
        where: zone.scene_id == ^scene_id,
        order_by: [asc: zone.position]
      )

    query =
      case Keyword.get(opts, :layer_id) do
        nil -> query
        layer_id -> where(query, [zone], zone.layer_id == ^layer_id)
      end

    query
    |> preload([:label_icon_asset])
    |> Repo.all()
  end

  def get_zone(zone_id) do
    SceneZone
    |> Repo.get(zone_id)
    |> Repo.preload(:label_icon_asset)
  end

  def get_zone!(zone_id) do
    SceneZone
    |> Repo.get!(zone_id)
    |> Repo.preload(:label_icon_asset)
  end

  def get_zone(scene_id, zone_id) do
    Repo.one(
      from(zone in SceneZone,
        where: zone.scene_id == ^scene_id and zone.id == ^zone_id,
        preload: [:label_icon_asset]
      )
    )
  end

  def get_zone!(scene_id, zone_id) do
    Repo.one!(
      from(zone in SceneZone,
        where: zone.scene_id == ^scene_id and zone.id == ^zone_id,
        preload: [:label_icon_asset]
      )
    )
  end

  def list_actionable_zones(scene_id) do
    Repo.all(
      from(zone in SceneZone,
        where: zone.scene_id == ^scene_id and zone.action_type in ["action", "collection"],
        order_by: [asc: zone.position]
      )
    )
  end

  def get_zone_linking_to_scene(parent_scene_id, child_scene_id) do
    Repo.one(
      from(zone in SceneZone,
        where:
          zone.scene_id == ^parent_scene_id and zone.target_type == "scene" and
            zone.target_id == ^child_scene_id,
        limit: 1
      )
    )
  end
end
