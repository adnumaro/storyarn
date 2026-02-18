defmodule Storyarn.Maps.ConnectionCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Maps.{MapConnection, MapPin}
  alias Storyarn.Repo

  @doc """
  Lists all connections for a map, with from_pin and to_pin preloaded.
  """
  def list_connections(map_id) do
    from(c in MapConnection,
      where: c.map_id == ^map_id,
      preload: [:from_pin, :to_pin]
    )
    |> Repo.all()
  end

  def get_connection(connection_id) do
    MapConnection
    |> Repo.get(connection_id)
    |> Repo.preload([:from_pin, :to_pin])
  end

  def get_connection!(connection_id) do
    MapConnection
    |> Repo.get!(connection_id)
    |> Repo.preload([:from_pin, :to_pin])
  end

  @doc """
  Gets a connection by ID, scoped to a specific map. Returns `nil` if not found.
  """
  def get_connection(map_id, connection_id) do
    from(c in MapConnection,
      where: c.map_id == ^map_id and c.id == ^connection_id,
      preload: [:from_pin, :to_pin]
    )
    |> Repo.one()
  end

  @doc """
  Gets a connection by ID, scoped to a specific map. Raises if not found.
  """
  def get_connection!(map_id, connection_id) do
    from(c in MapConnection,
      where: c.map_id == ^map_id and c.id == ^connection_id,
      preload: [:from_pin, :to_pin]
    )
    |> Repo.one!()
  end

  @doc """
  Creates a connection between two pins.
  Validates that both pins belong to the same map.
  """
  def create_connection(map_id, attrs) do
    attrs = Storyarn.Shared.MapUtils.stringify_keys(attrs)
    from_pin_id = attrs["from_pin_id"]
    to_pin_id = attrs["to_pin_id"]

    with {:ok, _from_pin} <- validate_pin_belongs_to_map(from_pin_id, map_id),
         {:ok, _to_pin} <- validate_pin_belongs_to_map(to_pin_id, map_id) do
      %MapConnection{map_id: map_id}
      |> MapConnection.create_changeset(attrs)
      |> Repo.insert()
    end
  end

  def update_connection(%MapConnection{} = connection, attrs) do
    connection
    |> MapConnection.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates only the waypoints of a connection (optimized for drag).
  """
  def update_connection_waypoints(%MapConnection{} = connection, attrs) do
    connection
    |> MapConnection.waypoints_changeset(attrs)
    |> Repo.update()
  end

  def delete_connection(%MapConnection{} = connection) do
    Repo.delete(connection)
  end

  def change_connection(%MapConnection{} = connection, attrs \\ %{}) do
    MapConnection.update_changeset(connection, attrs)
  end

  defp validate_pin_belongs_to_map(pin_id, map_id) do
    case Repo.get(MapPin, pin_id) do
      nil ->
        {:error, :pin_not_found}

      %MapPin{map_id: ^map_id} = pin ->
        {:ok, pin}

      %MapPin{} ->
        {:error, :pin_belongs_to_different_map}
    end
  end
end
