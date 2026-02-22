defmodule Storyarn.Maps.TreeOperations do
  @moduledoc false

  alias Storyarn.Maps.Map, as: MapSchema
  alias Storyarn.Repo
  alias Storyarn.Shared.TreeOperations, as: SharedTree

  @doc """
  Reorders maps within a parent container.

  Takes a project_id, parent_id (nil for root level), and a list of map IDs
  in the desired order. Updates all positions in a single transaction.

  Returns `{:ok, maps}` with the reordered maps or `{:error, reason}`.
  """
  def reorder_maps(project_id, parent_id, map_ids) when is_list(map_ids) do
    SharedTree.reorder(MapSchema, project_id, parent_id, map_ids, &list_maps_by_parent/2)
  end

  @doc """
  Moves a map to a new parent at a specific position, reordering siblings as needed.

  This function handles both same-parent reordering and cross-parent moves.
  It updates the map's parent_id, then rebuilds positions for all affected containers.

  Returns `{:ok, map}` with the moved map or `{:error, reason}`.
  """
  def move_map_to_position(%MapSchema{} = map, new_parent_id, new_position) do
    if new_parent_id && descendant?(new_parent_id, map.id) do
      {:error, :cyclic_parent}
    else
      SharedTree.move_to_position(
        MapSchema,
        map,
        new_parent_id,
        new_position,
        &list_maps_by_parent/2
      )
    end
  end

  @doc """
  Gets the next available position for a new map in the given container.
  """
  def next_position(project_id, parent_id) do
    SharedTree.next_position(MapSchema, project_id, parent_id)
  end

  @doc """
  Lists maps for a given parent (or root level).
  Excludes soft-deleted maps and orders by position then name.
  """
  def list_maps_by_parent(project_id, parent_id) do
    SharedTree.list_by_parent(MapSchema, project_id, parent_id)
  end

  # Walks upward from map_id through parent_id links.
  # Returns true if potential_ancestor_id is found in the chain.
  # Depth limit prevents stack overflow if the DB has a cycle.
  defp descendant?(map_id, potential_ancestor_id, depth \\ 0)
  defp descendant?(_map_id, _potential_ancestor_id, depth) when depth > 100, do: false

  defp descendant?(map_id, potential_ancestor_id, depth) do
    case Repo.get(MapSchema, map_id) do
      nil -> false
      %MapSchema{id: id} when id == potential_ancestor_id -> true
      %MapSchema{parent_id: nil} -> false
      %MapSchema{parent_id: parent_id} -> descendant?(parent_id, potential_ancestor_id, depth + 1)
    end
  end
end
