defmodule Storyarn.Shared.TreeOperations do
  @moduledoc """
  Generic tree helpers for hierarchical entities with parent_id and position.

  Extracted from context-specific TreeOperations modules to eliminate
  duplicated `update_position_only`, `reorder_source_container`,
  `add_parent_filter`, and the reorder transaction pattern.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo

  @doc """
  Reorders entities within a parent container.

  Takes a schema, project_id, parent_id (nil for root level), a list of entity IDs
  in the desired order, and a `list_fn` called as `list_fn.(project_id, parent_id)`
  to return the final ordered list.

  Returns `{:ok, entities}` with the reordered entities or `{:error, reason}`.
  """
  def reorder(schema, project_id, parent_id, ids, list_fn) when is_list(ids) do
    Repo.transaction(fn ->
      ids
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index()
      |> Enum.each(fn {id, index} ->
        update_scoped_position(schema, id, index, project_id, parent_id)
      end)

      list_fn.(project_id, parent_id)
    end)
  end

  @doc """
  Updates only the position of an entity by ID (scoped to non-deleted).
  """
  def update_position_only(schema, id, position) do
    from(s in schema, where: s.id == ^id and is_nil(s.deleted_at))
    |> Repo.update_all(set: [position: position])
  end

  @doc """
  Reorders a source container after a move operation by compacting positions.

  `list_fn` is called as `list_fn.(project_id, parent_id)` to get the
  current entities, then reassigns sequential positions starting from 0.
  """
  def reorder_source_container(schema, project_id, parent_id, list_fn) do
    list_fn.(project_id, parent_id)
    |> Enum.with_index()
    |> Enum.each(fn {entity, index} ->
      update_position_only(schema, entity.id, index)
    end)
  end

  @doc """
  Returns the next available position for a child of parent_id.
  """
  def next_position(schema, project_id, parent_id) do
    from(s in schema,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      select: max(s.position)
    )
    |> add_parent_filter(parent_id)
    |> Repo.one()
    |> case do
      nil -> 0
      max -> max + 1
    end
  end

  @doc """
  Lists items by parent_id, ordered by position then name.
  """
  def list_by_parent(schema, project_id, parent_id) do
    from(s in schema,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      order_by: [asc: s.position, asc: s.name]
    )
    |> add_parent_filter(parent_id)
    |> Repo.all()
  end

  @doc """
  Moves an entity to a new parent and position, reordering siblings.

  `list_fn` is called as `list_fn.(project_id, parent_id)` to get siblings.
  The schema must implement a `move_changeset/2` function.

  Returns `{:ok, updated_entity}` or `{:error, reason}`.
  """
  def move_to_position(schema, entity, new_parent_id, new_position, list_fn) do
    new_position = max(new_position, 0)

    Repo.transaction(fn ->
      case schema.move_changeset(entity, %{parent_id: new_parent_id, position: new_position})
           |> Repo.update() do
        {:ok, updated} ->
          apply_move(schema, entity, updated, new_parent_id, new_position, list_fn)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp apply_move(schema, entity, updated, new_parent_id, new_position, list_fn) do
    siblings = list_fn.(entity.project_id, new_parent_id)
    siblings_without_moved = Enum.reject(siblings, &(&1.id == entity.id))

    siblings_without_moved
    |> List.insert_at(new_position, updated)
    |> Enum.map(& &1.id)
    |> Enum.with_index()
    |> Enum.each(fn {id, index} ->
      update_position_only(schema, id, index)
    end)

    if entity.parent_id != new_parent_id do
      reorder_source_container(schema, entity.project_id, entity.parent_id, list_fn)
    end

    Repo.get!(schema, entity.id)
  end

  @doc """
  Walks upward from `id` through `parent_id` links in `schema`.
  Returns true if `potential_ancestor_id` is found in the ancestor chain.
  Depth-limited to 100 to prevent cycles.
  """
  def descendant?(schema, id, potential_ancestor_id, depth \\ 0)
  def descendant?(_schema, _id, _potential_ancestor_id, depth) when depth > 100, do: false

  def descendant?(schema, id, potential_ancestor_id, depth) do
    case Repo.get(schema, id) do
      nil -> false
      %{id: ^potential_ancestor_id} -> true
      %{parent_id: nil} -> false
      %{parent_id: parent_id} -> descendant?(schema, parent_id, potential_ancestor_id, depth + 1)
    end
  end

  @doc """
  Adds a parent_id filter to a query.
  Handles nil (root level) vs specific parent_id.
  """
  def add_parent_filter(query, nil), do: where(query, [s], is_nil(s.parent_id))
  def add_parent_filter(query, parent_id), do: where(query, [s], s.parent_id == ^parent_id)

  # Updates position scoped by project_id, parent_id, and non-deleted.
  defp update_scoped_position(schema, id, position, project_id, parent_id) do
    from(s in schema,
      where: s.id == ^id and s.project_id == ^project_id and is_nil(s.deleted_at)
    )
    |> add_parent_filter(parent_id)
    |> Repo.update_all(set: [position: position])
  end
end
