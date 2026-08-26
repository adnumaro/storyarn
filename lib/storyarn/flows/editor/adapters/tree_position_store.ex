defmodule Storyarn.Flows.Editor.Adapters.TreePositionStore do
  @moduledoc """
  PostgreSQL bulk-update adapter for ordered Flow tree containers.
  """

  alias Storyarn.Repo

  @root_sql """
  UPDATE flows
  SET position = data.pos
  FROM unnest($1::bigint[], $2::int[]) AS data(id, pos)
  WHERE flows.id = data.id
    AND flows.project_id = $3
    AND flows.parent_id IS NULL
    AND flows.deleted_at IS NULL
  """

  @nested_sql """
  UPDATE flows
  SET position = data.pos
  FROM unnest($1::bigint[], $2::int[]) AS data(id, pos)
  WHERE flows.id = data.id
    AND flows.project_id = $3
    AND flows.parent_id = $4
    AND flows.deleted_at IS NULL
  """

  @spec update!([{integer(), non_neg_integer()}], integer(), integer() | nil) :: :ok
  # sobelow_skip ["SQL.Query"]
  def update!(id_position_pairs, project_id, nil) do
    {ids, positions} = Enum.unzip(id_position_pairs)
    Repo.query!(@root_sql, [ids, positions, project_id])
    :ok
  end

  # sobelow_skip ["SQL.Query"]
  def update!(id_position_pairs, project_id, parent_id) do
    {ids, positions} = Enum.unzip(id_position_pairs)
    Repo.query!(@nested_sql, [ids, positions, project_id, parent_id])
    :ok
  end
end
