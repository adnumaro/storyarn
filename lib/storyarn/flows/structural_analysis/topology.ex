defmodule Storyarn.Flows.StructuralAnalysis.Topology do
  @moduledoc """
  Lean structural snapshot of one flow: active nodes (with cross-flow
  reference data resolved), and connections between active nodes.

  Node data is resolved through the same `NodeCrud` resolution the editor
  serializer uses (`resolve_subflow_data`/`resolve_exit_data`), so subflow
  exit pins and `stale_reference` flags — the inputs of pin validation and
  reference-integrity rules — cannot drift between the editor and this path.

  Unlike `Flows.serialize_for_canvas/2` it loads none of the editorial
  material (project variables, resolved colors, referencing flows, sequence
  configs), so it is cheap enough to build for every flow of a project at
  dashboard time.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeCrud
  alias Storyarn.Repo

  defstruct [:project_id, :flow_id, :flow_name, nodes: [], connections: []]

  @type t :: %__MODULE__{}

  @doc """
  Builds the topology from a flow whose `nodes` (active only) and
  `connections` associations are already loaded. One batched query resolves
  subflow references; exit flow references resolve per node (rare).
  """
  @spec from_loaded(Flow.t()) :: t()
  def from_loaded(%Flow{} = flow) do
    nodes = Enum.map(flow.nodes, &%{id: &1.id, type: &1.type, data: &1.data || %{}})

    build(
      flow.project_id,
      flow.id,
      flow.name,
      resolve_nodes(nodes, flow.project_id),
      Enum.map(flow.connections, &normalize_connection/1)
    )
  end

  @doc """
  Builds the topology from `Flows.serialize_for_canvas/2` output — node data
  is ALREADY resolved there (same `NodeCrud` resolution), so this path issues
  zero queries. Guarded by the from_serialized==DB parity test.
  """
  @spec from_serialized(map(), pos_integer()) :: t()
  def from_serialized(%{id: flow_id, name: flow_name, nodes: nodes, connections: connections}, project_id) do
    build(
      project_id,
      flow_id,
      flow_name,
      Enum.map(nodes, &%{id: &1.id, type: &1.type, data: &1.data || %{}}),
      Enum.map(connections, &normalize_connection/1)
    )
  end

  @doc "Loads the topology for a single flow (panel rerun path)."
  @spec load_flow(pos_integer(), pos_integer()) :: {:ok, t()} | {:error, :not_found}
  def load_flow(project_id, flow_id) do
    case load_project(project_id, flow_id: flow_id) do
      [topology] -> {:ok, topology}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Loads topologies for every active flow of a project in three batched
  queries (flows, nodes, connections) plus one batched subflow-reference
  resolution — the dashboard path.
  """
  @spec load_project(pos_integer(), keyword()) :: [t()]
  def load_project(project_id, opts \\ []) do
    flows_query =
      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        select: {f.id, f.name}
      )

    flows_query =
      case opts[:flow_id] do
        nil -> flows_query
        flow_id -> where(flows_query, [f], f.id == ^flow_id)
      end

    flows = Repo.all(flows_query)
    flow_ids = Enum.map(flows, &elem(&1, 0))

    nodes_by_flow =
      from(n in FlowNode,
        where: n.flow_id in ^flow_ids and is_nil(n.deleted_at),
        select: %{id: n.id, flow_id: n.flow_id, type: n.type, data: n.data}
      )
      |> Repo.all()
      |> Enum.map(&%{&1 | data: &1.data || %{}})
      |> Enum.group_by(& &1.flow_id)

    connections_by_flow =
      from(c in FlowConnection,
        where: c.flow_id in ^flow_ids,
        select: %{
          id: c.id,
          flow_id: c.flow_id,
          source_node_id: c.source_node_id,
          source_pin: c.source_pin,
          target_node_id: c.target_node_id,
          target_pin: c.target_pin
        }
      )
      |> Repo.all()
      |> Enum.group_by(& &1.flow_id)

    all_nodes = nodes_by_flow |> Map.values() |> List.flatten()
    subflow_cache = NodeCrud.batch_resolve_subflow_data(all_nodes, project_id)
    exit_cache = NodeCrud.batch_resolve_exit_data(all_nodes, project_id)

    for {flow_id, flow_name} <- flows do
      nodes =
        nodes_by_flow
        |> Map.get(flow_id, [])
        |> Enum.map(&%{id: &1.id, type: &1.type, data: &1.data})
        |> resolve_nodes(project_id, subflow_cache, exit_cache)

      connections = Map.get(connections_by_flow, flow_id, [])
      build(project_id, flow_id, flow_name, nodes, connections)
    end
  end

  defp resolve_nodes(nodes, project_id) do
    resolve_nodes(
      nodes,
      project_id,
      NodeCrud.batch_resolve_subflow_data(nodes, project_id),
      NodeCrud.batch_resolve_exit_data(nodes, project_id)
    )
  end

  defp resolve_nodes(nodes, project_id, subflow_cache, exit_cache) do
    Enum.map(nodes, fn
      %{type: "subflow"} = node ->
        %{node | data: NodeCrud.resolve_subflow_data(node.data, subflow_cache)}

      %{type: "exit"} = node ->
        %{node | data: NodeCrud.resolve_exit_data(node.data, project_id, exit_cache)}

      node ->
        node
    end)
  end

  defp build(project_id, flow_id, flow_name, nodes, connections) do
    node_ids = MapSet.new(nodes, & &1.id)

    active_connections =
      Enum.filter(connections, fn conn ->
        MapSet.member?(node_ids, conn.source_node_id) and
          MapSet.member?(node_ids, conn.target_node_id)
      end)

    %__MODULE__{
      project_id: project_id,
      flow_id: flow_id,
      flow_name: flow_name,
      nodes: nodes,
      connections: active_connections
    }
  end

  defp normalize_connection(connection) do
    %{
      id: connection.id,
      source_node_id: connection.source_node_id,
      source_pin: connection.source_pin,
      target_node_id: connection.target_node_id,
      target_pin: connection.target_pin
    }
  end
end
