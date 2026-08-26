defmodule Storyarn.Flows.Editor.Adapters.NodePositionStore do
  @moduledoc """
  PostgreSQL bulk-update adapter for Flow node positions.
  """

  alias Storyarn.Repo

  @sql """
  UPDATE flow_nodes
  SET position_x = data.x, position_y = data.y, updated_at = $4
  FROM unnest($1::bigint[], $2::float8[], $3::float8[]) AS data(id, x, y)
  WHERE flow_nodes.id = data.id AND flow_nodes.flow_id = $5 AND flow_nodes.deleted_at IS NULL
  """

  @spec update!([integer()], [float()], [float()], DateTime.t(), integer()) :: Postgrex.Result.t()
  def update!(ids, xs, ys, now, flow_id) do
    Repo.query!(@sql, [ids, xs, ys, now, flow_id])
  end
end
