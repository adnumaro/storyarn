defmodule Storyarn.Scenes.ConnectionCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.SceneReferenceIntegrity
  alias Storyarn.Shared.MapUtils

  @doc """
  Lists all connections for a map, with from_pin and to_pin preloaded.
  """
  def list_connections(scene_id) do
    Repo.all(from(c in SceneConnection, where: c.scene_id == ^scene_id, preload: [:from_pin, :to_pin]))
  end

  @doc """
  Gets a connection by ID, scoped to a specific scene. Returns `nil` if not found.
  """
  def get_connection(scene_id, connection_id) do
    Repo.one(
      from(c in SceneConnection,
        where: c.scene_id == ^scene_id and c.id == ^connection_id,
        preload: [:from_pin, :to_pin]
      )
    )
  end

  @doc """
  Gets a connection by ID, scoped to a specific map. Raises if not found.
  """
  def get_connection!(scene_id, connection_id) do
    Repo.one!(
      from(c in SceneConnection,
        where: c.scene_id == ^scene_id and c.id == ^connection_id,
        preload: [:from_pin, :to_pin]
      )
    )
  end

  @doc """
  Creates a route between pinned or free points.
  Validates that any pinned endpoints belong to the same scene.
  """
  def create_connection(scene_id, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    SceneReferenceIntegrity.with_active_scene_lock(scene_id, fn scene ->
      with {:ok, attrs} <-
             SceneReferenceIntegrity.lock_connection_endpoints(scene, attrs) do
        %SceneConnection{scene_id: scene.id}
        |> SceneConnection.create_changeset(attrs)
        |> Repo.insert()
      end
    end)
  end

  def update_connection(%SceneConnection{} = connection, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    SceneReferenceIntegrity.with_active_scene_lock(connection.scene_id, fn scene ->
      with {:ok, locked_connection} <-
             lock_connection_for_scene(connection.id, scene.id),
           {:ok, attrs} <-
             SceneReferenceIntegrity.lock_connection_endpoints(
               scene,
               locked_connection,
               attrs
             ) do
        locked_connection
        |> SceneConnection.update_changeset(attrs)
        |> Repo.update()
      end
    end)
  end

  @doc """
  Updates only the waypoints of a connection (optimized for drag).
  """
  def update_connection_waypoints(%SceneConnection{} = connection, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    SceneReferenceIntegrity.with_active_scene_lock(connection.scene_id, fn scene ->
      with {:ok, locked_connection} <-
             lock_connection_for_scene(connection.id, scene.id),
           {:ok, _attrs} <-
             SceneReferenceIntegrity.lock_connection_endpoints(
               scene,
               locked_connection,
               %{}
             ) do
        locked_connection
        |> SceneConnection.waypoints_changeset(attrs)
        |> Repo.update()
      end
    end)
  end

  def delete_connection(%SceneConnection{} = connection) do
    SceneReferenceIntegrity.with_active_scene_lock(connection.scene_id, fn scene ->
      with {:ok, locked_connection} <-
             lock_connection_for_scene(connection.id, scene.id) do
        Repo.delete(locked_connection)
      end
    end)
  end

  def change_connection(%SceneConnection{} = connection, attrs \\ %{}) do
    SceneConnection.update_changeset(connection, attrs)
  end

  defp lock_connection_for_scene(connection_id, scene_id) do
    case Repo.one(
           from(connection in SceneConnection,
             where:
               connection.id == ^connection_id and
                 connection.scene_id == ^scene_id,
             lock: "FOR UPDATE"
           )
         ) do
      %SceneConnection{} = connection ->
        {:ok, connection}

      nil ->
        {:error, :connection_not_found}
    end
  end
end
