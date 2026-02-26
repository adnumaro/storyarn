defmodule Storyarn.Scenes.ConnectionCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.{SceneConnection, ScenePin}

  @doc """
  Lists all connections for a map, with from_pin and to_pin preloaded.
  """
  def list_connections(scene_id) do
    from(c in SceneConnection,
      where: c.scene_id == ^scene_id,
      preload: [:from_pin, :to_pin]
    )
    |> Repo.all()
  end

  @doc """
  Gets a connection by ID, scoped to a specific scene. Returns `nil` if not found.
  """
  def get_connection(scene_id, connection_id) do
    from(c in SceneConnection,
      where: c.scene_id == ^scene_id and c.id == ^connection_id,
      preload: [:from_pin, :to_pin]
    )
    |> Repo.one()
  end

  @doc """
  Gets a connection by ID, scoped to a specific map. Raises if not found.
  """
  def get_connection!(scene_id, connection_id) do
    from(c in SceneConnection,
      where: c.scene_id == ^scene_id and c.id == ^connection_id,
      preload: [:from_pin, :to_pin]
    )
    |> Repo.one!()
  end

  @doc """
  Creates a connection between two pins.
  Validates that both pins belong to the same map.
  """
  def create_connection(scene_id, attrs) do
    attrs = Storyarn.Shared.MapUtils.stringify_keys(attrs)
    from_pin_id = attrs["from_pin_id"]
    to_pin_id = attrs["to_pin_id"]

    with {:ok, _from_pin} <- validate_pin_belongs_to_map(from_pin_id, scene_id),
         {:ok, _to_pin} <- validate_pin_belongs_to_map(to_pin_id, scene_id) do
      %SceneConnection{scene_id: scene_id}
      |> SceneConnection.create_changeset(attrs)
      |> Repo.insert()
    end
  end

  def update_connection(%SceneConnection{} = connection, attrs) do
    connection
    |> SceneConnection.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates only the waypoints of a connection (optimized for drag).
  """
  def update_connection_waypoints(%SceneConnection{} = connection, attrs) do
    connection
    |> SceneConnection.waypoints_changeset(attrs)
    |> Repo.update()
  end

  def delete_connection(%SceneConnection{} = connection) do
    Repo.delete(connection)
  end

  def change_connection(%SceneConnection{} = connection, attrs \\ %{}) do
    SceneConnection.update_changeset(connection, attrs)
  end

  defp validate_pin_belongs_to_map(pin_id, scene_id) do
    case Repo.get(ScenePin, pin_id) do
      nil ->
        {:error, :pin_not_found}

      %ScenePin{scene_id: ^scene_id} = pin ->
        {:ok, pin}

      %ScenePin{} ->
        {:error, :pin_belongs_to_different_scene}
    end
  end
end
