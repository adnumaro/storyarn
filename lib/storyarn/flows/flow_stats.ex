defmodule Storyarn.Flows.FlowStats do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.StructuralAnalysis
  alias Storyarn.Localization.LocalizableWords
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

  # Legacy dashboard buckets ← canonical rules. The three issue types keep
  # their public contract while the counts come from the canonical engine, so
  # dashboards cannot disagree with the editor about the same rule.
  # `unreachable_node` folds into :disconnected_nodes (disconnected from
  # Entry) so detached chains — which the old SQL surfaced as dead ends —
  # keep dashboard coverage without a UI change.
  @issue_type_rules [
    no_entry: ["missing_entry"],
    disconnected_nodes: ["isolated_node", "unreachable_node"],
    dead_end_nodes: ["no_outgoing_connection"]
  ]

  @doc """
  Detects issues in flows for a project through the canonical structural
  analysis. Returns `[%{flow_id, flow_name, issue_type, count}]`.

  Issue types:
  - `:no_entry` — flow has no entry node
  - `:disconnected_nodes` — flow has isolated or Entry-unreachable nodes
  - `:dead_end_nodes` — flow has reachable nodes without outgoing connections
  """
  def detect_flow_issues(project_id) do
    analyses = StructuralAnalysis.analyze_project(project_id)

    Enum.flat_map(@issue_type_rules, fn {issue_type, rule_ids} ->
      analyses
      |> Enum.map(&issue_row(&1, issue_type, rule_ids))
      |> Enum.reject(&is_nil/1)
    end)
  end

  defp issue_row(analysis, issue_type, rule_ids) do
    case Enum.count(analysis.findings, &(&1.rule_id in rule_ids)) do
      0 ->
        nil

      count ->
        %{
          flow_id: analysis.flow_id,
          flow_name: analysis.flow_name,
          issue_type: issue_type,
          count: count
        }
    end
  end
end
