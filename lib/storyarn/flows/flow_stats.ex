defmodule Storyarn.Flows.FlowStats do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.StructuralAnalysis
  alias Storyarn.Flows.StructuralAnalysis.Topology
  alias Storyarn.Localization.LocalizableWords
  alias Storyarn.References
  alias Storyarn.Repo

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
  defdelegate flow_word_counts(project_id), to: LocalizableWords

  # ===========================================================================
  # Issue Detection
  # ===========================================================================

  @doc """
  Project-wide flow health findings for the dashboard.

  The sibling of `Sheets.list_dashboard_health_findings/2` and
  `Scenes.list_dashboard_health_findings/1`, and it reads the SAME findings the
  editor shows through the SAME composition point
  (`StructuralAnalysis.findings/1`) — the dashboard reimplements nothing of the
  vocabulary, so the two surfaces cannot disagree.

  This replaced `detect_flow_issues/1`, which mapped 4 of the 15 structural rules
  into 3 coarse buckets, dropped every reference-integrity error, and never ran
  the editorial checks at all. Counts therefore go UP: that is the correction.

  Cost is flat in flow count, like the sheets and scenes sweeps: one
  project-variable query, the topology load, and ONE batched stale-reference
  query for every flow at once. The per-flow pair this used to issue is what
  made it the only O(N) sweep of the three. The dashboard also caches it for 30s.
  """
  def list_dashboard_health_findings(project_id) do
    # The SAME set the editor uses, or the two surfaces disagree about type
    # warnings on any assignment to a scene pin or zone property. Keyed ONCE for
    # the whole sweep: rebuilt per node this was 1599 ms of a 1666 ms sweep at
    # 200 flows / 4000 variables — 96% of it.
    variable_types =
      project_id
      |> Flows.list_referenceable_variables()
      |> Flows.variable_type_map()

    topologies = Topology.load_project(project_id)

    # Batched, like the sheets and scenes sweeps: the per-flow pair of
    # stale-reference queries made this O(N) — 2 queries per flow — while the
    # other two domains are flat. Two queries total now.
    stale_by_flow =
      topologies
      |> Enum.map(& &1.flow_id)
      |> References.list_stale_node_ids_by_flow()

    Enum.flat_map(topologies, fn topology ->
      stale_node_ids = Map.get(stale_by_flow, topology.flow_id, MapSet.new())
      nodes = Flows.add_health_flags(topology.nodes, stale_node_ids, variable_types)

      %{topology | nodes: nodes}
      |> StructuralAnalysis.findings()
      # The flow name rides in `details` so the caller needs no second query;
      # `sheet_stats.ex` does the same with `sheet_name`.
      |> Enum.map(&%{&1 | details: Map.put(&1.details, :flow_name, topology.flow_name)})
    end)
  end
end
