defmodule Storyarn.Maps.PositionUtils do
  @moduledoc """
  Shared position utilities for map elements.
  """

  import Ecto.Query

  alias Storyarn.Repo

  @doc """
  Returns the next position value for a schema's items within a map.
  Equivalent to MAX(position) + 1, or 0 if no items exist.
  """
  def next_position(schema, map_id) do
    from(x in schema, where: x.map_id == ^map_id, select: max(x.position))
    |> Repo.one()
    |> case do
      nil -> 0
      max -> max + 1
    end
  end
end
