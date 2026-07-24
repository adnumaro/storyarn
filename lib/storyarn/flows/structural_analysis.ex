defmodule Storyarn.Flows.StructuralAnalysis do
  @moduledoc """
  Canonical structural-analysis engine for flows.

  Single detector boundary shared by the flow editor, the dashboards, and the
  structural-analysis panel: every consumer evaluates the same frozen rule
  catalog (`Rules`) over the same graph semantics (`Graph`) and receives the
  same canonical findings (`Finding`), deterministically ordered.

  Reachability is topological, never symbolic condition evaluation:

  - one Entry: traverse from that Entry;
  - no Entry: emit the entry finding, claim nothing about reachability;
  - multiple Entries: emit the entry finding and traverse from all Entries;
  - cycles are valid; traversal is cycle-safe;
  - jump→hub virtual edges participate in reachability and isolation.
  """

  alias Storyarn.Flows.NodeConnectionRules
  alias Storyarn.Flows.StructuralAnalysis.Finding
  alias Storyarn.Flows.StructuralAnalysis.Graph
  alias Storyarn.Flows.StructuralAnalysis.Topology
  alias Storyarn.Shared.CanonicalJSON

  defmodule Analysis do
    @moduledoc false
    defstruct [:project_id, :flow_id, :flow_name, :graph, :graph_digest, findings: []]

    @type t :: %__MODULE__{}
  end

  @doc "Analyzes one already-built topology."
  @spec analyze(Topology.t()) :: Analysis.t()
  def analyze(%Topology{} = topology) do
    graph = Graph.compute(topology.nodes, topology.connections)
    digest = graph_digest(topology)

    findings =
      []
      |> entry_findings(topology, graph, digest)
      |> reachability_findings(topology, graph, digest)
      |> output_findings(topology, graph, digest)
      |> pin_findings(topology, graph)
      |> orphan_hub_findings(topology, graph, digest)
      |> reference_findings(topology)
      |> Finding.sort()

    %Analysis{
      project_id: topology.project_id,
      flow_id: topology.flow_id,
      flow_name: topology.flow_name,
      graph: graph,
      graph_digest: digest,
      findings: findings
    }
  end

  @doc "Loads and analyzes a single flow."
  @spec analyze_flow(pos_integer(), pos_integer()) :: {:ok, Analysis.t()} | {:error, :not_found}
  def analyze_flow(project_id, flow_id) do
    with {:ok, topology} <- Topology.load_flow(project_id, flow_id) do
      {:ok, analyze(topology)}
    end
  end

  @doc """
  Analyzes a flow whose nodes/connections associations are already loaded
  (editor path — no node/connection re-query).
  """
  @spec analyze_loaded(Storyarn.Flows.Flow.t()) :: Analysis.t()
  def analyze_loaded(flow) do
    flow |> Topology.from_loaded() |> analyze()
  end

  @doc "Loads and analyzes every active flow of a project (dashboard path)."
  @spec analyze_project(pos_integer()) :: [Analysis.t()]
  def analyze_project(project_id) do
    project_id
    |> Topology.load_project()
    |> Enum.map(&analyze/1)
  end

  # ===========================================================================
  # Entry rules
  # ===========================================================================

  defp entry_findings(acc, topology, %Graph{entry_ids: []} = _graph, digest) do
    finding =
      Finding.build("missing_entry", topology.flow_id, %{type: :flow, id: topology.flow_id},
        evidence: [flow_evidence(topology)],
        fingerprint_inputs: %{"entry_node_ids" => [], "graph" => digest}
      )

    [finding | acc]
  end

  defp entry_findings(acc, _topology, %Graph{entry_ids: [_single]}, _digest), do: acc

  defp entry_findings(acc, topology, %Graph{entry_ids: entry_ids}, digest) do
    sorted = Enum.sort(entry_ids)

    finding =
      Finding.build("multiple_entries", topology.flow_id, %{type: :flow, id: topology.flow_id},
        details: %{count: length(sorted)},
        evidence: [flow_evidence(topology) | Enum.map(sorted, &node_evidence/1)],
        fingerprint_inputs: %{"entry_node_ids" => sorted, "graph" => digest}
      )

    [finding | acc]
  end

  # ===========================================================================
  # Reachability rules
  # ===========================================================================

  defp reachability_findings(acc, topology, graph, digest) do
    entry_ids = Enum.sort(graph.entry_ids)

    unreachable =
      for node <- graph.nodes,
          NodeConnectionRules.can_be_unreachable?(node.type),
          MapSet.member?(graph.unreachable_ids, node.id),
          not MapSet.member?(graph.isolated_ids, node.id) do
        Finding.build("unreachable_node", topology.flow_id, %{type: :node, id: node.id},
          details: %{node_type: node.type},
          evidence: [node_evidence(node.id)],
          fingerprint_inputs: %{
            "node_id" => node.id,
            "entry_node_ids" => entry_ids,
            "graph" => digest
          }
        )
      end

    isolated =
      for node <- graph.nodes, MapSet.member?(graph.isolated_ids, node.id) do
        Finding.build("isolated_node", topology.flow_id, %{type: :node, id: node.id},
          details: %{node_type: node.type},
          evidence: [node_evidence(node.id)],
          fingerprint_inputs: %{"node_id" => node.id, "graph" => digest}
        )
      end

    unreachable ++ isolated ++ acc
  end

  # ===========================================================================
  # Output rules (reachable non-terminal dead ends, required pins)
  # ===========================================================================

  defp output_findings(acc, topology, graph, digest) do
    dead_ends =
      for node <- graph.nodes,
          MapSet.member?(graph.dead_end_ids, node.id),
          not MapSet.member?(graph.isolated_ids, node.id),
          claimed_reachable?(graph, node.id) do
        Finding.build("no_outgoing_connection", topology.flow_id, %{type: :node, id: node.id},
          details: %{node_type: node.type},
          evidence: [node_evidence(node.id)],
          fingerprint_inputs: %{"node_id" => node.id, "graph" => digest}
        )
      end

    missing_pins =
      for node <- graph.nodes,
          pins = Graph.missing_output_pins_for(graph, node),
          pins != [],
          not MapSet.member?(graph.dead_end_ids, node.id),
          not MapSet.member?(graph.isolated_ids, node.id),
          claimed_reachable?(graph, node.id) do
        Finding.build(
          "missing_output_connections",
          topology.flow_id,
          %{type: :node, id: node.id},
          details: %{node_type: node.type, pins: pins},
          evidence: [node_evidence(node.id)],
          fingerprint_inputs: %{"node_id" => node.id, "pins" => pins, "graph" => digest}
        )
      end

    dead_ends ++ missing_pins ++ acc
  end

  # Without any Entry, reachability is unknown: the entry finding is emitted
  # and output rules do not suppress themselves behind an unprovable claim.
  defp claimed_reachable?(%Graph{entry_ids: []}, _node_id), do: true
  defp claimed_reachable?(graph, node_id), do: not MapSet.member?(graph.unreachable_ids, node_id)

  # ===========================================================================
  # Pin validity rules
  # ===========================================================================

  defp pin_findings(acc, topology, graph) do
    invalid_by_source = Enum.group_by(graph.invalid_connections, & &1.source_node_id)
    invalid_by_target = Enum.group_by(graph.invalid_connections, & &1.target_node_id)
    nodes_by_id = Map.new(graph.nodes, &{&1.id, &1})

    outputs =
      for {node_id, pins} <- graph.invalid_output_pins do
        node = Map.fetch!(nodes_by_id, node_id)

        connections =
          invalid_by_source
          |> Map.get(node_id, [])
          |> Enum.filter(&(&1.source_pin in pins))
          |> Enum.sort_by(& &1.id)

        Finding.build("invalid_output_pins", topology.flow_id, %{type: :node, id: node_id},
          details: %{node_type: node.type, pins: pins},
          evidence: [node_evidence(node_id) | Enum.map(connections, &connection_evidence/1)],
          fingerprint_inputs: %{
            "node_id" => node_id,
            "pins" => pins,
            "connections" => Enum.map(connections, &[&1.id, &1.source_pin]),
            "accepted_pins" => node.type |> NodeConnectionRules.accepted_output_pins(node.data) |> Enum.sort()
          }
        )
      end

    inputs =
      for {node_id, pins} <- graph.invalid_input_pins do
        node = Map.fetch!(nodes_by_id, node_id)

        connections =
          invalid_by_target
          |> Map.get(node_id, [])
          |> Enum.filter(&(&1.target_pin in pins))
          |> Enum.sort_by(& &1.id)

        Finding.build("invalid_input_pins", topology.flow_id, %{type: :node, id: node_id},
          details: %{node_type: node.type, pins: pins},
          evidence: [node_evidence(node_id) | Enum.map(connections, &connection_evidence/1)],
          fingerprint_inputs: %{
            "node_id" => node_id,
            "pins" => pins,
            "connections" => Enum.map(connections, &[&1.id, &1.target_pin])
          }
        )
      end

    outputs ++ inputs ++ acc
  end

  # ===========================================================================
  # Orphan hubs
  # ===========================================================================

  defp orphan_hub_findings(acc, topology, graph, digest) do
    findings =
      for node <- graph.nodes, MapSet.member?(graph.orphan_hub_ids, node.id) do
        Finding.build("orphan_hub", topology.flow_id, %{type: :node, id: node.id},
          details: %{hub_id: node.data["hub_id"]},
          evidence: [node_evidence(node.id)],
          fingerprint_inputs: %{
            "node_id" => node.id,
            "hub_id" => node.data["hub_id"],
            "graph" => digest
          }
        )
      end

    findings ++ acc
  end

  # ===========================================================================
  # Reference integrity rules
  # ===========================================================================

  defp reference_findings(acc, topology) do
    hub_ids =
      topology.nodes
      |> Enum.filter(&(&1.type == "hub"))
      |> Enum.map(& &1.data["hub_id"])
      |> Enum.sort()

    Enum.reduce(topology.nodes, acc, fn node, acc ->
      node
      |> node_reference_findings(topology, hub_ids)
      |> Kernel.++(acc)
    end)
  end

  defp node_reference_findings(%{type: "jump"} = node, topology, hub_ids) do
    target = node.data["target_hub_id"]

    cond do
      blank?(target) ->
        [reference_finding("missing_jump_target", topology, node, %{})]

      target not in hub_ids ->
        [
          reference_finding("stale_jump_target", topology, node, %{
            "target_hub_id" => target,
            "flow_hub_ids" => hub_ids
          })
        ]

      true ->
        []
    end
  end

  defp node_reference_findings(%{type: "subflow"} = node, topology, _hub_ids) do
    reference_state_findings(
      node,
      topology,
      "missing_subflow_reference",
      "stale_subflow_reference"
    )
  end

  defp node_reference_findings(%{type: "exit", data: %{"exit_mode" => "flow_reference"}} = node, topology, _hub_ids) do
    reference_state_findings(
      node,
      topology,
      "missing_exit_flow_reference",
      "stale_exit_flow_reference"
    )
  end

  defp node_reference_findings(_node, _topology, _hub_ids), do: []

  defp reference_state_findings(node, topology, missing_rule, stale_rule) do
    ref_id = node.data["referenced_flow_id"]

    cond do
      blank?(ref_id) ->
        [reference_finding(missing_rule, topology, node, %{})]

      node.data["stale_reference"] == true ->
        [
          reference_finding(stale_rule, topology, node, %{
            "referenced_flow_id" => to_string(ref_id)
          })
        ]

      true ->
        []
    end
  end

  defp reference_finding(rule_id, topology, node, extra_inputs) do
    Finding.build(rule_id, topology.flow_id, %{type: :node, id: node.id},
      details: %{node_type: node.type},
      evidence: [node_evidence(node.id)],
      fingerprint_inputs: Map.merge(%{"node_id" => node.id}, extra_inputs)
    )
  end

  # ===========================================================================
  # Shared helpers
  # ===========================================================================

  # Canonical digest of the topology relevant to negative graph claims:
  # active nodes with their types and the stored connection tuples.
  # Everything that shapes graph semantics belongs in the digest: stored
  # edges, resolved jump→hub virtual edges, and each node's canonical output
  # pin set (pin validity and required-pin claims derive from it). Rewiring a
  # jump or removing a dialogue response must rotate reachability fingerprints.
  defp graph_digest(%Topology{} = topology) do
    CanonicalJSON.hash!(%{
      "nodes" => topology.nodes |> Enum.map(&[&1.id, &1.type]) |> Enum.sort(),
      "edges" =>
        topology.connections
        |> Enum.map(&[&1.source_node_id, &1.source_pin, &1.target_node_id, &1.target_pin])
        |> Enum.sort(),
      "virtual_edges" =>
        topology.nodes
        |> Graph.resolved_jump_edges()
        |> Enum.map(fn {jump_id, hub_node_id} -> [jump_id, hub_node_id] end)
        |> Enum.sort(),
      "output_pins" =>
        topology.nodes
        |> Enum.map(&[&1.id, NodeConnectionRules.output_pins(&1.type, &1.data)])
        |> Enum.sort()
    })
  end

  defp flow_evidence(topology), do: %{type: "flow", id: topology.flow_id}
  defp node_evidence(node_id), do: %{type: "flow_node", id: node_id}
  defp connection_evidence(connection), do: %{type: "flow_connection", id: connection.id}

  defp blank?(value), do: value in [nil, ""]
end
