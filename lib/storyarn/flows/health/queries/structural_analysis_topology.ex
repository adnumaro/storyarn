defmodule Storyarn.Flows.StructuralAnalysis.Topology do
  @moduledoc """
  Lean structural snapshot of one flow: active nodes (with cross-flow
  reference data resolved), and connections between active nodes.

  Node data is resolved through the same `NodeCrud` resolution the editor
  serializer uses (`resolve_subflow_data`/`resolve_exit_data`), so subflow
  exit pins and `stale_reference` flags — the inputs of pin validation and
  reference-integrity rules — cannot drift between the editor and this path.
  Sequence nodes carry no data at all here, because they carry none the editor
  can see either — same reason.

  Unlike `Flows.serialize_for_canvas/2` it loads none of the editorial
  material (project variables, resolved colors, referencing flows, sequence
  configs), so it is cheap enough to build for every flow of a project at
  dashboard time.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Editor
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
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
  Builds topologies for already-loaded flows while resolving cross-flow node
  data once for the whole batch.

  Export validation already owns the selected flows with their nodes and
  connections preloaded. Reusing them here avoids loading every topology in the
  project and preserves the dashboard's batched reference resolution.
  """
  @spec from_loaded_many([Flow.t()]) :: [t()]
  def from_loaded_many([]), do: []

  def from_loaded_many(flows) when is_list(flows) do
    flows
    |> Enum.group_by(& &1.project_id)
    |> Enum.flat_map(fn {project_id, project_flows} ->
      nodes_by_flow =
        Map.new(project_flows, fn flow ->
          nodes =
            Enum.map(
              flow.nodes,
              &%{
                id: &1.id,
                type: &1.type,
                data: &1.data || %{}
              }
            )

          {flow.id, nodes}
        end)

      all_nodes = nodes_by_flow |> Map.values() |> List.flatten()
      subflow_cache = Editor.batch_resolve_subflow_data(all_nodes, project_id)
      exit_cache = Editor.batch_resolve_exit_data(all_nodes, project_id)

      Enum.map(project_flows, fn flow ->
        nodes =
          nodes_by_flow
          |> Map.fetch!(flow.id)
          |> resolve_nodes(project_id, subflow_cache, exit_cache)

        build(
          project_id,
          flow.id,
          flow.name,
          nodes,
          Enum.map(flow.connections, &normalize_connection/1)
        )
      end)
    end)
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

  @doc """
  Loads the topology for a single flow — `load_project/2` narrowed to one id, so
  it is the same builder the dashboard sweep uses. That is what makes it the DB
  side of the `from_serialized == DB` parity test.
  """
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
    # Deterministic flow order: project-level analysis results (dashboards)
    # must not reorder between runs on `Repo.all`'s unspecified order.
    flows_query =
      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        order_by: [asc: f.name, asc: f.id],
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
        # Same reason as the flows query above, and it was missing here: with no
        # `order_by` Postgres returns whatever the plan happens to produce — a
        # forced seqscan after an UPDATE reorders these rows, verified. The
        # composed sort in `StructuralAnalysis.findings/1` is what the surfaces
        # actually depend on; this keeps the INPUT stable too, so `Analysis.graph`
        # and anything that reads `topology.nodes` positionally cannot drift.
        order_by: [asc: n.flow_id, asc: n.id],
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
    subflow_cache = Editor.batch_resolve_subflow_data(all_nodes, project_id)
    exit_cache = Editor.batch_resolve_exit_data(all_nodes, project_id)

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
      Editor.batch_resolve_subflow_data(nodes, project_id),
      Editor.batch_resolve_exit_data(nodes, project_id)
    )
  end

  defp resolve_nodes(nodes, project_id, subflow_cache, exit_cache) do
    Enum.map(nodes, fn
      %{type: "subflow"} = node ->
        %{node | data: Editor.resolve_subflow_data(node.data, subflow_cache)}

      %{type: "exit"} = node ->
        %{node | data: Editor.resolve_exit_data(node.data, project_id, exit_cache)}

      # A sequence node is a visual container. `Flows.serialize_for_canvas/2`
      # discards its row `data` and rebuilds it from `sequence_config`
      # (`name`/`width`/`height`), so on the editor's side a sequence node
      # carries no editorial surface at all — and no health rule reads any of
      # those three. Passing the row through here is what let the dashboard emit
      # findings off a flag the editor cannot even see.
      %{type: "sequence"} = node ->
        %{node | data: %{}}

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
