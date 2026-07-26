defmodule Storyarn.Flows.StructuralAnalysis do
  @moduledoc """
  Canonical structural-analysis engine for flows.

  The graph-derived half of flow health. Editorial checks that only need one
  node live in `Storyarn.Flows.HealthChecker`; the checks here need the whole
  graph, and both emit through `HealthChecker.finding/2` so the editor and the
  dashboard share one vocabulary, deterministically ordered.

  Reachability is topological, never symbolic condition evaluation:

  - one Entry: traverse from that Entry;
  - no Entry: emit the entry finding, claim nothing about reachability;
  - multiple Entries: emit the entry finding and traverse from all Entries;
  - cycles are valid; traversal is cycle-safe;
  - jump→hub virtual edges participate in reachability and isolation.
  """

  alias Storyarn.Flows.HealthChecker
  alias Storyarn.Flows.NodeConnectionRules
  alias Storyarn.Flows.StructuralAnalysis.Graph
  alias Storyarn.Flows.StructuralAnalysis.Topology

  defmodule Analysis do
    @moduledoc false
    defstruct [:project_id, :flow_id, :flow_name, :graph, findings: []]

    @type t :: %__MODULE__{}
  end

  @doc "Analyzes one already-built topology."
  @spec analyze(Topology.t()) :: Analysis.t()
  def analyze(%Topology{} = topology) do
    graph = Graph.compute(topology.nodes, topology.connections)

    findings =
      []
      |> entry_findings(topology, graph)
      |> reachability_findings(topology, graph)
      |> output_findings(topology, graph)
      |> pin_findings(topology, graph)
      |> orphan_hub_findings(topology, graph)
      |> reference_findings(topology)
      |> sort_findings()

    %Analysis{
      project_id: topology.project_id,
      flow_id: topology.flow_id,
      flow_name: topology.flow_name,
      graph: graph,
      findings: findings
    }
  end

  @doc """
  Every health finding of one flow: editorial plus graph-derived, in one list.

  **The single composition point.** The editor and the dashboard both call this,
  so the only way they can disagree is by feeding it different nodes — which is
  what the agreement test pins. Adding a detector here reaches both surfaces at
  once; that is the whole point of the consolidation.

  Editorial checks read a node's own `data`, so the caller must supply nodes
  already carrying the health flags the canvas serializer injects
  (`Flows.add_health_flags/3` does it for nodes read straight from the DB).
  """
  @spec findings(Topology.t()) :: [map()]
  def findings(%Topology{} = topology) do
    # `check/1` sees only the nodes, so it cannot know the flow. Stamping it here
    # is what lets a project-wide sweep attribute an editorial finding to its
    # flow — without it they all collapse under a nil key.
    editorial =
      %{nodes: topology.nodes}
      |> HealthChecker.check()
      |> Enum.map(&%{&1 | flow_id: topology.flow_id})

    editorial ++ analyze(topology).findings
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

  @doc """
  Analyzes `Flows.serialize_for_canvas/2` output — zero extra queries, node
  data is already resolved. Identical results to the DB path (parity test).
  """
  @spec analyze_serialized(map(), pos_integer()) :: Analysis.t()
  def analyze_serialized(flow_data, project_id) do
    flow_data |> Topology.from_serialized(project_id) |> analyze()
  end

  @doc "Loads and analyzes every active flow of a project (dashboard path)."
  @spec analyze_project(pos_integer()) :: [Analysis.t()]
  def analyze_project(project_id) do
    project_id
    |> Topology.load_project()
    |> Enum.map(&analyze/1)
  end

  # Every rule here emits through the ONE flow-health vocabulary. There is no
  # occurrence identity and no evidence fingerprint any more: both existed to
  # anchor a dismissal or an AI explanation to an exact occurrence, and both are
  # gone. Sheets and Scenes never had them either.
  defp finding(code, topology, :flow, _id, details) do
    HealthChecker.finding(atom_code(code), %{
      flow_id: topology.flow_id,
      entity_type: "flow",
      entity_id: nil,
      details: details
    })
  end

  defp finding(code, topology, :node, node_id, details) do
    HealthChecker.finding(atom_code(code), %{
      flow_id: topology.flow_id,
      entity_type: node_type(topology, node_id),
      entity_id: node_id,
      details: details
    })
  end

  # The reference rules derive their code at runtime; an unknown one must raise
  # rather than invent a severity.
  defp atom_code(code) when is_atom(code), do: code
  defp atom_code(code) when is_binary(code), do: String.to_existing_atom(code)

  defp node_type(topology, node_id) do
    Enum.find_value(topology.nodes, "node", fn node -> if node.id == node_id, do: node.type end)
  end

  # Deterministic order for a stable UI: severity, then location, then code.
  defp sort_findings(findings) do
    Enum.sort_by(findings, fn finding ->
      {severity_rank(finding.severity), finding.entity_id || 0, to_string(finding.code)}
    end)
  end

  defp severity_rank(:error), do: 0
  defp severity_rank(:warning), do: 1
  defp severity_rank(:info), do: 2

  # ===========================================================================
  # Entry rules
  # ===========================================================================

  defp entry_findings(acc, topology, %Graph{entry_ids: []} = _graph) do
    finding =
      finding(:missing_entry, topology, :flow, topology.flow_id, %{})

    [finding | acc]
  end

  defp entry_findings(acc, _topology, %Graph{entry_ids: [_single]}), do: acc

  defp entry_findings(acc, topology, %Graph{entry_ids: entry_ids}) do
    sorted = Enum.sort(entry_ids)

    finding =
      finding(:multiple_entries, topology, :flow, topology.flow_id, %{count: length(sorted)})

    [finding | acc]
  end

  # ===========================================================================
  # Reachability rules
  # ===========================================================================

  defp reachability_findings(acc, topology, graph) do
    unreachable =
      for node <- graph.nodes,
          NodeConnectionRules.can_be_unreachable?(node.type),
          MapSet.member?(graph.unreachable_ids, node.id),
          not MapSet.member?(graph.isolated_ids, node.id) do
        finding(:unreachable_node, topology, :node, node.id, %{node_type: node.type})
      end

    isolated =
      for node <- graph.nodes, MapSet.member?(graph.isolated_ids, node.id) do
        finding(:isolated_node, topology, :node, node.id, %{node_type: node.type})
      end

    unreachable ++ isolated ++ acc
  end

  # ===========================================================================
  # Output rules (reachable non-terminal dead ends, required pins)
  # ===========================================================================

  defp output_findings(acc, topology, graph) do
    dead_ends =
      for node <- graph.nodes,
          MapSet.member?(graph.dead_end_ids, node.id),
          not MapSet.member?(graph.isolated_ids, node.id),
          claimed_reachable?(graph, node.id) do
        finding(:no_outgoing_connection, topology, :node, node.id, %{node_type: node.type})
      end

    missing_pins =
      for node <- graph.nodes,
          pins = Graph.missing_output_pins_for(graph, node),
          pins != [],
          not MapSet.member?(graph.dead_end_ids, node.id),
          not MapSet.member?(graph.isolated_ids, node.id),
          claimed_reachable?(graph, node.id) do
        finding(:missing_output_connections, topology, :node, node.id, %{node_type: node.type, pins: pins})
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
    nodes_by_id = Map.new(graph.nodes, &{&1.id, &1})

    outputs =
      for {node_id, pins} <- graph.invalid_output_pins do
        node = Map.fetch!(nodes_by_id, node_id)

        finding(:invalid_output_pins, topology, :node, node_id, %{node_type: node.type, pins: pins})
      end

    inputs =
      for {node_id, pins} <- graph.invalid_input_pins do
        node = Map.fetch!(nodes_by_id, node_id)

        finding(:invalid_input_pins, topology, :node, node_id, %{node_type: node.type, pins: pins})
      end

    outputs ++ inputs ++ acc
  end

  # ===========================================================================
  # Orphan hubs
  # ===========================================================================

  defp orphan_hub_findings(acc, topology, graph) do
    findings =
      for node <- graph.nodes, MapSet.member?(graph.orphan_hub_ids, node.id) do
        finding(:orphan_hub, topology, :node, node.id, %{node_type: "hub", hub_id: node.data["hub_id"]})
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

  defp reference_finding(rule_id, topology, node, _extra_inputs) do
    finding(rule_id, topology, :node, node.id, %{node_type: node.type})
  end

  # ===========================================================================
  # Shared helpers
  # ===========================================================================

  defp blank?(value), do: value in [nil, ""]
end
