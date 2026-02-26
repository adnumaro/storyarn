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
    pairs =
      ids
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index()

    table = schema.__schema__(:source)

    Repo.transaction(fn ->
      batch_set_positions(table, pairs,
        scope: {"project_id", project_id},
        parent_id: parent_id,
        soft_delete: true
      )

      list_fn.(project_id, parent_id)
    end)
  end

  @doc """
  Batch-updates positions for multiple entities in a single query using unnest.

  `table` is the PostgreSQL table name (string).
  `id_position_pairs` is a list of `{id, position}` tuples.

  Options:
  - `:scope` - `{field_name, value}` tuple for scoping (e.g. `{"sheet_id", 42}`)
  - `:parent_id` - parent_id value for additional filtering (nil = IS NULL filter)
  - `:soft_delete` - if true, adds `AND deleted_at IS NULL` (default: false)
  """
  def batch_set_positions(_table, [], _opts), do: :ok

  def batch_set_positions(table, id_position_pairs, opts) when is_list(id_position_pairs) do
    {ids, positions} = Enum.unzip(id_position_pairs)

    {scope_field, scope_value} = Keyword.fetch!(opts, :scope)
    soft_delete = Keyword.get(opts, :soft_delete, false)
    parent_id = Keyword.get(opts, :parent_id, :skip)

    {where_clause, params} =
      build_where_clause(scope_field, scope_value, soft_delete, parent_id, 3)

    sql = """
    UPDATE #{table}
    SET position = data.pos
    FROM unnest($1::bigint[], $2::int[]) AS data(id, pos)
    WHERE #{table}.id = data.id#{where_clause}
    """

    Repo.query!(sql, [ids, positions | params])
  end

  defp build_where_clause(scope_field, scope_value, soft_delete, parent_id, param_start) do
    clauses = []
    params = []
    idx = param_start

    # Scope field
    clauses = [" AND #{scope_field} = $#{idx}" | clauses]
    params = [scope_value | params]
    idx = idx + 1

    # Soft delete
    {clauses, params, idx} =
      if soft_delete do
        {[" AND deleted_at IS NULL" | clauses], params, idx}
      else
        {clauses, params, idx}
      end

    # Parent id filter
    {clauses, params, _idx} =
      case parent_id do
        :skip ->
          {clauses, params, idx}

        nil ->
          {[" AND parent_id IS NULL" | clauses], params, idx}

        value ->
          {[" AND parent_id = $#{idx}" | clauses], [value | params], idx + 1}
      end

    {clauses |> Enum.reverse() |> Enum.join(), Enum.reverse(params)}
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
    table = schema.__schema__(:source)

    pairs =
      list_fn.(project_id, parent_id)
      |> Enum.with_index()
      |> Enum.map(fn {entity, index} -> {entity.id, index} end)

    batch_set_positions(table, pairs,
      scope: {"project_id", project_id},
      parent_id: parent_id,
      soft_delete: true
    )
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
    table = schema.__schema__(:source)
    siblings = list_fn.(entity.project_id, new_parent_id)
    siblings_without_moved = Enum.reject(siblings, &(&1.id == entity.id))

    pairs =
      siblings_without_moved
      |> List.insert_at(new_position, updated)
      |> Enum.with_index()
      |> Enum.map(fn {s, index} -> {s.id, index} end)

    batch_set_positions(table, pairs,
      scope: {"project_id", entity.project_id},
      parent_id: new_parent_id,
      soft_delete: true
    )

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

  @doc """
  Builds a nested tree structure from a flat list of entities with `parent_id` and `id` fields.
  Entities with `parent_id` matching `root_parent_id` (default `nil`) become root nodes.
  Each entity gets a `:children` key populated with its direct children, recursively.
  """
  def build_tree_from_flat_list(items, root_parent_id \\ nil) do
    grouped = Enum.group_by(items, & &1.parent_id)
    do_build_subtree(grouped, root_parent_id)
  end

  defp do_build_subtree(grouped, parent_id) do
    (Map.get(grouped, parent_id) || [])
    |> Enum.map(fn item ->
      Map.put(item, :children, do_build_subtree(grouped, item.id))
    end)
  end
end
