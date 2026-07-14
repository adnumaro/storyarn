defmodule Storyarn.Scenes.PositionUtils do
  @moduledoc """
  Shared position utilities for map elements.
  """

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene

  @doc "Serializes position allocation for all elements belonging to a scene."
  def with_scene_lock(scene_id, fun) when is_function(fun, 0) do
    Repo.transaction(fn ->
      Repo.one!(from(scene in Scene, where: scene.id == ^scene_id, lock: "FOR UPDATE"))

      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Returns the next position value for a schema's items within a map.
  Equivalent to MAX(position) + 1, or 0 if no items exist.
  """
  def next_position(schema, scene_id) do
    from(x in schema, where: x.scene_id == ^scene_id, select: max(x.position))
    |> Repo.one()
    |> case do
      nil -> 0
      max -> max + 1
    end
  end
end
