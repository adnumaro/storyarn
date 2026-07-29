defmodule Storyarn.Exports.Validator do
  @moduledoc """
  Pre-export validation for projects.

  Checks for broken references, orphan nodes, missing translations,
  and other issues that would cause problems in exported files.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Exports.ArtifactValidator
  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Sheets

  @artifact_health_codes [
    :invalid_output_pins,
    :missing_entry,
    :multiple_entries
  ]
  @editorial_health_rules [
    missing_dialogue_text: :empty_dialogue,
    missing_dialogue_speaker: :missing_speakers
  ]

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

  Takes a built `%ExportOptions{}`. There is no default: the previous one
  guessed the now-deleted native JSON format, so a caller that never said which
  format it was exporting as got validated against a different one.
  """
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
      fn -> ArtifactValidator.findings(project_id, opts, flows_data, sheets) end,
      fn -> check_canonical_flow_health(project_id, flows_data) end,
      fn -> check_circular_subflows(flows_data) end,
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
      fn -> ArtifactValidator.findings(project_id, opts, flows_data, sheets) end,
      fn -> check_canonical_flow_health(project_id, flows_data) end,
      fn -> check_circular_subflows(flows_data) end,
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

  # Export consumes canonical health as a boundary, never as a second dashboard.
  # Only health that invalidates every target artifact crosses that boundary;
  # editorial quality is reduced to summaries that link back to the dashboard,
  # where the individual authoring findings already live.
  defp check_canonical_flow_health(_project_id, []), do: []

  defp check_canonical_flow_health(project_id, flows) do
    selected_flow_ids = MapSet.new(flows, & &1.id)

    health_findings =
      project_id
      |> Flows.list_dashboard_health_findings()
      |> Enum.filter(&MapSet.member?(selected_flow_ids, &1.flow_id))

    artifact_findings =
      health_findings
      |> Enum.filter(&(&1.code in @artifact_health_codes))
      |> Enum.map(&artifact_health_finding/1)

    artifact_findings ++ aggregate_editorial_findings(health_findings)
  end

  defp artifact_health_finding(%{code: :missing_entry, flow_id: flow_id, details: details}) do
    flow_name = Map.fetch!(details, :flow_name)

    %{
      level: :error,
      rule: :missing_entry,
      message: dgettext("projects", "Flow \"%{name}\" has no Entry node", name: flow_name),
      flow_id: flow_id,
      flow_name: flow_name
    }
  end

  defp artifact_health_finding(%{code: :multiple_entries, flow_id: flow_id, details: details}) do
    flow_name = Map.fetch!(details, :flow_name)
    count = Map.fetch!(details, :count)

    %{
      level: :error,
      rule: :multiple_entries,
      count: count,
      message:
        dgettext(
          "projects",
          "Flow \"%{name}\" has %{count} Entry nodes; export can preserve only one",
          name: flow_name,
          count: count
        ),
      flow_id: flow_id,
      flow_name: flow_name
    }
  end

  defp artifact_health_finding(%{
         code: :invalid_output_pins,
         flow_id: flow_id,
         entity_type: entity_type,
         entity_id: entity_id,
         details: details
       }) do
    flow_name = Map.fetch!(details, :flow_name)
    entity_label = Map.get(details, :entity_label, entity_type)

    %{
      level: :error,
      rule: :invalid_output_pins,
      message:
        dgettext(
          "projects",
          ~s("%{node}" in flow "%{flow}" has connections from outputs the exporter cannot preserve),
          node: entity_label,
          flow: flow_name
        ),
      flow_id: flow_id,
      flow_name: flow_name,
      entity_type: entity_type,
      entity_id: entity_id,
      entity_label: entity_label,
      details: %{pins: Map.get(details, :pins, [])}
    }
  end

  defp aggregate_editorial_findings(health_findings) do
    Enum.flat_map(@editorial_health_rules, fn {health_code, export_rule} ->
      count = Enum.count(health_findings, &(&1.code == health_code))
      aggregate_editorial_finding(export_rule, count)
    end)
  end

  defp aggregate_editorial_finding(_rule, 0), do: []

  defp aggregate_editorial_finding(:empty_dialogue, count) do
    [
      %{
        level: :warning,
        rule: :empty_dialogue,
        count: count,
        dashboard: :flows,
        message:
          dngettext(
            "projects",
            "One dialogue has no text",
            "%{count} dialogues have no text",
            count,
            count: count
          )
      }
    ]
  end

  defp aggregate_editorial_finding(:missing_speakers, count) do
    [
      %{
        level: :warning,
        rule: :missing_speakers,
        count: count,
        dashboard: :flows,
        message:
          dngettext(
            "projects",
            "One dialogue has no speaker assigned",
            "%{count} dialogues have no speaker assigned",
            count,
            count: count
          )
      }
    ]
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
  # Check: missing_translations (warning)
  # =============================================================================

  defp check_missing_translations(_project_id, %ExportOptions{include_localization: false}), do: []

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
end
