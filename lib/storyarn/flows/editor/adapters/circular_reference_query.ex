defmodule Storyarn.Flows.Editor.Adapters.CircularReferenceQuery do
  @moduledoc """
  PostgreSQL recursive-query adapter for batch Flow cycle detection.
  """

  alias Storyarn.Repo

  @sql """
  WITH RECURSIVE candidates AS (
    SELECT DISTINCT source_flow_id, target_flow_id
    FROM unnest($1::bigint[], $2::bigint[])
      AS pair(source_flow_id, target_flow_id)
  ),
  reference_walk AS (
    SELECT
      source_flow_id,
      target_flow_id,
      target_flow_id AS current_flow_id,
      ARRAY[]::bigint[] AS visited_flow_ids,
      0 AS depth
    FROM candidates

    UNION ALL

    SELECT
      walk.source_flow_id,
      walk.target_flow_id,
      reference.target_flow_id AS current_flow_id,
      array_append(walk.visited_flow_ids, walk.current_flow_id),
      walk.depth + 1
    FROM reference_walk AS walk
    JOIN LATERAL (
      SELECT DISTINCT
        (node.data->>'referenced_flow_id')::integer AS target_flow_id
      FROM flow_nodes AS node
      WHERE
        node.flow_id = walk.current_flow_id
        AND node.deleted_at IS NULL
        AND node.data->>'referenced_flow_id' ~ '^[0-9]+$'
        AND (
          node.type = 'subflow'
          OR (
            node.type = 'exit'
            AND node.data->>'exit_mode' = 'flow_reference'
          )
        )
    ) AS reference ON TRUE
    WHERE
      walk.depth <= $3
      AND walk.current_flow_id <> walk.source_flow_id
      AND NOT walk.current_flow_id = ANY(walk.visited_flow_ids)
  )
  SELECT source_flow_id, target_flow_id
  FROM reference_walk
  GROUP BY source_flow_id, target_flow_id
  HAVING bool_or(
    depth > $3
    OR current_flow_id = source_flow_id
  )
  """

  @spec circular_pairs([{integer(), integer()}], non_neg_integer()) ::
          MapSet.t({integer(), integer()})
  def circular_pairs(pairs, max_depth) do
    {source_flow_ids, target_flow_ids} = Enum.unzip(pairs)

    @sql
    |> Repo.query!([source_flow_ids, target_flow_ids, max_depth])
    |> Map.fetch!(:rows)
    |> MapSet.new(fn [source_flow_id, target_flow_id] ->
      {source_flow_id, target_flow_id}
    end)
  end
end
