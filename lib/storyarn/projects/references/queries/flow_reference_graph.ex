defmodule Storyarn.Projects.FlowReferenceGraph do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Persistence.FlowNodeRecord
  alias Storyarn.Repo

  @max_reference_depth 20
  @batch_circular_references_sql """
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

  def has_circular_reference?(source_flow_id, target_flow_id) do
    check_circular(source_flow_id, target_flow_id, MapSet.new(), 0)
  end

  def circular_reference_pairs([]), do: MapSet.new()

  def circular_reference_pairs(pairs) when is_list(pairs) do
    pairs = pairs |> Enum.uniq() |> Enum.sort()
    {source_flow_ids, target_flow_ids} = Enum.unzip(pairs)

    @batch_circular_references_sql
    |> Repo.query!([source_flow_ids, target_flow_ids, @max_reference_depth])
    |> Map.fetch!(:rows)
    |> MapSet.new(fn [source_flow_id, target_flow_id] ->
      {source_flow_id, target_flow_id}
    end)
  end

  defp check_circular(_source_flow_id, _current_flow_id, _visited, depth) when depth > @max_reference_depth, do: true

  defp check_circular(source_flow_id, source_flow_id, _visited, _depth), do: true

  defp check_circular(source_flow_id, current_flow_id, visited, depth) do
    if MapSet.member?(visited, current_flow_id) do
      false
    else
      visited = MapSet.put(visited, current_flow_id)

      current_flow_id
      |> referenced_flow_ids()
      |> Enum.any?(&check_circular(source_flow_id, &1, visited, depth + 1))
    end
  end

  defp referenced_flow_ids(flow_id) do
    Repo.all(
      from(node in FlowNodeRecord,
        where:
          node.flow_id == ^flow_id and is_nil(node.deleted_at) and
            ((node.type == "subflow" and not is_nil(fragment("?->>'referenced_flow_id'", node.data))) or
               (node.type == "exit" and fragment("?->>'exit_mode'", node.data) == "flow_reference" and
                  not is_nil(fragment("?->>'referenced_flow_id'", node.data)))),
        where: fragment("?->>'referenced_flow_id' ~ '^[0-9]+$'", node.data),
        select: fragment("(?->>'referenced_flow_id')::integer", node.data)
      )
    )
  end
end
