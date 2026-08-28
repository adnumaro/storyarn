defmodule Storyarn.Flows.Editor.Queries.Flows do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Platform.Shared.SearchHelpers
  alias Storyarn.Repo

  @default_search_limit 25
  @max_deep_search_limit 50
  @max_deep_search_offset 1_000

  def default_search_limit, do: @default_search_limit

  def list(project_id) do
    Repo.all(
      from(flow in Flow,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        order_by: [desc: flow.is_main, asc: flow.name]
      )
    )
  end

  def list_tree(project_id) do
    project_id
    |> list_flat_tree()
    |> build_tree_from_flat_list()
  end

  @doc false
  def build_tree_from_flat_list(flows) do
    grouped = Enum.group_by(flows, & &1.parent_id)
    build_subtree(grouped, nil)
  end

  def search(project_id, query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_search_limit)
    offset = Keyword.get(opts, :offset, 0)
    exclude_id = Keyword.get(opts, :exclude_id)
    query_string = String.trim(query)

    base =
      maybe_exclude_flow(
        from(flow in Flow, where: flow.project_id == ^project_id and is_nil(flow.deleted_at)),
        exclude_id
      )

    if query_string == "" do
      Repo.all(
        from(flow in base,
          order_by: [desc: flow.updated_at],
          limit: ^limit,
          offset: ^offset
        ),
        log: false
      )
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query_string)}%"

      Repo.all(
        from(flow in base,
          where: ilike(flow.name, ^search_term) or ilike(flow.shortcut, ^search_term),
          order_by: [asc: flow.name],
          limit: ^limit,
          offset: ^offset
        ),
        log: false
      )
    end
  end

  def search_in_projects(project_ids, query, opts \\ []) when is_list(project_ids) and is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_search_limit)
    query_string = String.trim(query)

    cond do
      project_ids == [] ->
        []

      query_string == "" ->
        Repo.all(
          from(flow in Flow,
            where: flow.project_id in ^project_ids and is_nil(flow.deleted_at),
            order_by: [desc: flow.updated_at, desc: flow.id],
            limit: ^limit
          ),
          log: false
        )

      true ->
        search_term = "%#{SearchHelpers.sanitize_like_query(query_string)}%"

        Repo.all(
          from(flow in Flow,
            where: flow.project_id in ^project_ids and is_nil(flow.deleted_at),
            where: ilike(flow.name, ^search_term) or ilike(flow.shortcut, ^search_term),
            order_by: [asc: flow.name],
            limit: ^limit
          ),
          log: false
        )
    end
  end

  def search_deep(project_id, query, opts \\ []) when is_binary(query) do
    query_string = String.trim(query)

    if query_string == "" do
      search(project_id, query_string, opts)
    else
      limit = bounded_deep_search_limit(opts)
      offset = bounded_deep_search_offset(opts)
      exclude_id = Keyword.get(opts, :exclude_id)
      search_term = "%#{SearchHelpers.sanitize_like_query(query_string)}%"

      from(flow in Flow,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        where:
          ilike(flow.name, ^search_term) or
            ilike(flow.shortcut, ^search_term) or
            ilike(flow.description, ^search_term) or
            flow.id in subquery(node_content_subquery(project_id, search_term)) or
            flow.id in subquery(connection_content_subquery(project_id, search_term)),
        order_by: [asc: flow.name],
        limit: ^limit,
        offset: ^offset
      )
      |> maybe_exclude_flow(exclude_id)
      |> Repo.all(log: false)
    end
  end

  def get(project_id, flow_id) do
    active_nodes_query =
      from(node in FlowNode,
        where: is_nil(node.deleted_at),
        order_by: [asc: node.inserted_at]
      )

    Repo.one(
      from(flow in Flow,
        where: flow.project_id == ^project_id and flow.id == ^flow_id and is_nil(flow.deleted_at),
        preload: [:connections, nodes: ^active_nodes_query]
      )
    )
  end

  def get_brief(project_id, flow_id) do
    Repo.one(
      from(flow in Flow,
        where: flow.project_id == ^project_id and flow.id == ^flow_id and is_nil(flow.deleted_at)
      )
    )
  end

  def get!(project_id, flow_id) do
    active_nodes_query =
      from(node in FlowNode,
        where: is_nil(node.deleted_at),
        order_by: [asc: node.inserted_at]
      )

    Repo.one!(
      from(flow in Flow,
        where: flow.project_id == ^project_id and flow.id == ^flow_id and is_nil(flow.deleted_at),
        preload: [:connections, nodes: ^active_nodes_query]
      )
    )
  end

  def get_including_deleted(project_id, flow_id) do
    Repo.one(
      from(flow in Flow,
        where: flow.project_id == ^project_id and flow.id == ^flow_id,
        preload: [:nodes, :connections]
      )
    )
  end

  def count(project_id) do
    Repo.aggregate(
      from(flow in Flow,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at)
      ),
      :count
    )
  end

  def count_nodes(project_id) do
    Repo.aggregate(
      from(node in FlowNode,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where:
          flow.project_id == ^project_id and is_nil(flow.deleted_at) and
            is_nil(node.deleted_at)
      ),
      :count
    )
  end

  defp list_flat_tree(project_id) do
    Repo.all(
      from(flow in Flow,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        order_by: [asc: flow.position, asc: flow.name]
      )
    )
  end

  defp build_subtree(grouped, parent_id) do
    Enum.map(Map.get(grouped, parent_id, []), fn flow ->
      Map.put(flow, :children, build_subtree(grouped, flow.id))
    end)
  end

  defp maybe_exclude_flow(query, nil), do: query
  defp maybe_exclude_flow(query, id), do: from(flow in query, where: flow.id != ^id)

  defp node_content_subquery(project_id, search_term) do
    from(node in FlowNode,
      join: flow in Flow,
      on: node.flow_id == flow.id,
      where: flow.project_id == ^project_id and is_nil(flow.deleted_at) and is_nil(node.deleted_at),
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
          ^search_term
        ),
      select: node.flow_id
    )
  end

  defp connection_content_subquery(project_id, search_term) do
    from(connection in FlowConnection,
      join: flow in Flow,
      on: flow.id == connection.flow_id,
      where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
      where: ilike(connection.label, ^search_term),
      select: connection.flow_id
    )
  end

  defp bounded_deep_search_limit(opts) do
    case Keyword.get(opts, :limit, @default_search_limit) do
      limit when is_integer(limit) -> limit |> max(1) |> min(@max_deep_search_limit)
      _invalid -> @default_search_limit
    end
  end

  defp bounded_deep_search_offset(opts) do
    case Keyword.get(opts, :offset, 0) do
      offset when is_integer(offset) -> offset |> max(0) |> min(@max_deep_search_offset)
      _invalid -> 0
    end
  end
end
