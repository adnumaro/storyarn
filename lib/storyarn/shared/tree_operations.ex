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
