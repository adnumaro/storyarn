defmodule Storyarn.Sheets.Editor.Adapters.Postgres.BlockLayout do
  @moduledoc """
  PostgreSQL adapter for atomically replacing block layout positions and columns.

  The editor command validates and locks the complete block set before invoking
  this adapter; this module owns only the database-specific `unnest` statement.
  """

  alias Storyarn.Repo

  @update_sql """
  UPDATE blocks
  SET position = data.pos,
      column_group_id = data.gid::uuid,
      column_index = data.cidx
  FROM unnest($1::bigint[], $2::int[], $3::text[], $4::int[]) AS data(id, pos, gid, cidx)
  WHERE blocks.id = data.id AND blocks.sheet_id = $5 AND blocks.deleted_at IS NULL
  """

  # sobelow_skip ["SQL.Query"]
  def replace(ids, positions, group_ids, column_indexes, sheet_id) do
    Repo.query!(@update_sql, [ids, positions, group_ids, column_indexes, sheet_id])
  end
end
