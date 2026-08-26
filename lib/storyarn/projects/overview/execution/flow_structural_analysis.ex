defmodule Storyarn.Projects.FlowStructuralAnalysis do
  @moduledoc """
  Canonical structural-analysis engine for flows.

  The graph-derived half of flow health. Editorial checks that only need one
  node live in `Storyarn.Projects.FlowHealthChecker`; the checks here need the whole
  graph, and both emit through `FlowHealthChecker.finding/2` so the editor and the
  dashboard share one vocabulary.

  Order is part of that contract: `findings/1` returns the COMPOSED list sorted
  by severity, then location, then code — errors first, on every surface, from
  one place. Composing two already-sorted halves does not produce a sorted
  whole, which is exactly how every `:info` used to arrive ahead of every
  `:error`.

  Reachability is topological, never symbolic condition evaluation:

  - one Entry: traverse from that Entry;
  - no Entry: emit the entry finding, claim nothing about reachability;
  - multiple Entries: emit the entry finding and traverse from all Entries;
  - cycles are valid; traversal is cycle-safe;
  - jump→hub virtual edges participate in reachability and isolation.
  """

  alias Storyarn.Platform.Shared.StringUtils
  alias Storyarn.Projects.FlowHealthChecker
  alias Storyarn.Projects.FlowNodeConnectionRules
  alias Storyarn.Projects.FlowStructuralAnalysis.Graph
  alias Storyarn.Projects.FlowStructuralAnalysis.Topology

  defmodule Analysis do
    @moduledoc false
    defstruct [:project_id, :flow_id, :flow_name, :graph, findings: []]

    @type t :: %__MODULE__{}
  end

  @doc "Analyzes one already-built topology."
  @spec analyze(Topology.t()) :: Analysis.t()
  def analyze(%Topology{} = topology) do
    graph = Graph.compute(topology.nodes, topology.connections)

    # Sorted here too: `Analysis.findings` is a published shape of its own
    # (`FlowStructuralAnalysis.analyze_flow/2`), so it cannot depend on a caller
    # composing it. `findings/1` re-sorts because sorted ++ sorted is not sorted.
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
  (`FlowReadModel` does it for nodes read straight from the DB).
  """
  @spec findings(Topology.t()) :: [map()]
  def findings(%Topology{} = topology) do
    editorial = FlowHealthChecker.check(%{flow_id: topology.flow_id, nodes: topology.nodes})

    # Both halves arrive sorted, and that is not enough: concatenating them puts
    # every editorial `:info` ahead of every structural `:error`. The composed
    # list is what both surfaces render, so the composed list is what gets sorted.
    sort_findings(editorial ++ analyze(topology).findings)
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
  @spec analyze_loaded(Storyarn.Projects.Persistence.FlowRecord.t()) :: Analysis.t()
  def analyze_loaded(flow) do
    flow |> Topology.from_loaded() |> analyze()
  end

  @doc """
  Analyzes serialized Flow output — zero extra queries, node
  data is already resolved. Identical results to the DB path (parity test).
  """
  @spec analyze_serialized(map(), pos_integer()) :: Analysis.t()
  def analyze_serialized(flow_data, project_id) do
    flow_data |> Topology.from_serialized(project_id) |> analyze()
  end

  # Every rule here emits through the ONE flow-health vocabulary. There is no
  # occurrence identity and no evidence fingerprint any more: both existed to
  # anchor a dismissal or an AI explanation to an exact occurrence, and both are
  # gone. Sheets and Scenes never had them either.
  defp flow_finding(code, topology, details) do
    FlowHealthChecker.finding(code, %{
      flow_id: topology.flow_id,
      entity_type: "flow",
      entity_id: nil,
      details: details
    })
  end

  # Takes the node, not its id: every emitting rule already holds it, so the
  # `entity_type` is a field read rather than a scan of every node per finding.
  defp node_finding(code, topology, node, details) do
    FlowHealthChecker.finding(code, %{
      flow_id: topology.flow_id,
      entity_type: node.type,
      entity_id: node.id,
      details: details
    })
  end

  # Deterministic order for a stable UI: severity, then location, then code.
  defp sort_findings(findings) do
    Enum.sort_by(findings, fn finding ->
      {severity_rank(finding.severity), finding.entity_id || 0, to_string(finding.code)}
    end)
  end

  # This projection happens to expose the same labels as other tools, but the
  # ordering is part of the Project-owned Flow read model rather than a shared
  # domain contract.
  defp severity_rank(:error), do: 0
  defp severity_rank(:warning), do: 1
  defp severity_rank(:info), do: 2

  # ===========================================================================
  # Entry rules
  # ===========================================================================

  defp entry_findings(acc, topology, %Graph{entry_ids: []} = _graph) do
    [flow_finding(:missing_entry, topology, %{}) | acc]
  end

  defp entry_findings(acc, _topology, %Graph{entry_ids: [_single]}), do: acc

  defp entry_findings(acc, topology, %Graph{entry_ids: entry_ids}) do
    [flow_finding(:multiple_entries, topology, %{count: length(entry_ids)}) | acc]
  end

  # ===========================================================================
  # Reachability rules
  # ===========================================================================

  defp reachability_findings(acc, topology, graph) do
    unreachable =
      for node <- graph.nodes,
          FlowNodeConnectionRules.can_be_unreachable?(node.type),
          MapSet.member?(graph.unreachable_ids, node.id),
          not MapSet.member?(graph.isolated_ids, node.id) do
        node_finding(:unreachable_node, topology, node, %{node_type: node.type})
      end

    isolated =
      for node <- graph.nodes, MapSet.member?(graph.isolated_ids, node.id) do
        node_finding(:isolated_node, topology, node, %{node_type: node.type})
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
        node_finding(:no_outgoing_connection, topology, node, %{node_type: node.type})
      end

    missing_pins =
      for node <- graph.nodes,
          pins = Graph.missing_output_pins_for(graph, node),
          pins != [],
          not MapSet.member?(graph.dead_end_ids, node.id),
          not MapSet.member?(graph.isolated_ids, node.id),
          claimed_reachable?(graph, node.id) do
        node_finding(:missing_output_connections, topology, node, %{node_type: node.type, pins: pins})
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

        node_finding(:invalid_output_pins, topology, node, %{node_type: node.type, pins: pins})
      end

    inputs =
      for {node_id, pins} <- graph.invalid_input_pins do
        node = Map.fetch!(nodes_by_id, node_id)

        node_finding(:invalid_input_pins, topology, node, %{node_type: node.type, pins: pins})
      end

    outputs ++ inputs ++ acc
  end

  # ===========================================================================
  # Orphan hubs
  # ===========================================================================

  defp orphan_hub_findings(acc, topology, graph) do
    findings =
      for node <- graph.nodes, MapSet.member?(graph.orphan_hub_ids, node.id) do
        node_finding(:orphan_hub, topology, node, %{node_type: "hub", hub_id: node.data["hub_id"]})
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
      StringUtils.blank?(target) -> [reference_finding(:missing_jump_target, topology, node)]
      target not in hub_ids -> [reference_finding(:stale_jump_target, topology, node)]
      true -> []
    end
  end

  defp node_reference_findings(%{type: "subflow"} = node, topology, _hub_ids) do
    reference_state_findings(
      node,
      topology,
      :missing_subflow_reference,
      :stale_subflow_reference
    )
  end

  defp node_reference_findings(%{type: "exit", data: %{"exit_mode" => "flow_reference"}} = node, topology, _hub_ids) do
    reference_state_findings(
      node,
      topology,
      :missing_exit_flow_reference,
      :stale_exit_flow_reference
    )
  end

  defp node_reference_findings(_node, _topology, _hub_ids), do: []

  defp reference_state_findings(node, topology, missing_rule, stale_rule) do
    cond do
      StringUtils.blank?(node.data["referenced_flow_id"]) -> [reference_finding(missing_rule, topology, node)]
      node.data["stale_reference"] == true -> [reference_finding(stale_rule, topology, node)]
      true -> []
    end
  end

  # These rules pick their code at runtime, which is the whole reason they used
  # to travel as strings. Atoms end to end means the catalog lookup in
  # `FlowHealthChecker.finding/2` is the only thing that can reject an unknown one.
  defp reference_finding(code, topology, node) do
    node_finding(code, topology, node, %{node_type: node.type})
  end
end
