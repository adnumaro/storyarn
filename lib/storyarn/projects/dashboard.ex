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
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeConnectionRules
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

    [
      detect_flows_without_entry(project_id, workspace_slug, project_slug),
      detect_disconnected_nodes(project_id, workspace_slug, project_slug),
      detect_dead_end_nodes(project_id, workspace_slug, project_slug),
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
  # Issue Detectors (public raw queries + private formatters)
  # ---------------------------------------------------------------------------

  @doc "Returns flows without entry nodes. Returns `[%{flow_id, flow_name}]`."
  def flows_without_entry(project_id) do
    flows_with_entry_ids =
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where:
          f.project_id == ^project_id and
            is_nil(f.deleted_at) and
            is_nil(n.deleted_at) and
            n.type == "entry",
        select: f.id
      )

    Repo.all(
      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at) and f.id not in subquery(flows_with_entry_ids),
        select: %{flow_id: f.id, flow_name: f.name}
      )
    )
  end

  @doc "Returns flows with disconnected nodes. Returns `[%{flow_id, flow_name, count}]`."
  def flows_with_disconnected_nodes(project_id) do
    connection_optional_types = NodeConnectionRules.connection_optional_types()

    project_id
    |> active_node_connection_counts(connection_optional_types)
    |> Enum.filter(&(&1.valid_outgoing_count == 0 and &1.valid_incoming_count == 0))
    |> group_flow_node_counts()
  end

  @doc "Returns flows with nodes that need an outgoing connection but do not have one."
  def flows_with_dead_end_nodes(project_id) do
    outgoing_optional_types = NodeConnectionRules.outgoing_optional_types()

    project_id
    |> active_node_connection_counts(outgoing_optional_types)
    |> Enum.filter(&(&1.valid_outgoing_count == 0 and &1.valid_incoming_count > 0))
    |> group_flow_node_counts()
  end

  defp active_node_connection_counts(project_id, ignored_types) do
    Repo.all(
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        left_join: cs in FlowConnection,
        on: cs.source_node_id == n.id,
        left_join: target in FlowNode,
        on: target.id == cs.target_node_id and target.flow_id == f.id and is_nil(target.deleted_at),
        left_join: ct in FlowConnection,
        on: ct.target_node_id == n.id,
        left_join: source in FlowNode,
        on: source.id == ct.source_node_id and source.flow_id == f.id and is_nil(source.deleted_at),
        where:
          f.project_id == ^project_id and
            is_nil(n.deleted_at) and
            is_nil(f.deleted_at) and
            n.type not in ^ignored_types,
        group_by: [f.id, f.name, n.id],
        select: %{
          flow_id: f.id,
          flow_name: f.name,
          node_id: n.id,
          valid_outgoing_count: count(target.id),
          valid_incoming_count: count(source.id)
        }
      )
    )
  end

  defp group_flow_node_counts(rows) do
    rows
    |> Enum.group_by(&{&1.flow_id, &1.flow_name})
    |> Enum.map(fn {{flow_id, flow_name}, rows} ->
      %{flow_id: flow_id, flow_name: flow_name, count: length(rows)}
    end)
  end

  defp detect_flows_without_entry(project_id, workspace_slug, project_slug) do
    project_id
    |> flows_without_entry()
    |> Enum.map(fn flow ->
      %{
        severity: :error,
        message: dgettext("flows", "Flow \"%{name}\" has no entry node", name: flow.flow_name),
        href: "/workspaces/#{workspace_slug}/projects/#{project_slug}/flows/#{flow.flow_id}",
        count: 1
      }
    end)
  end

  defp detect_disconnected_nodes(project_id, workspace_slug, project_slug) do
    project_id
    |> flows_with_disconnected_nodes()
    |> Enum.map(fn row ->
      %{
        severity: :warning,
        message:
          dgettext(
            "flows",
            "Flow \"%{name}\" has %{count} disconnected node(s)",
            name: row.flow_name,
            count: row.count
          ),
        href: "/workspaces/#{workspace_slug}/projects/#{project_slug}/flows/#{row.flow_id}",
        count: row.count
      }
    end)
  end

  defp detect_dead_end_nodes(project_id, workspace_slug, project_slug) do
    project_id
    |> flows_with_dead_end_nodes()
    |> Enum.map(fn row ->
      %{
        severity: :warning,
        message:
          dgettext(
            "flows",
            "Flow \"%{name}\" has %{count} node(s) without outgoing connection",
            name: row.flow_name,
            count: row.count
          ),
        href: "/workspaces/#{workspace_slug}/projects/#{project_slug}/flows/#{row.flow_id}",
        count: row.count
      }
    end)
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
