defmodule Storyarn.Sheets.Editor.Adapters.Postgres.Positions do
  @moduledoc """
  PostgreSQL adapter for atomically assigning ordered positions with `unnest`.

  Identifier interpolation is restricted to fixed allowlists; business scope,
  completeness, and lock ownership are decided by the calling editor command.
  """

  alias Storyarn.Repo

  @allowed_scope_fields ~w(project_id sheet_id block_id)
  @allowed_tables ~w(blocks sheets table_columns table_rows)

  def batch_set(_table, [], _opts), do: :ok

  # sobelow_skip ["SQL.Query"]
  def batch_set(table, id_position_pairs, opts) when is_list(id_position_pairs) do
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
    clauses = [" AND #{quoted_scope_field} = $#{param_start}"]
    params = [scope_value]
    next_index = param_start + 1

    clauses = if soft_delete, do: [" AND deleted_at IS NULL" | clauses], else: clauses

    {clauses, params} =
      case parent_id do
        :skip -> {clauses, params}
        nil -> {[" AND parent_id IS NULL" | clauses], params}
        value -> {[" AND parent_id = $#{next_index}" | clauses], [value | params]}
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
end
