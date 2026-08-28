defmodule Storyarn.Scenes.Editor.Queries.Connections do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.SceneConnection

  @doc "Lists all connections for a scene with both endpoints preloaded."
  def list_connections(scene_id) do
    Repo.all(
      from(connection in SceneConnection,
        where: connection.scene_id == ^scene_id,
        preload: [:from_pin, :to_pin]
      )
    )
  end

  def get_connection(scene_id, connection_id) do
    Repo.one(
      from(connection in SceneConnection,
        where: connection.scene_id == ^scene_id and connection.id == ^connection_id,
        preload: [:from_pin, :to_pin]
      )
    )
  end

  def get_connection!(scene_id, connection_id) do
    Repo.one!(
      from(connection in SceneConnection,
        where: connection.scene_id == ^scene_id and connection.id == ^connection_id,
        preload: [:from_pin, :to_pin]
      )
    )
  end
end
