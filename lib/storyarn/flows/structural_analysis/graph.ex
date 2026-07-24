defmodule Storyarn.Flows.StructuralAnalysis.Graph do
  @moduledoc """
  Pure structural-graph computation for a single flow.

  Single implementation of the graph semantics shared by the flow editor
  serializer, the dashboards, and the structural-analysis panel: pin-validated
  connections, virtual jump→hub edges, cycle-safe reachability from every
  Entry, dead ends, isolated nodes, and orphan hubs.

  Operates on plain node maps (`%{id, type, data}`) and connection maps
  (`%{id, source_node_id, source_pin, target_node_id, target_pin}`) — see
  `Storyarn.Flows.StructuralAnalysis.Topology`.
  """

  alias Storyarn.Flows.NodeConnectionRules

  defstruct nodes: [],
            valid_connections: [],
            invalid_connections: [],
            invalid_output_pins: %{},
            invalid_input_pins: %{},
            connected_output_pins: %{},
            entry_ids: [],
            unreachable_ids: MapSet.new(),
            dead_end_ids: MapSet.new(),
            isolated_ids: MapSet.new(),
            orphan_hub_ids: MapSet.new(),
            missing_output_pins: %{}

  @type node_map :: %{id: integer(), type: String.t(), data: map()}
  @type connection_map :: %{
          id: integer(),
          source_node_id: integer(),
          source_pin: String.t(),
          target_node_id: integer(),
          target_pin: String.t()
        }
  @type t :: %__MODULE__{}

  @doc """
  Computes the full structural graph state for the given active nodes and
  connections. Connections whose endpoints are not in `nodes` must already be
  filtered out by the caller (topology building).
  """
  @spec compute([node_map()], [connection_map()]) :: t()
  def compute(nodes, connections) do
    {valid_connections, invalid_output_pins, invalid_input_pins} =
      classify_connections(nodes, connections)

    valid_ids = MapSet.new(valid_connections, & &1.id)
    invalid_connections = Enum.reject(connections, &MapSet.member?(valid_ids, &1.id))
    entry_ids = for n <- nodes, n.type == "entry", do: n.id
    unreachable_ids = compute_unreachable_ids(nodes, valid_connections, entry_ids)
    dead_end_ids = compute_dead_end_ids(nodes, valid_connections)
    connected_output_pins = connected_output_pins(valid_connections)

    %__MODULE__{
      nodes: nodes,
      valid_connections: valid_connections,
      invalid_connections: invalid_connections,
      invalid_output_pins: invalid_output_pins,
      invalid_input_pins: invalid_input_pins,
      connected_output_pins: connected_output_pins,
      entry_ids: entry_ids,
      unreachable_ids: unreachable_ids,
      dead_end_ids: dead_end_ids,
      isolated_ids: compute_isolated_ids(nodes, valid_connections),
      orphan_hub_ids: compute_orphan_hub_ids(nodes, valid_connections),
      missing_output_pins: compute_missing_output_pins(nodes, connected_output_pins)
    }
  end

  @doc "Missing (unconnected) required output pins for one node, `[]` when none."
  @spec missing_output_pins_for(t(), node_map()) :: [String.t()]
  def missing_output_pins_for(%__MODULE__{} = graph, node) do
    Map.get(graph.missing_output_pins, node.id, [])
  end

  # ===========================================================================
  # Pin validation
  # ===========================================================================

  defp classify_connections(nodes, connections) do
    nodes_by_id = Map.new(nodes, &{&1.id, &1})

    connections
    |> Enum.reduce({[], %{}, %{}}, fn connection, {valid, invalid_outputs, invalid_inputs} ->
      source = Map.fetch!(nodes_by_id, connection.source_node_id)
      target = Map.fetch!(nodes_by_id, connection.target_node_id)

      valid_output? =
        NodeConnectionRules.valid_output_pin?(source.type, source.data, connection.source_pin)

      valid_input? = NodeConnectionRules.valid_input_pin?(target.type, connection.target_pin)

      invalid_outputs =
        maybe_add_invalid_pin(invalid_outputs, source.id, connection.source_pin, !valid_output?)

      invalid_inputs =
        maybe_add_invalid_pin(invalid_inputs, target.id, connection.target_pin, !valid_input?)

      if valid_output? and valid_input? do
        {[connection | valid], invalid_outputs, invalid_inputs}
      else
        {valid, invalid_outputs, invalid_inputs}
      end
    end)
    |> then(fn {valid, invalid_outputs, invalid_inputs} ->
      {Enum.reverse(valid), invalid_outputs, invalid_inputs}
    end)
  end

  defp maybe_add_invalid_pin(pins, _node_id, _pin, false), do: pins

  defp maybe_add_invalid_pin(pins, node_id, pin, true) do
    Map.update(pins, node_id, [pin], fn existing ->
      [pin | existing] |> Enum.uniq() |> Enum.sort()
    end)
  end

  # ===========================================================================
  # Reachability (virtual jump→hub edges, cycle-safe BFS from every Entry)
  # ===========================================================================

  defp compute_unreachable_ids(_nodes, _connections, []), do: MapSet.new()

  defp compute_unreachable_ids(nodes, connections, entry_ids) do
    physical_adj =
      Enum.reduce(connections, %{}, fn c, acc ->
        Map.update(acc, c.source_node_id, [c.target_node_id], &[c.target_node_id | &1])
      end)

    adj = add_jump_edges(physical_adj, nodes)
    reachable = bfs(entry_ids, adj, MapSet.new(entry_ids))
    all_ids = MapSet.new(nodes, & &1.id)
    MapSet.difference(all_ids, reachable)
  end

  defp add_jump_edges(adj, nodes) do
    Enum.reduce(resolved_jump_edges(nodes), adj, fn {jump_id, hub_node_id}, acc ->
      Map.update(acc, jump_id, [hub_node_id], &[hub_node_id | &1])
    end)
  end

  @doc """
  `{jump node id, hub node id}` pairs for jumps whose target hub exists.

  Blank hub identifiers never form an edge (a jump with an empty target must
  not resolve to a hub with an empty id — both are their own findings), and
  duplicate hub identifiers resolve to the lowest hub node id so the result
  is independent of load order.
  """
  @spec resolved_jump_edges([node_map()]) :: [{integer(), integer()}]
  def resolved_jump_edges(nodes) do
    hubs_by_identifier =
      nodes
      |> Enum.filter(&(&1.type == "hub" and &1.data["hub_id"] not in [nil, ""]))
      |> Enum.sort_by(& &1.id)
      |> Enum.reduce(%{}, fn hub, acc -> Map.put_new(acc, hub.data["hub_id"], hub.id) end)

    for jump <- nodes,
        jump.type == "jump",
        target = jump.data["target_hub_id"],
        target not in [nil, ""],
        hub_node_id = Map.get(hubs_by_identifier, target),
        not is_nil(hub_node_id),
        do: {jump.id, hub_node_id}
  end

  defp bfs([], _adj, visited), do: visited

  defp bfs(queue, adj, visited) do
    next =
      queue
      |> Enum.flat_map(fn id ->
        adj
        |> Map.get(id, [])
        |> Enum.reject(&MapSet.member?(visited, &1))
      end)
      |> Enum.uniq()

    bfs(next, adj, MapSet.union(visited, MapSet.new(next)))
  end

  # ===========================================================================
  # Dead ends, isolation, orphan hubs, missing pins
  # ===========================================================================

  defp compute_dead_end_ids(nodes, connections) do
    source_ids = MapSet.new(connections, & &1.source_node_id)

    for n <- nodes,
        NodeConnectionRules.needs_outgoing_connection?(n.type),
        not MapSet.member?(source_ids, n.id),
        into: MapSet.new(),
        do: n.id
  end

  defp compute_isolated_ids(nodes, connections) do
    connected_ids =
      Enum.reduce(connections, MapSet.new(), fn c, acc ->
        acc |> MapSet.put(c.source_node_id) |> MapSet.put(c.target_node_id)
      end)

    jump_participant_ids = virtual_edge_participant_ids(nodes)

    for n <- nodes,
        not NodeConnectionRules.connection_optional_type?(n.type),
        not MapSet.member?(connected_ids, n.id),
        not MapSet.member?(jump_participant_ids, n.id),
        into: MapSet.new(),
        do: n.id
  end

  # Jumps with a resolvable target and their target hubs participate in the
  # graph through the virtual edge, so neither end is isolated.
  defp virtual_edge_participant_ids(nodes) do
    nodes
    |> resolved_jump_edges()
    |> Enum.flat_map(fn {jump_id, hub_node_id} -> [jump_id, hub_node_id] end)
    |> MapSet.new()
  end

  defp compute_orphan_hub_ids(nodes, connections) do
    target_ids = MapSet.new(connections, & &1.target_node_id)
    jump_target_hub_node_ids = nodes |> resolved_jump_edges() |> MapSet.new(&elem(&1, 1))

    for n <- nodes,
        n.type == "hub",
        not MapSet.member?(target_ids, n.id),
        not MapSet.member?(jump_target_hub_node_ids, n.id),
        into: MapSet.new(),
        do: n.id
  end

  defp compute_missing_output_pins(nodes, connected_output_pins) do
    Enum.reduce(nodes, %{}, fn node, acc ->
      case node_missing_output_pins(node, connected_output_pins) do
        [] -> acc
        missing -> Map.put(acc, node.id, missing)
      end
    end)
  end

  defp node_missing_output_pins(node, connected_output_pins) do
    if NodeConnectionRules.needs_outgoing_connection?(node.type) do
      connected = Map.get(connected_output_pins, node.id, MapSet.new())

      node.type
      |> NodeConnectionRules.output_pins(node.data)
      |> Enum.reject(&MapSet.member?(connected, &1))
    else
      []
    end
  end

  defp connected_output_pins(connections) do
    Enum.reduce(connections, %{}, fn connection, acc ->
      Map.update(
        acc,
        connection.source_node_id,
        MapSet.new([connection.source_pin]),
        &MapSet.put(&1, connection.source_pin)
      )
    end)
  end
end
