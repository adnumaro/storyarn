defmodule Storyarn.Maps.TreeOperations do
  @moduledoc false

  import Ecto.Query, warn: false

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
      do_move_map_to_position(map, new_parent_id, new_position)
    end
  end

  @doc """
  Gets the next available position for a new map in the given container.
  """
  def next_position(project_id, parent_id) do
    from(m in MapSchema,
      where: m.project_id == ^project_id and is_nil(m.deleted_at),
      select: max(m.position)
    )
    |> SharedTree.add_parent_filter(parent_id)
    |> Repo.one()
    |> case do
      nil -> 0
      max -> max + 1
    end
  end

  @doc """
  Lists maps for a given parent (or root level).
  Excludes soft-deleted maps and orders by position then name.
  """
  def list_maps_by_parent(project_id, parent_id) do
    from(m in MapSchema,
      where: m.project_id == ^project_id and is_nil(m.deleted_at),
      order_by: [asc: m.position, asc: m.name]
    )
    |> SharedTree.add_parent_filter(parent_id)
    |> Repo.all()
  end

  defp do_move_map_to_position(%MapSchema{} = map, new_parent_id, new_position) do
    new_position = max(new_position, 0)

    Repo.transaction(fn ->
      old_parent_id = map.parent_id
      project_id = map.project_id

      case map
           |> MapSchema.move_changeset(%{parent_id: new_parent_id, position: new_position})
           |> Repo.update() do
        {:ok, updated_map} ->
          apply_move_result(
            project_id,
            map,
            updated_map,
            new_parent_id,
            new_position,
            old_parent_id
          )

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp apply_move_result(project_id, map, updated_map, new_parent_id, new_position, old_parent_id) do
    siblings = list_maps_by_parent(project_id, new_parent_id)
    siblings_without_moved = Enum.reject(siblings, &(&1.id == map.id))

    new_order =
      siblings_without_moved
      |> List.insert_at(new_position, updated_map)
      |> Enum.map(& &1.id)

    new_order
    |> Enum.with_index()
    |> Enum.each(fn {map_id, index} ->
      SharedTree.update_position_only(MapSchema, map_id, index)
    end)

    maybe_reorder_source(project_id, old_parent_id, new_parent_id)
    Repo.get!(MapSchema, map.id)
  end

  defp maybe_reorder_source(_project_id, parent_id, parent_id), do: :ok

  defp maybe_reorder_source(project_id, old_parent_id, _new_parent_id) do
    SharedTree.reorder_source_container(
      MapSchema,
      project_id,
      old_parent_id,
      &list_maps_by_parent/2
    )
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
