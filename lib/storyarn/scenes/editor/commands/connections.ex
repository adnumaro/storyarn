defmodule Storyarn.Scenes.Editor.Commands.Connections do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.Repo
  alias Storyarn.Scenes.Editor.Commands.ReferenceIntegrity
  alias Storyarn.Scenes.Editor.Commands.Scenes
  alias Storyarn.Scenes.SceneConnection

  @doc """
  Creates a route between pinned or free points.
  Validates that any pinned endpoints belong to the same scene.
  """
  def create_connection(scene_id, attrs) do
    attrs = MapAccess.stringify_keys(attrs)

    scene_id
    |> ReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, attrs} <-
             ReferenceIntegrity.lock_connection_endpoints(scene, attrs) do
        %SceneConnection{scene_id: scene.id}
        |> SceneConnection.create_changeset(attrs)
        |> Repo.insert()
      end
    end)
    |> Scenes.broadcast_scene_dashboard_result(scene_id)
  end

  def update_connection(%SceneConnection{} = connection, attrs) do
    attrs = MapAccess.stringify_keys(attrs)

    connection.scene_id
    |> ReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, locked_connection} <-
             lock_connection_for_scene(connection.id, scene.id),
           {:ok, attrs} <-
             ReferenceIntegrity.lock_connection_endpoints(
               scene,
               locked_connection,
               attrs
             ) do
        locked_connection
        |> SceneConnection.update_changeset(attrs)
        |> Repo.update()
      end
    end)
    |> Scenes.broadcast_scene_dashboard_result(connection.scene_id)
  end

  @doc """
  Updates only the waypoints of a connection (optimized for drag).
  """
  def update_connection_waypoints(%SceneConnection{} = connection, attrs) do
    attrs = MapAccess.stringify_keys(attrs)

    connection.scene_id
    |> ReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, locked_connection} <-
             lock_connection_for_scene(connection.id, scene.id),
           {:ok, _attrs} <-
             ReferenceIntegrity.lock_connection_endpoints(
               scene,
               locked_connection,
               %{}
             ) do
        locked_connection
        |> SceneConnection.waypoints_changeset(attrs)
        |> Repo.update()
      end
    end)
    |> Scenes.broadcast_scene_dashboard_result(connection.scene_id)
  end

  def delete_connection(%SceneConnection{} = connection) do
    connection.scene_id
    |> ReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, locked_connection} <-
             lock_connection_for_scene(connection.id, scene.id) do
        Repo.delete(locked_connection)
      end
    end)
    |> Scenes.broadcast_scene_dashboard_result(connection.scene_id)
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
