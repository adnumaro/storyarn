defmodule Storyarn.Sheets.TreeOperations do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.Persistence.ProjectRecord, as: Project
  alias Storyarn.Sheets.ProjectReferenceIntegrity
  alias Storyarn.Sheets.Sheet

  @doc """
  Reorders sheets within a parent container.

  Takes a project_id, parent_id (nil for root level), and a list of sheet IDs
  in the desired order. Updates all positions in a single transaction.

  Returns `{:ok, sheets}` with the reordered sheets or `{:error, reason}`.
  """
  def reorder_sheets(project_id, parent_id, sheet_ids) when is_list(sheet_ids) do
    Repo.transaction(fn ->
      lock_active_project!(project_id)
      normalized_parent_id = lock_parent_reference!(project_id, parent_id)
      normalized_sheet_ids = normalize_reorder_ids!(sheet_ids)
      lock_exact_sibling_set!(project_id, normalized_parent_id, normalized_sheet_ids)

      case reorder_siblings(project_id, normalized_parent_id, normalized_sheet_ids) do
        {:ok, sheets} -> sheets
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Moves a sheet to a new parent at a specific position, reordering siblings as needed.

  This function handles both same-parent reordering and cross-parent moves.
  It updates the sheet's parent_id, then rebuilds positions for all affected containers.

  Returns `{:ok, sheet}` with the moved sheet or `{:error, reason}`.
  """
  def move_sheet_to_position(%Sheet{} = sheet, new_parent_id, new_position) do
    Repo.transaction(fn ->
      lock_active_project!(sheet.project_id)
      locked_sheet = lock_active_sheet!(sheet.id, sheet.project_id)
      normalized_parent_id = lock_parent_reference!(sheet.project_id, new_parent_id)

      validate_parent_cycle!(locked_sheet.id, normalized_parent_id)

      case move_locked_sheet(locked_sheet, normalized_parent_id, new_position) do
        {:ok, moved_sheet} -> moved_sheet
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Returns the next available position for a sheet under parent_id.
  """
  def next_position(project_id, parent_id) do
    from(sheet in Sheet,
      where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
      select: max(sheet.position)
    )
    |> add_parent_filter(parent_id)
    |> Repo.one()
    |> case do
      nil -> 0
      max -> max + 1
    end
  end

  @doc """
  Walks upward from `id` through `parent_id` links.
  Returns true if `potential_ancestor_id` is found in the ancestor chain.
  Depth-limited to 100 to prevent cycles.
  """
  def descendant?(id, potential_ancestor_id, depth \\ 0)
  def descendant?(_id, _potential_ancestor_id, depth) when depth > 100, do: false

  def descendant?(id, potential_ancestor_id, depth) do
    case Repo.get(Sheet, id) do
      nil -> false
      %{id: ^potential_ancestor_id} -> true
      %{parent_id: nil} -> false
      %{parent_id: parent_id} -> descendant?(parent_id, potential_ancestor_id, depth + 1)
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
    Enum.map(Map.get(grouped, parent_id) || [], fn item ->
      Map.put(item, :children, do_build_subtree(grouped, item.id))
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

  @allowed_scope_fields ~w(project_id sheet_id block_id)
  @allowed_tables ~w(
    blocks
    sheets
    table_columns
    table_rows
  )

  # sobelow_skip ["SQL.Query"]
  def batch_set_positions(table, id_position_pairs, opts) when is_list(id_position_pairs) do
    {ids, positions} = Enum.unzip(id_position_pairs)

    {scope_field, scope_value} = Keyword.fetch!(opts, :scope)
    table = validated_identifier!(table, @allowed_tables, "table")
    scope_field = validated_identifier!(scope_field, @allowed_scope_fields, "scope_field")

    soft_delete = Keyword.get(opts, :soft_delete, false)
    parent_id = Keyword.get(opts, :parent_id, :skip)

    quoted_table = quote_identifier(table)

    {where_clause, params} =
      build_where_clause(scope_field, scope_value, soft_delete, parent_id, 3)

    sql = """
    UPDATE #{quoted_table}
    SET position = data.pos
    FROM unnest($1::bigint[], $2::int[]) AS data(id, pos)
    WHERE #{quoted_table}.id = data.id#{where_clause}
    """

    Repo.query!(sql, [ids, positions | params])
  end

  defp build_where_clause(scope_field, scope_value, soft_delete, parent_id, param_start) do
    quoted_scope_field = quote_identifier(scope_field)
    clauses = []
    params = []
    idx = param_start

    # Scope field
    clauses = [" AND #{quoted_scope_field} = $#{idx}" | clauses]
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

  defp validated_identifier!(identifier, allowlist, label) do
    if identifier in allowlist do
      identifier
    else
      raise ArgumentError,
            "#{label} must be one of #{inspect(allowlist)}, got: #{inspect(identifier)}"
    end
  end

  defp quote_identifier(identifier) do
    escaped = String.replace(identifier, ~s("), ~s(""))

    ~s("#{escaped}")
  end

  defp reorder_siblings(project_id, parent_id, ids) do
    pairs =
      ids
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index()

    Repo.transaction(fn ->
      batch_set_positions("sheets", pairs,
        scope: {"project_id", project_id},
        parent_id: parent_id,
        soft_delete: true
      )

      list_sheets_by_parent(project_id, parent_id)
    end)
  end

  defp move_locked_sheet(sheet, new_parent_id, new_position) do
    new_position = max(new_position, 0)

    Repo.transaction(fn ->
      case sheet
           |> Sheet.move_changeset(%{parent_id: new_parent_id, position: new_position})
           |> Repo.update() do
        {:ok, updated} ->
          apply_move(sheet, updated, new_parent_id, new_position)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp apply_move(sheet, updated, new_parent_id, new_position) do
    siblings = list_sheets_by_parent(sheet.project_id, new_parent_id)
    siblings_without_moved = Enum.reject(siblings, &(&1.id == sheet.id))

    pairs =
      siblings_without_moved
      |> List.insert_at(new_position, updated)
      |> Enum.with_index()
      |> Enum.map(fn {s, index} -> {s.id, index} end)

    batch_set_positions("sheets", pairs,
      scope: {"project_id", sheet.project_id},
      parent_id: new_parent_id,
      soft_delete: true
    )

    if sheet.parent_id != new_parent_id do
      reorder_source_container(sheet.project_id, sheet.parent_id)
    end

    Repo.get!(Sheet, sheet.id)
  end

  defp reorder_source_container(project_id, parent_id) do
    pairs =
      project_id
      |> list_sheets_by_parent(parent_id)
      |> Enum.with_index()
      |> Enum.map(fn {sheet, index} -> {sheet.id, index} end)

    batch_set_positions("sheets", pairs,
      scope: {"project_id", project_id},
      parent_id: parent_id,
      soft_delete: true
    )
  end

  defp list_sheets_by_parent(project_id, parent_id) do
    from(sheet in Sheet,
      where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
      order_by: [asc: sheet.position, asc: sheet.name]
    )
    |> add_parent_filter(parent_id)
    |> Repo.all()
  end

  defp lock_active_project!(project_id) do
    case Repo.one(
           from(project in Project,
             where: project.id == ^project_id,
             lock: "FOR UPDATE"
           )
         ) do
      %Project{deleted_at: nil} -> :ok
      %Project{} -> Repo.rollback(:project_not_active)
      nil -> Repo.rollback(:project_not_found)
    end
  end

  defp lock_active_sheet!(sheet_id, project_id) do
    case Repo.one(
           from(sheet in Sheet,
             where:
               sheet.id == ^sheet_id and sheet.project_id == ^project_id and
                 is_nil(sheet.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      %Sheet{} = sheet -> sheet
      nil -> Repo.rollback(:sheet_not_active)
    end
  end

  defp lock_parent_reference!(project_id, parent_id) do
    case ProjectReferenceIntegrity.lock_active_references(project_id, [
           {:sheet, :parent_id, parent_id}
         ]) do
      {:ok, [normalized_parent_id]} -> normalized_parent_id
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp normalize_reorder_ids!(sheet_ids) do
    normalized_ids =
      Enum.reduce_while(sheet_ids, [], fn sheet_id, ids ->
        case ProjectReferenceIntegrity.normalize_optional_id(sheet_id) do
          {:ok, normalized_id} when is_integer(normalized_id) ->
            {:cont, [normalized_id | ids]}

          _error ->
            {:halt, :error}
        end
      end)

    case normalized_ids do
      :error ->
        Repo.rollback({:invalid_sheet_reorder, sheet_ids})

      reversed_ids ->
        normalized_ids = Enum.reverse(reversed_ids)

        if length(normalized_ids) == length(Enum.uniq(normalized_ids)) do
          normalized_ids
        else
          Repo.rollback({:invalid_sheet_reorder, sheet_ids})
        end
    end
  end

  defp lock_exact_sibling_set!(project_id, parent_id, sheet_ids) do
    locked_ids =
      Sheet
      |> where(
        [sheet],
        sheet.project_id == ^project_id and
          is_nil(sheet.deleted_at)
      )
      |> add_parent_filter(parent_id)
      |> order_by([sheet], asc: sheet.id)
      |> lock("FOR UPDATE")
      |> select([sheet], sheet.id)
      |> Repo.all()

    if locked_ids == Enum.sort(sheet_ids) do
      :ok
    else
      Repo.rollback({:invalid_sheet_reorder, sheet_ids})
    end
  end

  defp validate_parent_cycle!(_sheet_id, nil), do: :ok

  defp validate_parent_cycle!(sheet_id, sheet_id), do: Repo.rollback(:would_create_cycle)

  defp validate_parent_cycle!(sheet_id, parent_id) do
    if descendant?(parent_id, sheet_id),
      do: Repo.rollback(:would_create_cycle),
      else: :ok
  end
end
