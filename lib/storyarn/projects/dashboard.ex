defmodule Storyarn.Projects.Dashboard do
  @moduledoc """
  Aggregates dashboard data across all project contexts.

  Provides project-level statistics, issue detection, and recent activity
  for the project dashboard. Calls existing facade functions where possible
  and only implements new queries when needed.
  """

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query

  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Localization
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet

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
  # Content Breakdown
  # ===========================================================================

  @doc """
  Returns node type distribution across all flows in a project.

  Returns a map of `%{"dialogue" => 42, "condition" => 15, ...}`.
  """
  def count_all_nodes_by_type(project_id) do
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
  Returns top speakers by dialogue line count.

  Returns a list of `%{sheet_id: id, sheet_name: name, line_count: count}`
  sorted by line count descending.
  """
  def count_dialogue_lines_by_speaker(project_id, limit \\ 10) do
    Repo.all(
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        left_join: s in Sheet,
        on: type(fragment("(?->>'speaker_sheet_id')::integer", n.data), :integer) == s.id,
        where:
          f.project_id == ^project_id and is_nil(n.deleted_at) and is_nil(f.deleted_at) and n.type == "dialogue" and
            not is_nil(fragment("?->>'speaker_sheet_id'", n.data)),
        group_by: [fragment("(?->>'speaker_sheet_id')::integer", n.data), s.name, s.id],
        select: %{
          sheet_id: fragment("(?->>'speaker_sheet_id')::integer", n.data),
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
  Detects project issues across all contexts.

  Returns a list of `%{severity: atom, message: String.t(), href: String.t(), count: integer}`
  sorted by severity (error > warning > info).
  """
  def detect_issues(project_id, opts \\ []) do
    workspace_slug = Keyword.fetch!(opts, :workspace_slug)
    project_slug = Keyword.fetch!(opts, :project_slug)

    flow_findings = Flows.list_dashboard_health_findings(project_id)

    [
      detect_flow_health(flow_findings, workspace_slug, project_slug),
      detect_empty_sheets(project_id, workspace_slug, project_slug),
      detect_untranslated_content(project_id, workspace_slug, project_slug)
    ]
    |> List.flatten()
    |> Enum.sort_by(& &1.severity, &severity_order/2)
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

  # ---------------------------------------------------------------------------
  # Issue Detectors (formatters over the canonical flow analysis)
  # ---------------------------------------------------------------------------

  # The project overview is a CURATED cross-domain summary, not full coverage:
  # every domain contributes a few high-signal rows with a written sentence
  # (`detect_empty_sheets` does exactly this for sheets). So flows keeps specific
  # copy here — but driven by the canonical findings, so it cannot drift from the
  # flows dashboard the way the old bucket mapping did.
  #
  # Anything outside the curated set still gets a row per flow and severity, so no
  # finding is silently dropped from the overview.
  @curated_codes %{
    missing_entry: :no_entry,
    isolated_node: :disconnected,
    unreachable_node: :disconnected,
    no_outgoing_connection: :dead_end
  }

  defp detect_flow_health(findings, workspace_slug, project_slug) do
    {curated, rest} = Enum.split_with(findings, &Map.has_key?(@curated_codes, &1.code))

    curated_rows =
      curated
      |> Enum.group_by(&{&1.flow_id, Map.fetch!(@curated_codes, &1.code)})
      |> Enum.map(fn {{flow_id, kind}, group} ->
        flow_health_row(kind, hd(group), length(group), flow_id, workspace_slug, project_slug)
      end)

    other_rows =
      rest
      |> Enum.filter(&(&1.severity in [:error, :warning]))
      |> Enum.group_by(&{&1.flow_id, &1.severity})
      |> Enum.map(fn {{flow_id, severity}, group} ->
        %{
          severity: severity,
          message: other_flow_health_message(severity, flow_name(hd(group)), length(group)),
          href: flow_href(workspace_slug, project_slug, flow_id),
          count: length(group)
        }
      end)

    Enum.sort_by(curated_rows ++ other_rows, & &1.message)
  end

  defp flow_health_row(:no_entry, finding, _count, flow_id, workspace_slug, project_slug) do
    %{
      severity: :error,
      message: dgettext("flows", "Flow \"%{name}\" has no entry node", name: flow_name(finding)),
      href: flow_href(workspace_slug, project_slug, flow_id),
      count: 1
    }
  end

  defp flow_health_row(:disconnected, finding, count, flow_id, workspace_slug, project_slug) do
    %{
      severity: :warning,
      message:
        dgettext("flows", "Flow \"%{name}\" has %{count} disconnected node(s)",
          name: flow_name(finding),
          count: count
        ),
      href: flow_href(workspace_slug, project_slug, flow_id),
      count: count
    }
  end

  defp flow_health_row(:dead_end, finding, count, flow_id, workspace_slug, project_slug) do
    %{
      severity: :warning,
      message:
        dgettext("flows", "Flow \"%{name}\" has %{count} node(s) without outgoing connection",
          name: flow_name(finding),
          count: count
        ),
      href: flow_href(workspace_slug, project_slug, flow_id),
      count: count
    }
  end

  defp other_flow_health_message(:error, flow_name, count) do
    dgettext("flows", "Flow \"%{name}\" has %{count} error(s)", name: flow_name, count: count)
  end

  defp other_flow_health_message(:warning, flow_name, count) do
    dgettext("flows", "Flow \"%{name}\" has %{count} warning(s)", name: flow_name, count: count)
  end

  defp flow_name(finding), do: Map.get(finding.details, :flow_name, dgettext("flows", "Flow"))

  defp flow_href(workspace_slug, project_slug, flow_id) do
    "/workspaces/#{workspace_slug}/projects/#{project_slug}/flows/#{flow_id}"
  end

  defp detect_empty_sheets(project_id, workspace_slug, project_slug) do
    sheets_with_blocks_ids =
      from(b in Block,
        join: s in Sheet,
        on: b.sheet_id == s.id,
        where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(b.deleted_at),
        select: s.id
      )

    empty_sheets =
      Repo.all(
        from(s in Sheet,
          where: s.project_id == ^project_id and is_nil(s.deleted_at) and s.id not in subquery(sheets_with_blocks_ids),
          select: %{id: s.id, name: s.name}
        )
      )

    case empty_sheets do
      [] ->
        []

      sheets ->
        count = length(sheets)

        [
          %{
            severity: :info,
            message:
              dngettext(
                "sheets",
                "%{count} sheet has no blocks defined",
                "%{count} sheets have no blocks defined",
                count,
                count: count
              ),
            href: "/workspaces/#{workspace_slug}/projects/#{project_slug}/sheets",
            count: count
          }
        ]
    end
  end

  defp detect_untranslated_content(project_id, workspace_slug, project_slug) do
    languages = Localization.list_languages(project_id)
    target_languages = Enum.reject(languages, & &1.is_source)

    if target_languages == [] do
      []
    else
      progress = Localization.progress_by_language(project_id)

      progress
      |> Enum.reject(&(&1.percentage >= 100.0))
      |> Enum.map(fn lang ->
        pending = lang.total - lang.final

        %{
          severity: :warning,
          message:
            dngettext(
              "localization",
              "%{language}: %{count} text pending translation (%{percent}% done)",
              "%{language}: %{count} texts pending translation (%{percent}% done)",
              pending,
              language: lang.name,
              count: pending,
              percent: round(lang.percentage)
            ),
          href: "/workspaces/#{workspace_slug}/projects/#{project_slug}/localization",
          count: pending
        }
      end)
    end
  end

  # Severity ordering: :error < :warning < :info (error first)
  defp severity_order(a, b), do: severity_rank(a) <= severity_rank(b)
  defp severity_rank(:error), do: 0
  defp severity_rank(:warning), do: 1
  defp severity_rank(:info), do: 2
end
