defmodule Storyarn.Maps.ZoneCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Maps.{MapZone, PositionUtils}
  alias Storyarn.Repo

  @doc """
  Lists zones for a map, with optional layer_id filter.
  """
  def list_zones(map_id, opts \\ []) do
    query =
      from(z in MapZone,
        where: z.map_id == ^map_id,
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
    Repo.get(MapZone, zone_id)
  end

  def get_zone!(zone_id) do
    Repo.get!(MapZone, zone_id)
  end

  @doc """
  Gets a zone by ID, scoped to a specific map. Returns `nil` if not found.
  """
  def get_zone(map_id, zone_id) do
    from(z in MapZone, where: z.map_id == ^map_id and z.id == ^zone_id)
    |> Repo.one()
  end

  @doc """
  Gets a zone by ID, scoped to a specific map. Raises if not found.
  """
  def get_zone!(map_id, zone_id) do
    from(z in MapZone, where: z.map_id == ^map_id and z.id == ^zone_id)
    |> Repo.one!()
  end

  def create_zone(map_id, attrs) do
    position = PositionUtils.next_position(MapZone, map_id)
    attrs = Storyarn.Shared.MapUtils.stringify_keys(attrs)

    %MapZone{map_id: map_id}
    |> MapZone.create_changeset(Map.put(attrs, "position", position))
    |> Repo.insert()
  end

  def update_zone(%MapZone{} = zone, attrs) do
    zone
    |> MapZone.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates only vertices (optimized for drag operations).
  """
  def update_zone_vertices(%MapZone{} = zone, attrs) do
    zone
    |> MapZone.update_vertices_changeset(attrs)
    |> Repo.update()
  end

  def delete_zone(%MapZone{} = zone) do
    Repo.delete(zone)
  end

  def change_zone(%MapZone{} = zone, attrs \\ %{}) do
    MapZone.update_changeset(zone, attrs)
  end

  @doc """
  Lists zones with action_type "event", ordered by position.
  """
  def list_event_zones(map_id) do
    from(z in MapZone,
      where: z.map_id == ^map_id and z.action_type == "event",
      order_by: [asc: z.position]
    )
    |> Repo.all()
  end

  @doc """
  Lists zones with a non-navigate action_type, ordered by position.
  """
  def list_actionable_zones(map_id) do
    from(z in MapZone,
      where: z.map_id == ^map_id and z.action_type != "navigate",
      order_by: [asc: z.position]
    )
    |> Repo.all()
  end

  @doc """
  Finds the zone on a given map that targets a specific child map.
  Returns `nil` if no linking zone is found.
  """
  def get_zone_linking_to_map(parent_map_id, child_map_id) do
    from(z in MapZone,
      where:
        z.map_id == ^parent_map_id and
          z.target_type == "map" and
          z.target_id == ^child_map_id,
      limit: 1
    )
    |> Repo.one()
  end
end
