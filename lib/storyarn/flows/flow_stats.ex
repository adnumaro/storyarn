defmodule Storyarn.Flows.FlowStats do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.ContentContract
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.HealthFlags
  alias Storyarn.Flows.Instruction
  alias Storyarn.Flows.NodeLabel
  alias Storyarn.Flows.Persistence.SheetRecord
  alias Storyarn.Flows.SpeakerSheetId
  alias Storyarn.Flows.StructuralAnalysis
  alias Storyarn.Flows.StructuralAnalysis.Topology
  alias Storyarn.Flows.VariableCatalog
  alias Storyarn.Flows.VariableReferenceTracker
  alias Storyarn.Repo

  require SpeakerSheetId

  # ===========================================================================
  # Stats
  # ===========================================================================

  @doc """
  Returns per-flow node stats for a project in a single query.
  Returns `%{flow_id => %{node_count, dialogue_count, condition_count}}`.
  Flows with 0 nodes are absent from the returned map.
  """
  def flow_stats_for_project(project_id) do
    from(n in FlowNode,
      join: f in Flow,
      on: n.flow_id == f.id,
      where: f.project_id == ^project_id and is_nil(n.deleted_at) and is_nil(f.deleted_at),
      group_by: [n.flow_id, n.type],
      select: {n.flow_id, n.type, count(n.id)}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {flow_id, rows} ->
      type_counts = Map.new(rows, fn {_, type, count} -> {type, count} end)

      {flow_id,
       %{
         node_count: rows |> Enum.map(&elem(&1, 2)) |> Enum.sum(),
         dialogue_count: Map.get(type_counts, "dialogue", 0),
         condition_count: Map.get(type_counts, "condition", 0)
       }}
    end)
  end

  @doc """
  Returns per-flow counts for all localizable words in each flow.
  Returns `%{flow_id => word_count}`.
  """
  @spec flow_word_counts(integer()) :: %{integer() => non_neg_integer()}
  def flow_word_counts(project_id) when is_integer(project_id) do
    localizable_node_types = ContentContract.localizable_node_types()

    from(node in FlowNode,
      join: flow in Flow,
      on: flow.id == node.flow_id,
      where:
        flow.project_id == ^project_id and is_nil(flow.deleted_at) and
          is_nil(node.deleted_at) and node.type in ^localizable_node_types,
      group_by: node.flow_id,
      select: {node.flow_id, coalesce(sum(node.word_count), 0)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Returns the player-facing word count for an already-loaded Flow."
  @spec flow_word_count(Flow.t()) :: non_neg_integer()
  def flow_word_count(%Flow{nodes: nodes}) when is_list(nodes) do
    localizable_node_types = ContentContract.localizable_node_types()

    Enum.reduce(nodes, 0, fn node, total ->
      if node.type in localizable_node_types, do: total + (node.word_count || 0), else: total
    end)
  end

  @doc """
  Returns the node type distribution across every flow in a project.

  Returns a map of `%{"dialogue" => 42, "condition" => 15, ...}`. Types with no
  nodes are absent.

  Named for its scope because `NodeCrud.count_nodes_by_type/1` counts within ONE
  flow — same shape, different question.
  """
  def count_project_nodes_by_type(project_id) do
    from(n in FlowNode,
      join: f in Flow,
      on: n.flow_id == f.id,
      where: f.project_id == ^project_id and is_nil(n.deleted_at) and is_nil(f.deleted_at),
      group_by: n.type,
      select: {n.type, count(n.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns the top speakers by dialogue line count across every flow in a project.

  Returns a list of `%{sheet_id: id, sheet_name: name, line_count: count}` sorted
  by line count descending.
  """
  def count_dialogue_lines_by_speaker(project_id, limit \\ 10) do
    Repo.all(
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        left_join: s in SheetRecord,
        on: SpeakerSheetId.safe_query_value(n.data) == s.id,
        where:
          f.project_id == ^project_id and is_nil(n.deleted_at) and is_nil(f.deleted_at) and n.type == "dialogue" and
            not is_nil(SpeakerSheetId.safe_query_value(n.data)),
        group_by: [SpeakerSheetId.safe_query_value(n.data), s.name, s.id],
        select: %{
          sheet_id: SpeakerSheetId.safe_query_value(n.data),
          sheet_name: s.name,
          line_count: count(n.id)
        },
        order_by: [desc: count(n.id)],
        limit: ^limit
      )
    )
  end

  # ===========================================================================
  # Issue Detection
  # ===========================================================================

  @doc """
  Project-wide flow health findings for the dashboard.

  It reads the same findings the editor shows through the same composition point
  (`StructuralAnalysis.findings/1`) — the dashboard reimplements nothing of the
  vocabulary, so the two surfaces cannot disagree.

  This replaced `detect_flow_issues/1`, which mapped 4 of the 15 structural rules
  into 3 coarse buckets, dropped every reference-integrity error, and never ran
  the editorial checks at all. Counts therefore go UP: that is the correction.

  Cost is flat in flow count: one project-variable query, the topology load,
  and one batched stale-reference
  query for every flow at once. The per-flow pair this used to issue is what
  made it an O(N) sweep. The dashboard also caches it for 30s.
  """
  def list_dashboard_health_findings(project_id) do
    project_id
    |> Topology.load_project()
    |> health_findings(project_id, %{})
  end

  @doc """
  Health findings for an already-loaded export selection.

  Uses the same canonical health composition as the dashboard, but scopes graph
  work and stale-reference loading to the flows selected for the artifact.
  Callers that already loaded the project variable catalogue and stale-reference
  index may pass both in `context` to keep the whole validation pass query-flat.
  """
  def list_export_health_findings(project_id, flows, context \\ %{}) when is_list(flows) and is_map(context) do
    flows
    |> Topology.from_loaded_many()
    |> health_findings(project_id, context)
  end

  defp health_findings(topologies, project_id, context) do
    # The SAME set the editor uses, or the two surfaces disagree about type
    # warnings on any assignment to a scene pin or zone property. Keyed ONCE for
    # the whole sweep: rebuilt per node this was 1599 ms of a 1666 ms sweep at
    # 200 flows / 4000 variables — 96% of it.
    variable_types =
      context
      |> Map.get_lazy(:referenceable_variables, fn ->
        VariableCatalog.list_referenceable(project_id)
      end)
      |> Instruction.variable_type_map()

    # Batched, like the sheets and scenes sweeps: the per-flow pair of
    # stale-reference queries made this O(N) — 2 queries per flow — while the
    # other two domains are flat. Two queries total now.
    stale_by_flow =
      Map.get_lazy(context, :stale_node_ids_by_flow, fn ->
        topologies
        |> Enum.map(& &1.flow_id)
        |> VariableReferenceTracker.list_stale_node_ids_by_flow()
      end)

    Enum.flat_map(topologies, fn topology ->
      stale_node_ids = Map.get(stale_by_flow, topology.flow_id, MapSet.new())
      nodes = HealthFlags.add(topology.nodes, stale_node_ids, variable_types)
      node_labels = Map.new(nodes, &{&1.id, NodeLabel.specific_for_node(&1)})

      %{topology | nodes: nodes}
      |> StructuralAnalysis.findings()
      # The flow name rides in `details` so the caller needs no second query;
      # `sheet_stats.ex` does the same with `sheet_name`.
      |> Enum.map(fn finding ->
        details =
          finding.details
          |> Map.put(:flow_name, topology.flow_name)
          |> maybe_put_entity_label(finding.entity_id, node_labels)

        %{finding | details: details}
      end)
    end)
  end

  defp maybe_put_entity_label(details, nil, _node_labels), do: details

  defp maybe_put_entity_label(details, entity_id, node_labels) do
    case Map.get(node_labels, entity_id) do
      nil -> details
      label -> Map.put(details, :entity_label, label)
    end
  end
end
