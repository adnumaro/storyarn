defmodule Storyarn.GlobalSearch.FlowSearch do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.GlobalSearch.Persistence.FlowConnectionRecord
  alias Storyarn.GlobalSearch.Persistence.FlowNodeRecord
  alias Storyarn.GlobalSearch.Persistence.FlowRecord
  alias Storyarn.Repo
  alias Storyarn.Shared.SearchHelpers

  @default_limit 50
  @max_deep_limit 100
  @max_deep_offset 10_000

  @spec get(integer(), integer()) :: FlowRecord.t() | nil
  def get(project_id, flow_id) do
    Repo.one(
      from(flow in FlowRecord,
        where:
          flow.id == ^flow_id and flow.project_id == ^project_id and
            is_nil(flow.deleted_at)
      )
    )
  end

  @spec search_in_projects([integer()], String.t(), keyword()) :: [FlowRecord.t()]
  def search_in_projects(project_ids, query, opts \\ []) when is_list(project_ids) and is_binary(query) do
    limit = normalize_limit(Keyword.get(opts, :limit, @default_limit))
    query = String.trim(query)

    cond do
      project_ids == [] ->
        []

      query == "" ->
        Repo.all(
          from(flow in FlowRecord,
            where: flow.project_id in ^project_ids and is_nil(flow.deleted_at),
            order_by: [desc: flow.updated_at, desc: flow.id],
            limit: ^limit
          ),
          log: false
        )

      true ->
        pattern = "%#{SearchHelpers.sanitize_like_query(query)}%"

        Repo.all(
          from(flow in FlowRecord,
            where: flow.project_id in ^project_ids and is_nil(flow.deleted_at),
            where: ilike(flow.name, ^pattern) or ilike(flow.shortcut, ^pattern),
            order_by: [asc: flow.name],
            limit: ^limit
          ),
          log: false
        )
    end
  end

  @spec search_deep(integer(), String.t(), keyword()) :: [FlowRecord.t()]
  def search_deep(project_id, query, opts \\ []) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      search_in_projects([project_id], query, opts)
    else
      limit = normalize_deep_limit(Keyword.get(opts, :limit, @default_limit))
      offset = normalize_deep_offset(Keyword.get(opts, :offset, 0))
      exclude_id = Keyword.get(opts, :exclude_id)
      pattern = "%#{SearchHelpers.sanitize_like_query(query)}%"

      FlowRecord
      |> where(
        [flow],
        flow.project_id == ^project_id and is_nil(flow.deleted_at) and
          (ilike(flow.name, ^pattern) or ilike(flow.shortcut, ^pattern) or
             ilike(flow.description, ^pattern) or
             flow.id in subquery(node_content_subquery(project_id, pattern)) or
             flow.id in subquery(connection_content_subquery(project_id, pattern)))
      )
      |> maybe_exclude(exclude_id)
      |> order_by([flow], asc: flow.name)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all(log: false)
    end
  end

  defp node_content_subquery(project_id, pattern) do
    from(node in FlowNodeRecord,
      join: flow in FlowRecord,
      on: node.flow_id == flow.id,
      where:
        flow.project_id == ^project_id and is_nil(flow.deleted_at) and
          is_nil(node.deleted_at),
      where:
        fragment(
          """
          EXISTS (
            SELECT 1
            FROM jsonb_path_query(COALESCE(?, '{}'::jsonb), '$.** \\? (@.type() == "string")')
              AS authored(value)
            WHERE authored.value #>> '{}' ILIKE ?
          )
          """,
          node.data,
          ^pattern
        ),
      select: node.flow_id
    )
  end

  defp connection_content_subquery(project_id, pattern) do
    from(connection in FlowConnectionRecord,
      join: flow in FlowRecord,
      on: connection.flow_id == flow.id,
      where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
      where: ilike(connection.label, ^pattern),
      select: connection.flow_id
    )
  end

  defp maybe_exclude(query, nil), do: query
  defp maybe_exclude(query, id), do: where(query, [flow], flow.id != ^id)

  defp normalize_limit(limit) when is_integer(limit), do: max(limit, 1)
  defp normalize_limit(_limit), do: @default_limit

  defp normalize_deep_limit(limit) when is_integer(limit), do: limit |> max(1) |> min(@max_deep_limit)
  defp normalize_deep_limit(_limit), do: @default_limit

  defp normalize_deep_offset(offset) when is_integer(offset), do: offset |> max(0) |> min(@max_deep_offset)
  defp normalize_deep_offset(_offset), do: 0
end
