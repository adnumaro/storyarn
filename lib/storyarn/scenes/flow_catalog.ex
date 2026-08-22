defmodule Storyarn.Scenes.FlowCatalog do
  @moduledoc """
  Scene-owned read model for Flow metadata and executable graphs.

  Scenes deliberately reads the shared SQL tables through its own records so
  exploration can evolve independently from the Flow editor and its schemas.
  """

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Scenes.Persistence.FlowConnectionRecord
  alias Storyarn.Scenes.Persistence.FlowNodeRecord
  alias Storyarn.Scenes.Persistence.FlowRecord
  alias Storyarn.Shared.SearchHelpers

  @default_search_limit 25

  @spec list_flows(integer()) :: [FlowRecord.t()]
  def list_flows(project_id) do
    Repo.all(
      from flow in FlowRecord,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        order_by: [desc: flow.is_main, asc: flow.name]
    )
  end

  @spec search_flows(integer(), String.t(), keyword()) :: [FlowRecord.t()]
  def search_flows(project_id, query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_search_limit)
    offset = Keyword.get(opts, :offset, 0)
    query = String.trim(query)

    base =
      from flow in FlowRecord,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at)

    if query == "" do
      Repo.all(
        from flow in base,
          order_by: [desc: flow.updated_at],
          limit: ^limit,
          offset: ^offset
      )
    else
      term = "%#{SearchHelpers.sanitize_like_query(query)}%"

      Repo.all(
        from flow in base,
          where: ilike(flow.name, ^term) or ilike(flow.shortcut, ^term),
          order_by: [asc: flow.name],
          limit: ^limit,
          offset: ^offset
      )
    end
  end

  @spec get_flow(integer(), integer()) :: FlowRecord.t() | nil
  def get_flow(project_id, flow_id) do
    Repo.one(
      from flow in FlowRecord,
        where:
          flow.project_id == ^project_id and flow.id == ^flow_id and
            is_nil(flow.deleted_at)
    )
  end

  @spec get_runtime_graph(integer(), integer()) ::
          %{flow: FlowRecord.t(), nodes: map(), connections: [map()]} | nil
  def get_runtime_graph(project_id, flow_id) do
    case get_flow(project_id, flow_id) do
      nil ->
        nil

      flow ->
        %{
          flow: flow,
          nodes: runtime_nodes(project_id, flow.id),
          connections: runtime_connections(project_id, flow.id)
        }
    end
  end

  @spec runtime_nodes(integer(), integer()) :: map()
  def runtime_nodes(project_id, flow_id) do
    from(node in FlowNodeRecord,
      join: flow in FlowRecord,
      on: flow.id == node.flow_id,
      where:
        flow.project_id == ^project_id and flow.id == ^flow_id and
          is_nil(flow.deleted_at) and is_nil(node.deleted_at),
      order_by: [asc: node.inserted_at, asc: node.id],
      select: %{
        id: node.id,
        type: node.type,
        data: node.data,
        parent_id: node.parent_id
      }
    )
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  @spec runtime_connections(integer(), integer()) :: [map()]
  def runtime_connections(project_id, flow_id) do
    Repo.all(
      from connection in FlowConnectionRecord,
        join: flow in FlowRecord,
        on: flow.id == connection.flow_id,
        where:
          flow.project_id == ^project_id and flow.id == ^flow_id and
            is_nil(flow.deleted_at),
        order_by: [asc: connection.id],
        select: %{
          source_node_id: connection.source_node_id,
          source_pin: connection.source_pin,
          target_node_id: connection.target_node_id,
          target_pin: connection.target_pin
        }
    )
  end
end
