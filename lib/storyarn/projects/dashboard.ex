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

  defp count_total_words(project_id) do
    texts =
      collect_flow_texts(project_id) ++
        collect_sheet_texts(project_id) ++
        collect_scene_texts(project_id) ++
        collect_screenplay_texts(project_id)

    texts
    |> List.flatten()
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.map(&count_words/1)
    |> Enum.sum()
  end

  # -- Flow texts: names, descriptions, dialogue, responses, slug lines, condition labels

  defp collect_flow_texts(project_id) do
    flow_texts = fetch_flow_texts(project_id)
    dialogue_texts = fetch_dialogue_texts(project_id)
    slug_texts = fetch_slug_texts(project_id)
    case_labels = fetch_case_labels(project_id)
    conn_labels = fetch_flow_connection_labels(project_id)

    flow_texts ++ dialogue_texts ++ slug_texts ++ case_labels ++ conn_labels
  end

  defp fetch_flow_texts(project_id) do
    from(f in Flow,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      select: [f.name, f.description]
    )
    |> Repo.all()
  end

  defp fetch_dialogue_texts(project_id) do
    dialogue_data =
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where:
          f.project_id == ^project_id and
            is_nil(n.deleted_at) and
            is_nil(f.deleted_at) and
            n.type == "dialogue",
        select: n.data
      )
      |> Repo.all()

    Enum.flat_map(dialogue_data, fn data ->
      responses =
        case Map.get(data, "responses") do
          rs when is_list(rs) -> Enum.map(rs, &Map.get(&1, "text"))
          _ -> []
        end

      [
        Map.get(data, "text"),
        Map.get(data, "menu_text"),
        Map.get(data, "stage_directions")
        | responses
      ]
    end)
  end

  defp fetch_slug_texts(project_id) do
    from(n in FlowNode,
      join: f in Flow,
      on: n.flow_id == f.id,
      where:
        f.project_id == ^project_id and
          is_nil(n.deleted_at) and
          is_nil(f.deleted_at) and
          n.type == "slug_line",
      select: [
        fragment("?->>'location'", n.data),
        fragment("?->>'description'", n.data),
        fragment("?->>'sub_location'", n.data)
      ]
    )
    |> Repo.all()
  end

  defp fetch_case_labels(project_id) do
    condition_data =
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where:
          f.project_id == ^project_id and
            is_nil(n.deleted_at) and
            is_nil(f.deleted_at) and
            n.type == "condition",
        select: fragment("?->'cases'", n.data)
      )
      |> Repo.all()

    Enum.flat_map(condition_data, fn
      cases when is_list(cases) -> Enum.map(cases, &Map.get(&1, "label"))
      _ -> []
    end)
  end

  defp fetch_flow_connection_labels(project_id) do
    from(c in FlowConnection,
      join: f in Flow,
      on: c.flow_id == f.id,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      select: c.label
    )
    |> Repo.all()
  end

  # -- Sheet texts: names, descriptions, block labels, text values, table names, gallery captions

  defp collect_sheet_texts(project_id) do
    sheet_texts = fetch_sheet_texts(project_id)
    block_texts = fetch_block_texts(project_id)
    table_col_names = fetch_table_column_names(project_id)
    table_row_names = fetch_table_row_names(project_id)
    gallery_texts = fetch_gallery_texts(project_id)

    sheet_texts ++ block_texts ++ table_col_names ++ table_row_names ++ gallery_texts
  end

  defp fetch_sheet_texts(project_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      select: [s.name, s.description]
    )
    |> Repo.all()
  end

  defp fetch_block_texts(project_id) do
    block_data =
      from(b in Block,
        join: s in Sheet,
        on: b.sheet_id == s.id,
        where: s.project_id == ^project_id and is_nil(b.deleted_at) and is_nil(s.deleted_at),
        select: %{
          type: b.type,
          config: b.config,
          value: b.value
        }
      )
      |> Repo.all()

    Enum.flat_map(block_data, fn b ->
      label = get_in(b.config, ["label"])
      placeholder = get_in(b.config, ["placeholder"])

      option_values =
        case get_in(b.config, ["options"]) do
          opts when is_list(opts) -> Enum.map(opts, &Map.get(&1, "value"))
          _ -> []
        end

      value_content =
        if b.type in ["text", "rich_text"],
          do: [get_in(b.value, ["content"])],
          else: []

      [label, placeholder | option_values ++ value_content]
    end)
  end

  defp fetch_table_column_names(project_id) do
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

  defp fetch_table_row_names(project_id) do
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

  defp fetch_gallery_texts(project_id) do
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

  # -- Scene texts: names, descriptions, layer/zone/pin/annotation/connection labels

  defp collect_scene_texts(project_id) do
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

  # -- Screenplay texts: names, descriptions, element content

  defp collect_screenplay_texts(project_id) do
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

  defp count_words(text) do
    text |> HtmlUtils.strip_html() |> String.split(~r/\s+/, trim: true) |> length()
  end

  # ---------------------------------------------------------------------------
  # Issue Detectors
  # ---------------------------------------------------------------------------

  defp detect_flows_without_entry(project_id, workspace_slug, project_slug) do
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

    flows_without_entry =
      from(f in Flow,
        where:
          f.project_id == ^project_id and
            is_nil(f.deleted_at) and
            f.id not in subquery(flows_with_entry_ids),
        select: %{id: f.id, name: f.name}
      )
      |> Repo.all()

    Enum.map(flows_without_entry, fn flow ->
      %{
        severity: :error,
        message: "Flow \"#{flow.name}\" has no entry node",
        href: "/workspaces/#{workspace_slug}/projects/#{project_slug}/flows/#{flow.id}",
        count: 1
      }
    end)
  end

  defp detect_disconnected_nodes(project_id, workspace_slug, project_slug) do
    # Nodes that have no connections (neither as source nor as target)
    connected_node_ids =
      from(c in FlowConnection,
        join: f in Flow,
        on: c.flow_id == f.id,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        select: c.source_node_id
      )
      |> union_all(
        ^from(c in FlowConnection,
          join: f in Flow,
          on: c.flow_id == f.id,
          where: f.project_id == ^project_id and is_nil(f.deleted_at),
          select: c.target_node_id
        )
      )

    disconnected =
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where:
          f.project_id == ^project_id and
            is_nil(n.deleted_at) and
            is_nil(f.deleted_at) and
            n.id not in subquery(connected_node_ids),
        group_by: [f.id, f.name],
        select: %{flow_id: f.id, flow_name: f.name, count: count(n.id)}
      )
      |> Repo.all()

    Enum.map(disconnected, fn row ->
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
