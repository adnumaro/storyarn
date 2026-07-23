defmodule Storyarn.Flows.ContextQueries do
  @moduledoc """
  Bounded read helpers for the AI context engine.

  These queries always require an already-authorized project id and never load
  a full flow or project graph.
  """

  import Ecto.Query

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo

  @spec get_node(integer(), integer()) :: {Flow.t(), FlowNode.t()} | nil
  def get_node(project_id, node_id) do
    Repo.one(
      from(node in FlowNode,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where:
          flow.project_id == ^project_id and node.id == ^node_id and
            is_nil(flow.deleted_at) and is_nil(node.deleted_at),
        select: {flow, node}
      )
    )
  end

  @spec list_flow_briefs(integer(), [integer()], pos_integer()) :: [Flow.t()]
  def list_flow_briefs(_project_id, [], _limit), do: []

  def list_flow_briefs(project_id, flow_ids, limit) do
    Repo.all(
      from(flow in Flow,
        where:
          flow.project_id == ^project_id and flow.id in ^flow_ids and
            is_nil(flow.deleted_at),
        order_by: [asc: flow.id],
        limit: ^limit
      )
    )
  end

  @spec neighborhood(integer(), integer(), non_neg_integer(), pos_integer(), pos_integer()) ::
          {:ok, map()} | {:error, :context_missing}
  def neighborhood(project_id, node_id, max_depth, max_fan_out, max_entities) do
    case get_node(project_id, node_id) do
      {%Flow{} = flow, %FlowNode{} = node} ->
        state = %{
          flow: flow,
          nodes: %{node.id => {node, 0}},
          connections: %{},
          frontier: [node.id],
          excluded: []
        }

        {:ok, walk(state, 0, max_depth, max_fan_out, max_entities)}

      nil ->
        {:error, :context_missing}
    end
  end

  defp walk(state, depth, max_depth, _max_fan_out, _max_entities) when depth >= max_depth or state.frontier == [] do
    Map.put(state, :depth_limited?, depth >= max_depth and has_unseen_neighbors?(state))
  end

  defp walk(state, depth, max_depth, max_fan_out, max_entities) do
    {connections, fan_out_excluded} =
      state.frontier
      |> Enum.sort()
      |> Enum.reduce({[], []}, fn node_id, {connections, excluded} ->
        rows = adjacent_connections(state.flow.id, node_id, max_fan_out + 1)
        {allowed, overflow} = Enum.split(rows, max_fan_out)

        overflow_excluded =
          Enum.map(overflow, fn connection ->
            %{
              "type" => "flow_connection",
              "id" => connection.id,
              "reason" => "fan_out_limit"
            }
          end)

        {connections ++ allowed, excluded ++ overflow_excluded}
      end)

    connections =
      connections
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.id)

    discovered_connection_ids =
      connections
      |> MapSet.new(& &1.id)
      |> MapSet.union(MapSet.new(Map.keys(state.connections)))

    fan_out_excluded =
      fan_out_excluded
      |> Enum.reject(&MapSet.member?(discovered_connection_ids, &1["id"]))
      |> Enum.uniq_by(& &1["id"])

    {connections, next_ids, entity_excluded} =
      select_within_entity_budget(connections, state, max_entities)

    next_nodes = list_nodes(state.flow.id, next_ids)

    nodes =
      Enum.reduce(next_nodes, state.nodes, fn node, acc ->
        Map.put_new(acc, node.id, {node, depth + 1})
      end)

    connections =
      Enum.reduce(connections, state.connections, fn connection, acc ->
        Map.put_new(acc, connection.id, {connection, depth + 1})
      end)

    next_state = %{
      state
      | nodes: nodes,
        connections: connections,
        frontier: Enum.map(next_nodes, & &1.id),
        excluded: state.excluded ++ fan_out_excluded ++ entity_excluded
    }

    walk(next_state, depth + 1, max_depth, max_fan_out, max_entities)
  end

  defp select_within_entity_budget(connections, state, max_entities) do
    known_nodes = MapSet.new(Map.keys(state.nodes))
    known_connections = MapSet.new(Map.keys(state.connections))
    initial_count = 1 + MapSet.size(known_nodes) + MapSet.size(known_connections)

    connections
    |> Enum.reject(&MapSet.member?(known_connections, &1.id))
    |> Enum.reduce(
      {[], known_nodes, initial_count, []},
      &maybe_include_connection(&1, &2, max_entities)
    )
    |> then(fn {included, nodes, _count, excluded} ->
      next_ids =
        nodes
        |> MapSet.difference(known_nodes)
        |> MapSet.to_list()
        |> Enum.sort()

      {Enum.reverse(included), next_ids, excluded}
    end)
  end

  defp maybe_include_connection(connection, {included, nodes, count, excluded}, max_entities) do
    endpoint_ids = Enum.uniq([connection.source_node_id, connection.target_node_id])
    new_node_ids = Enum.reject(endpoint_ids, &MapSet.member?(nodes, &1))
    required_slots = 1 + length(new_node_ids)

    if count + required_slots <= max_entities do
      {
        [connection | included],
        Enum.reduce(new_node_ids, nodes, &MapSet.put(&2, &1)),
        count + required_slots,
        excluded
      }
    else
      dropped =
        [%{"type" => "flow_connection", "id" => connection.id, "reason" => "entity_limit"}] ++
          Enum.map(new_node_ids, &%{"type" => "flow_node", "id" => &1, "reason" => "entity_limit"})

      {included, nodes, count, dropped ++ excluded}
    end
  end

  defp adjacent_connections(flow_id, node_id, limit) do
    Repo.all(
      from(connection in FlowConnection,
        join: source in FlowNode,
        on: source.id == connection.source_node_id,
        join: target in FlowNode,
        on: target.id == connection.target_node_id,
        where:
          connection.flow_id == ^flow_id and
            (connection.source_node_id == ^node_id or connection.target_node_id == ^node_id) and
            is_nil(source.deleted_at) and is_nil(target.deleted_at),
        order_by: [asc: connection.id],
        limit: ^limit
      )
    )
  end

  defp list_nodes(_flow_id, []), do: []

  defp list_nodes(flow_id, ids) do
    Repo.all(
      from(node in FlowNode,
        where: node.flow_id == ^flow_id and node.id in ^ids and is_nil(node.deleted_at),
        order_by: [asc: node.id]
      )
    )
  end

  defp has_unseen_neighbors?(state) do
    visited = Map.keys(state.nodes)

    Enum.any?(state.frontier, fn node_id ->
      Repo.exists?(
        from(connection in FlowConnection,
          join: source in FlowNode,
          on: source.id == connection.source_node_id,
          join: target in FlowNode,
          on: target.id == connection.target_node_id,
          where:
            connection.flow_id == ^state.flow.id and
              (connection.source_node_id == ^node_id or connection.target_node_id == ^node_id) and
              is_nil(source.deleted_at) and is_nil(target.deleted_at) and
              (connection.source_node_id not in ^visited or connection.target_node_id not in ^visited),
          select: 1
        )
      )
    end)
  end
end
