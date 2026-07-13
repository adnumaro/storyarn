defmodule Storyarn.Exports.Validator do
  @moduledoc """
  Pre-export validation for projects.

  Checks for broken references, orphan nodes, missing translations,
  and other issues that would cause problems in exported files.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Flows
  alias Storyarn.Flows.NodeConnectionRules
  alias Storyarn.Localization
  alias Storyarn.Sheets

  defmodule ValidationResult do
    @moduledoc "Result of a project validation pass."

    @type t :: %__MODULE__{
            status: :passed | :warnings | :errors,
            errors: [map()],
            warnings: [map()],
            info: [map()],
            statistics: map()
          }

    defstruct status: :passed,
              errors: [],
              warnings: [],
              info: [],
              statistics: %{}
  end

  @doc """
  Validate a project for export.

  Returns a `%ValidationResult{}` struct with errors, warnings, and info findings.
  """
  def validate_project(project_id, opts \\ %{})

  def validate_project(project_id, %ExportOptions{} = opts) do
    findings = run_all_checks(project_id, opts)

    errors = Enum.filter(findings, &(&1.level == :error))
    warnings = Enum.filter(findings, &(&1.level == :warning))
    info = Enum.filter(findings, &(&1.level == :info))

    status =
      cond do
        errors != [] -> :errors
        warnings != [] -> :warnings
        true -> :passed
      end

    %ValidationResult{
      status: status,
      errors: errors,
      warnings: warnings,
      info: info,
      statistics: %{
        project_id: project_id,
        total_findings: length(findings),
        error_count: length(errors),
        warning_count: length(warnings),
        info_count: length(info)
      }
    }
  end

  def validate_project(project_id, _opts) do
    validate_project(project_id, %ExportOptions{format: :storyarn})
  end

  @doc """
  Validate and return preloaded data for reuse by DataCollector.

  Returns `{%ValidationResult{}, %{flows: flows_data}}` so that the caller
  can thread the already-loaded flows into the data collection step.
  """
  def validate_with_data(project_id, %ExportOptions{} = opts) do
    flows_data = load_flows_data(project_id, opts)
    sheets = load_sheets(project_id, opts)

    findings = run_checks_with_data(project_id, opts, flows_data, sheets)

    errors = Enum.filter(findings, &(&1.level == :error))
    warnings = Enum.filter(findings, &(&1.level == :warning))
    info = Enum.filter(findings, &(&1.level == :info))

    status =
      cond do
        errors != [] -> :errors
        warnings != [] -> :warnings
        true -> :passed
      end

    result = %ValidationResult{
      status: status,
      errors: errors,
      warnings: warnings,
      info: info,
      statistics: %{
        project_id: project_id,
        total_findings: length(findings),
        error_count: length(errors),
        warning_count: length(warnings),
        info_count: length(info)
      }
    }

    {result, %{flows: flows_data}}
  end

  defp run_checks_with_data(project_id, opts, flows_data, sheets) do
    checks = [
      fn -> check_missing_entry(flows_data) end,
      fn -> check_orphan_nodes(flows_data) end,
      fn -> check_unreachable_nodes(flows_data) end,
      fn -> check_empty_dialogue(flows_data) end,
      fn -> check_missing_speakers(flows_data) end,
      fn -> check_circular_subflows(flows_data) end,
      fn -> check_broken_references(project_id, flows_data) end,
      fn -> check_missing_translations(project_id, opts) end,
      fn -> check_orphan_sheets(project_id, sheets) end
    ]

    Enum.flat_map(checks, fn check -> check.() end)
  end

  # =============================================================================
  # Check runner
  # =============================================================================

  defp run_all_checks(project_id, opts) do
    # Load data needed for multiple checks
    flows_data = load_flows_data(project_id, opts)
    sheets = load_sheets(project_id, opts)

    checks = [
      fn -> check_missing_entry(flows_data) end,
      fn -> check_orphan_nodes(flows_data) end,
      fn -> check_unreachable_nodes(flows_data) end,
      fn -> check_empty_dialogue(flows_data) end,
      fn -> check_missing_speakers(flows_data) end,
      fn -> check_circular_subflows(flows_data) end,
      fn -> check_broken_references(project_id, flows_data) end,
      fn -> check_missing_translations(project_id, opts) end,
      fn -> check_orphan_sheets(project_id, sheets) end
    ]

    Enum.flat_map(checks, fn check -> check.() end)
  end

  # =============================================================================
  # Data loading
  # =============================================================================

  defp load_flows_data(_project_id, %ExportOptions{include_flows: false}), do: []

  defp load_flows_data(project_id, %ExportOptions{flow_ids: :all}) do
    Flows.list_flows_for_export(project_id)
  end

  defp load_flows_data(_project_id, %ExportOptions{flow_ids: []}), do: []

  defp load_flows_data(project_id, %ExportOptions{flow_ids: flow_ids}) do
    Flows.list_flows_for_export(project_id, filter_ids: flow_ids)
  end

  defp load_sheets(_project_id, %ExportOptions{include_sheets: false}), do: []

  defp load_sheets(project_id, %ExportOptions{sheet_ids: :all}) do
    Sheets.list_sheets_brief(project_id)
  end

  defp load_sheets(_project_id, %ExportOptions{sheet_ids: []}), do: []

  defp load_sheets(project_id, %ExportOptions{sheet_ids: sheet_ids}) do
    Sheets.list_sheets_brief(project_id, filter_ids: sheet_ids)
  end

  # =============================================================================
  # Check: missing_entry (error)
  # =============================================================================

  defp check_missing_entry(flows) do
    flows
    |> Enum.reject(fn flow ->
      Enum.any?(flow.nodes, &(&1.type == "entry"))
    end)
    |> Enum.map(fn flow ->
      %{
        level: :error,
        rule: :missing_entry,
        message: dgettext("projects", "Flow \"%{name}\" has no Entry node", name: flow.name),
        flow_id: flow.id,
        flow_name: flow.name
      }
    end)
  end

  # =============================================================================
  # Check: orphan_nodes (warning) — nodes with no connections at all
  # =============================================================================

  defp check_orphan_nodes(flows) do
    Enum.flat_map(flows, fn flow ->
      connected_ids = connected_node_ids(flow.connections)

      flow.nodes
      |> Enum.reject(&(orphan_check_skipped?(&1.type) or MapSet.member?(connected_ids, &1.id)))
      |> Enum.map(fn node ->
        %{
          level: :warning,
          rule: :orphan_nodes,
          message:
            dgettext(
              "projects",
              "%{type} node (id: %{node_id}) in flow \"%{flow_name}\" has no connections",
              type: node.type,
              node_id: node.id,
              flow_name: flow.name
            ),
          flow_id: flow.id,
          flow_name: flow.name,
          node_id: node.id,
          node_type: node.type
        }
      end)
    end)
  end

  # =============================================================================
  # Check: unreachable_nodes (warning) — not reachable from Entry
  # =============================================================================

  defp check_unreachable_nodes(flows) do
    Enum.flat_map(flows, &find_unreachable_in_flow/1)
  end

  defp find_unreachable_in_flow(flow) do
    entry_nodes = Enum.filter(flow.nodes, &(&1.type == "entry"))

    if entry_nodes == [] do
      []
    else
      reachable = reachable_from_entries(entry_nodes, flow.connections)
      all_node_ids = MapSet.new(flow.nodes, & &1.id)
      unreachable_ids = MapSet.difference(all_node_ids, reachable)

      flow.nodes
      |> Enum.filter(&(MapSet.member?(unreachable_ids, &1.id) and NodeConnectionRules.can_be_unreachable?(&1.type)))
      |> Enum.map(fn node ->
        %{
          level: :warning,
          rule: :unreachable_nodes,
          message:
            dgettext(
              "projects",
              "%{type} node (id: %{node_id}) in flow \"%{flow_name}\" is not reachable from Entry",
              type: node.type,
              node_id: node.id,
              flow_name: flow.name
            ),
          flow_id: flow.id,
          flow_name: flow.name,
          node_id: node.id,
          node_type: node.type
        }
      end)
    end
  end

  defp orphan_check_skipped?(type), do: type in ["entry", "exit"] or NodeConnectionRules.connection_optional_type?(type)

  # =============================================================================
  # Check: empty_dialogue (warning)
  # =============================================================================

  defp check_empty_dialogue(flows) do
    Enum.flat_map(flows, fn flow ->
      flow.nodes
      |> Enum.filter(fn node ->
        node.type == "dialogue" and
          (get_in(node.data, ["text"]) || "") |> strip_html() |> String.trim() == ""
      end)
      |> Enum.map(fn node ->
        %{
          level: :warning,
          rule: :empty_dialogue,
          message:
            dgettext(
              "projects",
              "Dialogue node (id: %{node_id}) in flow \"%{flow_name}\" has no text",
              node_id: node.id,
              flow_name: flow.name
            ),
          flow_id: flow.id,
          flow_name: flow.name,
          node_id: node.id
        }
      end)
    end)
  end

  # =============================================================================
  # Check: missing_speakers (warning)
  # =============================================================================

  defp check_missing_speakers(flows) do
    Enum.flat_map(flows, fn flow ->
      flow.nodes
      |> Enum.filter(fn node ->
        node.type == "dialogue" and
          node.data |> get_in(["speaker_sheet_id"]) |> nil_or_empty?()
      end)
      |> Enum.map(fn node ->
        %{
          level: :warning,
          rule: :missing_speakers,
          message:
            dgettext(
              "projects",
              "Dialogue node (id: %{node_id}) in flow \"%{flow_name}\" has no speaker assigned",
              node_id: node.id,
              flow_name: flow.name
            ),
          flow_id: flow.id,
          flow_name: flow.name,
          node_id: node.id
        }
      end)
    end)
  end

  # =============================================================================
  # Check: circular_subflows (warning) — subflow A → B → A cycles
  # =============================================================================

  defp check_circular_subflows(flows) do
    # Build subflow reference graph: flow_id → [target_flow_ids]
    flow_map = Map.new(flows, &{&1.id, &1})

    ref_graph =
      Enum.reduce(flows, %{}, fn flow, acc ->
        targets =
          flow.nodes
          |> Enum.filter(&(&1.type == "subflow"))
          |> Enum.map(&get_in(&1.data, ["referenced_flow_id"]))
          |> Enum.reject(&is_nil/1)

        if targets == [], do: acc, else: Map.put(acc, flow.id, targets)
      end)

    # Find cycles using DFS
    ref_graph
    |> Map.keys()
    |> Enum.filter(&has_cycle?(&1, ref_graph, MapSet.new()))
    |> Enum.uniq()
    |> Enum.map(fn flow_id ->
      flow = Map.get(flow_map, flow_id)
      flow_name = if flow, do: flow.name, else: "unknown"

      %{
        level: :warning,
        rule: :circular_subflows,
        message:
          dgettext(
            "projects",
            "Flow \"%{name}\" is part of a circular subflow reference chain",
            name: flow_name
          ),
        flow_id: flow_id,
        flow_name: flow_name
      }
    end)
  end

  # =============================================================================
  # Check: broken_references (error)
  # =============================================================================

  defp check_broken_references(_project_id, flows) do
    # Check jump nodes referencing non-existent hubs
    jump_findings = check_broken_jump_refs(flows)

    # Check subflow nodes referencing deleted/non-existent flows
    subflow_findings = check_broken_subflow_refs(flows)

    jump_findings ++ subflow_findings
  end

  defp check_broken_jump_refs(flows) do
    Enum.flat_map(flows, fn flow ->
      hub_ids =
        flow.nodes
        |> Enum.filter(&(&1.type == "hub"))
        |> MapSet.new(&get_in(&1.data, ["hub_id"]))

      flow.nodes
      |> Enum.filter(fn node ->
        node.type == "jump" and has_broken_hub_ref?(node, hub_ids)
      end)
      |> Enum.map(fn node ->
        target = get_in(node.data, ["target_hub_id"])

        %{
          level: :error,
          rule: :broken_references,
          message:
            dgettext(
              "projects",
              ~s|Jump node (id: %{node_id}) in flow "%{flow_name}" references non-existent hub "%{target}"|,
              node_id: node.id,
              flow_name: flow.name,
              target: target
            ),
          flow_id: flow.id,
          flow_name: flow.name,
          node_id: node.id,
          ref_type: :hub,
          ref_value: target
        }
      end)
    end)
  end

  defp check_broken_subflow_refs(flows) do
    valid_flow_ids = MapSet.new(flows, & &1.id)

    Enum.flat_map(flows, fn flow ->
      flow.nodes
      |> Enum.filter(fn node ->
        node.type == "subflow" and has_broken_ref?(node, "referenced_flow_id", valid_flow_ids)
      end)
      |> Enum.map(fn node ->
        %{
          level: :error,
          rule: :broken_references,
          message:
            dgettext(
              "projects",
              "Subflow node (id: %{node_id}) in flow \"%{flow_name}\" references non-existent flow",
              node_id: node.id,
              flow_name: flow.name
            ),
          flow_id: flow.id,
          flow_name: flow.name,
          node_id: node.id,
          ref_type: :flow
        }
      end)
    end)
  end

  # =============================================================================
  # Check: missing_translations (warning)
  # =============================================================================

  defp check_missing_translations(_project_id, %ExportOptions{include_localization: false}), do: []
  defp check_missing_translations(_project_id, %ExportOptions{format: :storyarn}), do: []

  defp check_missing_translations(project_id, opts) do
    languages =
      project_id
      |> Localization.list_target_locale_codes()
      |> selected_locales(opts.languages)

    if languages == [] do
      []
    else
      do_check_missing_translations(project_id, languages, opts)
    end
  end

  defp selected_locales(locales, :all), do: locales
  defp selected_locales(locales, selected), do: Enum.filter(locales, &(&1 in selected))

  defp do_check_missing_translations(project_id, languages, opts) do
    readiness = Localization.export_readiness_by_locale(project_id, languages, opts)

    Enum.flat_map(languages, fn locale ->
      counts = Map.get(readiness, locale, %{total: 0, preview_ready: 0, release_ready: 0})
      localization_findings(locale, counts, opts.localization_policy)
    end)
  end

  defp localization_findings(locale, counts, :release) do
    excluded = counts.total - counts.release_ready

    if excluded == 0 do
      []
    else
      [
        %{
          level: :warning,
          rule: :missing_translations,
          message:
            dgettext(
              "projects",
              "%{excluded} of %{total} strings are not release-ready for locale \"%{locale}\"",
              excluded: excluded,
              total: counts.total,
              locale: locale
            ),
          locale: locale,
          pending_count: excluded,
          excluded_count: excluded,
          ready_count: counts.release_ready,
          total_count: counts.total,
          localization_policy: :release
        }
      ]
    end
  end

  defp localization_findings(locale, counts, :preview) do
    missing = counts.total - counts.preview_ready
    non_release = counts.preview_ready - counts.release_ready

    missing_findings =
      if missing == 0 do
        []
      else
        [
          %{
            level: :warning,
            rule: :missing_translations,
            message:
              dgettext(
                "projects",
                "%{missing} of %{total} strings have no preview translation for locale \"%{locale}\"",
                missing: missing,
                total: counts.total,
                locale: locale
              ),
            locale: locale,
            pending_count: missing,
            excluded_count: missing,
            ready_count: counts.preview_ready,
            total_count: counts.total,
            localization_policy: :preview
          }
        ]
      end

    preview_findings =
      if non_release == 0 do
        []
      else
        [
          %{
            level: :info,
            rule: :preview_localization,
            message:
              dgettext(
                "projects",
                "Preview export includes %{count} non-final or outdated strings for locale \"%{locale}\"",
                count: non_release,
                locale: locale
              ),
            locale: locale,
            non_release_count: non_release,
            localization_policy: :preview
          }
        ]
      end

    missing_findings ++ preview_findings
  end

  # =============================================================================
  # Check: orphan_sheets (info)
  # =============================================================================

  defp check_orphan_sheets(project_id, sheets) do
    # Find sheets referenced by flow nodes (speaker_sheet_id)
    referenced_sheet_ids = Flows.list_speaker_sheet_ids(project_id)

    # Also check variable_references — blocks referenced by flow nodes
    block_sheet_ids = Flows.list_variable_referenced_sheet_ids(project_id)

    all_referenced = MapSet.union(referenced_sheet_ids, block_sheet_ids)

    # Also check scene pin/zone sheet references
    pin_sheet_ids = Sheets.list_pin_referenced_sheet_ids(project_id)

    all_referenced = MapSet.union(all_referenced, pin_sheet_ids)

    sheets
    |> Enum.reject(&(MapSet.member?(all_referenced, &1.id) or &1.shortcut == nil))
    |> Enum.map(fn sheet ->
      %{
        level: :info,
        rule: :orphan_sheets,
        message:
          dgettext(
            "projects",
            "Sheet \"%{name}\" has no references from flows or scenes",
            name: sheet.name
          ),
        sheet_id: sheet.id,
        sheet_name: sheet.name
      }
    end)
  end

  # =============================================================================
  # Graph helpers
  # =============================================================================

  defp connected_node_ids(connections) do
    Enum.reduce(connections, MapSet.new(), fn conn, acc ->
      acc
      |> MapSet.put(conn.source_node_id)
      |> MapSet.put(conn.target_node_id)
    end)
  end

  defp reachable_from_entries(entry_nodes, connections) do
    # Build adjacency map: source_node_id → [target_node_ids]
    adj =
      Enum.reduce(connections, %{}, fn conn, acc ->
        Map.update(acc, conn.source_node_id, [conn.target_node_id], &[conn.target_node_id | &1])
      end)

    # BFS from all entry nodes
    entry_ids = Enum.map(entry_nodes, & &1.id)
    bfs(entry_ids, adj, MapSet.new(entry_ids))
  end

  defp bfs([], _adj, visited), do: visited

  defp bfs(queue, adj, visited) do
    next_queue =
      queue
      |> Enum.flat_map(fn node_id ->
        adj
        |> Map.get(node_id, [])
        |> Enum.reject(&MapSet.member?(visited, &1))
      end)
      |> Enum.uniq()

    new_visited = Enum.reduce(next_queue, visited, &MapSet.put(&2, &1))
    bfs(next_queue, adj, new_visited)
  end

  defp has_cycle?(start_id, graph, visited) do
    if MapSet.member?(visited, start_id) do
      true
    else
      visited = MapSet.put(visited, start_id)

      graph
      |> Map.get(start_id, [])
      |> Enum.any?(&has_cycle?(&1, graph, visited))
    end
  end

  defp has_broken_hub_ref?(node, hub_ids) do
    target = get_in(node.data, ["target_hub_id"])
    target != nil and target != "" and not MapSet.member?(hub_ids, target)
  end

  defp has_broken_ref?(node, field, valid_ids) do
    target = get_in(node.data, [field])
    target != nil and not MapSet.member?(valid_ids, target)
  end

  defp strip_html(text), do: Storyarn.Shared.HtmlUtils.strip_html(text)

  defp nil_or_empty?(nil), do: true
  defp nil_or_empty?(""), do: true
  defp nil_or_empty?(_), do: false
end
