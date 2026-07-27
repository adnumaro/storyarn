defmodule Storyarn.Projects.Dashboard do
  @moduledoc """
  Aggregates dashboard data across all project contexts.

  Provides project-level statistics, per-tool health counts, and recent activity
  for the project overview. Calls existing facade functions where possible and
  only implements new queries when needed.

  This module renders no text. It used to build `dgettext` sentences for the
  overview's issue list, inside a `Task.async` that does not inherit the
  Gettext locale and whose result is cached in a cross-user ETS table — so the
  list shipped in English to Spanish readers, and seeding the locale in the task
  would only have swapped that for serving the first reader's language to
  everyone. `tool_health_summary/1` returns counts instead, and the client
  renders them.
  """

  import Ecto.Query

  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Shared.Severity
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet

  @tools [:flows, :sheets, :scenes]

  # ===========================================================================
  # Project Stats
  # ===========================================================================

  @doc """
  Returns aggregate statistics for the project dashboard.

  Calls existing facade functions for counts that already exist,
  and uses private helpers for new aggregations.
  """
  def project_stats(project_id) do
    %{
      sheet_count: Sheets.count_sheets(project_id),
      variable_count: count_variables(project_id),
      flow_count: Flows.count_flows(project_id),
      dialogue_count: count_dialogue_nodes(project_id),
      scene_count: Scenes.count_scenes(project_id),
      total_word_count: count_total_words(project_id)
    }
  end

  # ===========================================================================
  # Tool Health
  # ===========================================================================

  @doc "The tools that report authoring health, in display order."
  def tools, do: @tools

  @doc """
  Rolls the three health sweeps up into per-tool severity counts.

  Takes the canonical findings the tool dashboards already load — this function
  runs no queries, so the caller keeps ownership of caching and can reuse the
  very cache entries those dashboards fill.

  Returns `%{flows: counts, sheets: counts, scenes: counts}`, where counts is
  `%{error: n, warning: n, info: n, actionable: n}`. `actionable` is errors plus
  warnings: it is the number the overview reports, because an `:info` finding is
  a note about valid content, not something the reader has to go fix. A tool
  with only `:info` findings reads as up to date.

  Counts, not sentences — no locale, no slugs. That is what makes the result
  safe to cache across users, and it is why the overview cannot regress into the
  cross-user locale leak it had.
  """
  def tool_health_summary(findings_by_tool) do
    Map.new(@tools, fn tool ->
      {tool, count_by_severity(Map.fetch!(findings_by_tool, tool))}
    end)
  end

  defp count_by_severity(findings) do
    counts = Enum.frequencies_by(findings, & &1.severity)
    summary = Map.new(Severity.catalog(), &{&1, Map.get(counts, &1, 0)})

    Map.put(summary, :actionable, summary.error + summary.warning)
  end

  # ===========================================================================
  # Recent Activity
  # ===========================================================================

  @doc """
  Returns recent changes across all entity types.

  Returns a list of `%{name: String.t(), type: String.t(), updated_at: DateTime.t()}`
  sorted by most recent first.
  """
  def recent_activity(project_id, limit \\ 10) do
    sheets_query =
      from(s in Sheet,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        select: %{
          name: s.name,
          type: "sheet",
          entity_id: s.id,
          updated_at: s.updated_at
        }
      )

    flows_query =
      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        select: %{
          name: f.name,
          type: "flow",
          entity_id: f.id,
          updated_at: f.updated_at
        }
      )

    scenes_query =
      from(s in "scenes",
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        select: %{
          name: s.name,
          type: "scene",
          entity_id: s.id,
          updated_at: s.updated_at
        }
      )

    screenplays_query =
      from(sp in "screenplays",
        where: sp.project_id == ^project_id and is_nil(sp.deleted_at),
        select: %{
          name: sp.name,
          type: "screenplay",
          entity_id: sp.id,
          updated_at: sp.updated_at
        }
      )

    sheets_query
    |> union_all(^flows_query)
    |> union_all(^scenes_query)
    |> union_all(^screenplays_query)
    |> subquery()
    |> order_by([r], desc: r.updated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  # ===========================================================================
  # Private Helpers — New Queries
  # ===========================================================================

  # Uses existing Sheets.list_project_variables/1 which handles both
  # regular block variables AND table cell variables (TableColumn + TableRow).
  # A custom count query would miss table variables.
  defp count_variables(project_id) do
    project_id |> Sheets.list_project_variables() |> length()
  end

  defp count_dialogue_nodes(project_id) do
    Repo.aggregate(
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where: f.project_id == ^project_id and is_nil(n.deleted_at) and is_nil(f.deleted_at) and n.type == "dialogue"
      ),
      :count
    )
  end

  # Runtime word volume follows the same contract as localization and engine
  # exports. Scenes and screenplays are editor-only and intentionally excluded.
  defp count_total_words(project_id) do
    flow_words =
      project_id
      |> Flows.flow_word_counts()
      |> Map.values()
      |> Enum.sum()

    sheet_words =
      project_id
      |> Sheets.sheet_word_counts()
      |> Map.values()
      |> Enum.sum()

    flow_words + sheet_words
  end
end
