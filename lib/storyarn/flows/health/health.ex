defmodule Storyarn.Flows.Health do
  @moduledoc """
  Public capability boundary for Flow health rules and project projections.

  Editor, dashboard and export surfaces enter through the same structural and
  editorial analysis so their findings cannot drift independently.
  """

  alias Storyarn.Flows.FlowStats
  alias Storyarn.Flows.HealthChecker
  alias Storyarn.Flows.HealthFlags
  alias Storyarn.Flows.Severity
  alias Storyarn.Flows.StructuralAnalysis
  alias Storyarn.Flows.StructuralAnalysis.Graph
  alias Storyarn.Flows.StructuralAnalysis.Topology

  defdelegate health_severity_rank(severity), to: Severity, as: :rank
  defdelegate add_health_flags(nodes, stale_node_ids, variable_types), to: HealthFlags, as: :add

  defdelegate add_stale_health_flag(data, node_id, stale_node_ids),
    to: HealthFlags,
    as: :add_stale

  defdelegate add_type_warning_health_flag(data, type, variable_types),
    to: HealthFlags,
    as: :add_type_warning

  defdelegate flow_stats_for_project(project_id), to: FlowStats
  defdelegate flow_word_counts(project_id), to: FlowStats
  defdelegate flow_word_count(flow), to: FlowStats
  defdelegate count_project_nodes_by_type(project_id), to: FlowStats
  defdelegate count_dialogue_lines_by_speaker(project_id, limit \\ 10), to: FlowStats
  defdelegate list_dashboard_health_findings(project_id), to: FlowStats

  defdelegate list_export_health_findings(project_id, flows, context \\ %{}),
    to: FlowStats

  defdelegate analyze_flow_structure(project_id, flow_id),
    to: StructuralAnalysis,
    as: :analyze_flow

  defdelegate analyze_loaded_flow_structure(flow),
    to: StructuralAnalysis,
    as: :analyze_loaded

  defdelegate analyze_serialized_flow_structure(flow_data, project_id),
    to: StructuralAnalysis,
    as: :analyze_serialized

  def flow_health_findings(flow_data, project_id) do
    flow_data
    |> Topology.from_serialized(project_id)
    |> StructuralAnalysis.findings()
  end

  defdelegate compute_structural_graph(nodes, connections), to: Graph, as: :compute
  defdelegate structural_missing_output_pins_for(graph, node), to: Graph, as: :missing_output_pins_for
  defdelegate health_codes(), to: HealthChecker, as: :codes
  defdelegate health_finding(code, attrs \\ %{}), to: HealthChecker, as: :finding
  defdelegate check_health(snapshot), to: HealthChecker, as: :check
end
