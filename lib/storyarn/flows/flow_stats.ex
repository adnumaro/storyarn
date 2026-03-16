defmodule Storyarn.Flows.FlowStats do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.{Flow, FlowNode}
  alias Storyarn.Localization.LocalizableWords
  alias Storyarn.Projects.Dashboard
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
  Detects issues in flows for a project.
  Returns `[%{flow_id, flow_name, issue_type, count}]`.

  Issue types:
  - `:no_entry` — flow has no entry node
  - `:disconnected_nodes` — flow has nodes with zero connections
  """
  def detect_flow_issues(project_id) do
    no_entry = detect_no_entry_issues(project_id)
    disconnected = detect_disconnected_issues(project_id)
    no_entry ++ disconnected
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp detect_no_entry_issues(project_id) do
    project_id
    |> Dashboard.flows_without_entry()
    |> Enum.map(&%{flow_id: &1.flow_id, flow_name: &1.flow_name, issue_type: :no_entry, count: 1})
  end

  defp detect_disconnected_issues(project_id) do
    project_id
    |> Dashboard.flows_with_disconnected_nodes()
    |> Enum.map(
      &%{
        flow_id: &1.flow_id,
        flow_name: &1.flow_name,
        issue_type: :disconnected_nodes,
        count: &1.count
      }
    )
  end
end
