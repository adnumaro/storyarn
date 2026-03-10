defmodule Storyarn.Projects.Dashboard do
  @moduledoc """
  Aggregates dashboard data across all project contexts.

  Provides project-level statistics, issue detection, and recent activity
  for the project dashboard. Calls existing facade functions where possible
  and only implements new queries when needed.
  """

  import Ecto.Query

  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Shared.HtmlUtils
  alias Storyarn.Sheets

  alias Storyarn.Flows.{Flow, FlowConnection, FlowNode}
  alias Storyarn.Sheets.{Block, Sheet}

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
    from(n in FlowNode,
      join: f in Flow,
      on: n.flow_id == f.id,
      left_join: s in Sheet,
      on: type(fragment("(?->>'speaker_sheet_id')::integer", n.data), :integer) == s.id,
      where:
        f.project_id == ^project_id and
          is_nil(n.deleted_at) and
          is_nil(f.deleted_at) and
          n.type == "dialogue" and
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
    |> Repo.all()
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
    from(n in FlowNode,
      join: f in Flow,
      on: n.flow_id == f.id,
      where:
        f.project_id == ^project_id and
          is_nil(n.deleted_at) and
          is_nil(f.deleted_at) and
          n.type == "dialogue"
    )
    |> Repo.aggregate(:count)
  end

  # Hybrid word count: SUM(word_count) for heavy content (dialogue, text blocks)
  # + lightweight text queries for metadata (names, labels, descriptions).
  # At 800K-word scale, content is 99%+ of total; metadata is ~300KB transfer.
  defp count_total_words(project_id) do
    content_words = sum_flow_word_counts(project_id) + sum_block_word_counts(project_id)

    metadata_texts =
      collect_flow_metadata(project_id) ++
        collect_sheet_metadata(project_id) ++
        collect_scene_metadata(project_id) ++
        collect_screenplay_metadata(project_id)

    metadata_words =
      metadata_texts
      |> List.flatten()
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.map(&HtmlUtils.word_count/1)
      |> Enum.sum()

    content_words + metadata_words
  end

  defp sum_flow_word_counts(project_id) do
    from(n in FlowNode,
      join: f in Flow,
      on: n.flow_id == f.id,
      where: f.project_id == ^project_id and is_nil(n.deleted_at) and is_nil(f.deleted_at),
      select: coalesce(sum(n.word_count), 0)
    )
    |> Repo.one()
  end

  defp sum_block_word_counts(project_id) do
    from(b in Block,
      join: s in Sheet,
      on: b.sheet_id == s.id,
      where: s.project_id == ^project_id and is_nil(b.deleted_at) and is_nil(s.deleted_at),
      select: coalesce(sum(b.word_count), 0)
    )
    |> Repo.one()
  end

  # -- Flow metadata: names, descriptions, slug line texts, case labels, connection labels
  # (dialogue/response/menu text is in word_count — NOT loaded here)

  defp collect_flow_metadata(project_id) do
    flow_texts =
      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        select: [f.name, f.description]
      )
      |> Repo.all()

    slug_texts =
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where:
          f.project_id == ^project_id and is_nil(n.deleted_at) and is_nil(f.deleted_at) and
            n.type == "slug_line",
        select: [
          fragment("?->>'location'", n.data),
          fragment("?->>'description'", n.data),
          fragment("?->>'sub_location'", n.data)
        ]
      )
      |> Repo.all()

    case_labels =
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where:
          f.project_id == ^project_id and is_nil(n.deleted_at) and is_nil(f.deleted_at) and
            n.type == "condition",
        select: fragment("?->'cases'", n.data)
      )
      |> Repo.all()
      |> Enum.flat_map(fn
        cases when is_list(cases) -> Enum.map(cases, &Map.get(&1, "label"))
        _ -> []
      end)

    conn_labels =
      from(c in FlowConnection,
        join: f in Flow,
        on: c.flow_id == f.id,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        select: c.label
      )
      |> Repo.all()

    flow_texts ++ slug_texts ++ case_labels ++ conn_labels
  end

  # -- Sheet metadata: names, descriptions, block labels/placeholders/options
  # (block text/rich_text content is in word_count — NOT loaded here)

  defp collect_sheet_metadata(project_id) do
    sheet_texts = query_sheet_texts(project_id)
    block_labels = query_block_labels(project_id)
    option_values = query_block_option_values(project_id)
    table_col_names = query_table_column_names(project_id)
    table_row_names = query_table_row_names(project_id)
    gallery_texts = query_gallery_texts(project_id)

    sheet_texts ++ block_labels ++ option_values ++ table_col_names ++ table_row_names ++
      gallery_texts
  end

  defp query_sheet_texts(project_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      select: [s.name, s.description]
    )
    |> Repo.all()
  end

  defp query_block_labels(project_id) do
    from(b in Block,
      join: s in Sheet,
      on: b.sheet_id == s.id,
      where: s.project_id == ^project_id and is_nil(b.deleted_at) and is_nil(s.deleted_at),
      select: [fragment("?->>'label'", b.config), fragment("?->>'placeholder'", b.config)]
    )
    |> Repo.all()
  end

  defp query_block_option_values(project_id) do
    from(b in Block,
      join: s in Sheet,
      on: b.sheet_id == s.id,
      where:
        s.project_id == ^project_id and is_nil(b.deleted_at) and is_nil(s.deleted_at) and
          b.type in ["select", "multi_select"],
      select: fragment("?->'options'", b.config)
    )
    |> Repo.all()
    |> Enum.flat_map(fn
      opts when is_list(opts) -> Enum.map(opts, &Map.get(&1, "value"))
      _ -> []
    end)
  end

  defp query_table_column_names(project_id) do
    from(tc in "table_columns",
      join: b in "blocks",
      on: tc.block_id == b.id,
      join: s in "sheets",
      on: b.sheet_id == s.id,
      where: s.project_id == ^project_id and is_nil(b.deleted_at) and is_nil(s.deleted_at),
      select: tc.name
    )
    |> Repo.all()
  end

  defp query_table_row_names(project_id) do
    from(tr in "table_rows",
      join: b in "blocks",
      on: tr.block_id == b.id,
      join: s in "sheets",
      on: b.sheet_id == s.id,
      where: s.project_id == ^project_id and is_nil(b.deleted_at) and is_nil(s.deleted_at),
      select: tr.name
    )
    |> Repo.all()
  end

  defp query_gallery_texts(project_id) do
    from(gi in "block_gallery_images",
      join: b in "blocks",
      on: gi.block_id == b.id,
      join: s in "sheets",
      on: b.sheet_id == s.id,
      where: s.project_id == ^project_id and is_nil(b.deleted_at) and is_nil(s.deleted_at),
      select: [gi.label, gi.description]
    )
    |> Repo.all()
  end

  # -- Scene metadata: names, descriptions, layer/zone/pin/annotation/connection labels

  defp collect_scene_metadata(project_id) do
    scene_texts =
      from(s in "scenes",
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        select: [s.name, s.description]
      )
      |> Repo.all()

    layer_names =
      from(l in "scene_layers",
        join: s in "scenes",
        on: l.scene_id == s.id,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        select: l.name
      )
      |> Repo.all()

    zone_texts =
      from(z in "scene_zones",
        join: s in "scenes",
        on: z.scene_id == s.id,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        select: [z.name, z.tooltip]
      )
      |> Repo.all()

    pin_texts =
      from(p in "scene_pins",
        join: s in "scenes",
        on: p.scene_id == s.id,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        select: [p.label, p.tooltip]
      )
      |> Repo.all()

    annotation_texts =
      from(a in "scene_annotations",
        join: s in "scenes",
        on: a.scene_id == s.id,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        select: a.text
      )
      |> Repo.all()

    conn_labels =
      from(c in "scene_connections",
        join: s in "scenes",
        on: c.scene_id == s.id,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        select: c.label
      )
      |> Repo.all()

    scene_texts ++ layer_names ++ zone_texts ++ pin_texts ++ annotation_texts ++ conn_labels
  end

  # -- Screenplay metadata: names, descriptions, element content

  defp collect_screenplay_metadata(project_id) do
    screenplay_texts =
      from(sp in "screenplays",
        where: sp.project_id == ^project_id and is_nil(sp.deleted_at),
        select: [sp.name, sp.description]
      )
      |> Repo.all()

    element_texts =
      from(e in "screenplay_elements",
        join: sp in "screenplays",
        on: e.screenplay_id == sp.id,
        where: sp.project_id == ^project_id and is_nil(sp.deleted_at),
        select: e.content
      )
      |> Repo.all()

    screenplay_texts ++ element_texts
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

    from(f in Flow,
      where:
        f.project_id == ^project_id and
          is_nil(f.deleted_at) and
          f.id not in subquery(flows_with_entry_ids),
      select: %{flow_id: f.id, flow_name: f.name}
    )
    |> Repo.all()
  end

  @doc "Returns flows with disconnected nodes. Returns `[%{flow_id, flow_name, count}]`."
  def flows_with_disconnected_nodes(project_id) do
    from(n in FlowNode,
      join: f in Flow,
      on: n.flow_id == f.id,
      left_join: cs in FlowConnection,
      on: cs.source_node_id == n.id,
      left_join: ct in FlowConnection,
      on: ct.target_node_id == n.id,
      where:
        f.project_id == ^project_id and
          is_nil(n.deleted_at) and
          is_nil(f.deleted_at) and
          is_nil(cs.id) and
          is_nil(ct.id),
      group_by: [f.id, f.name],
      select: %{flow_id: f.id, flow_name: f.name, count: count(n.id)}
    )
    |> Repo.all()
  end

  defp detect_flows_without_entry(project_id, workspace_slug, project_slug) do
    project_id
    |> flows_without_entry()
    |> Enum.map(fn flow ->
      %{
        severity: :error,
        message: "Flow \"#{flow.flow_name}\" has no entry node",
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
        message: "Flow \"#{row.flow_name}\" has #{row.count} disconnected node(s)",
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
      from(s in Sheet,
        where:
          s.project_id == ^project_id and
            is_nil(s.deleted_at) and
            s.id not in subquery(sheets_with_blocks_ids),
        select: %{id: s.id, name: s.name}
      )
      |> Repo.all()

    case empty_sheets do
      [] ->
        []

      sheets ->
        count = length(sheets)

        [
          %{
            severity: :info,
            message: "#{count} sheet(s) have no blocks defined",
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
            "#{lang.name}: #{pending} text(s) pending translation " <>
              "(#{round(lang.percentage)}% done)",
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
