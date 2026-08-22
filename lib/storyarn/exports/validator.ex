defmodule Storyarn.Exports.Validator do
  @moduledoc """
  Pre-export validation for projects.

  Checks for broken references, orphan nodes, missing translations,
  and other issues that would cause problems in exported files.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Exports.ArtifactValidator
  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Projects.FlowReadModel
  alias Storyarn.Projects.LocalizationReadModel
  alias Storyarn.References
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
    validation_data = load_validation_data(project_id, opts)

    project_id
    |> run_checks_with_data(opts, validation_data)
    |> build_result(project_id)
  end

  @doc """
  Validate and return preloaded data for reuse by DataCollector.

  Returns the result together with every export section already loaded by
  validation: selected flows, selected full sheets, and the project-wide flow
  shortcut map used to resolve cross-flow references.
  """
  def validate_with_data(project_id, %ExportOptions{} = opts) do
    validation_data = load_validation_data(project_id, opts)

    result =
      project_id
      |> run_checks_with_data(opts, validation_data)
      |> build_result(project_id)

    preloaded = %{
      flows: validation_data.flows,
      sheets: validation_data.sheets,
      flow_shortcuts_by_id: Map.new(validation_data.active_flows, &{to_string(&1.id), &1.shortcut})
    }

    {result, preloaded}
  end

  defp build_result(findings, project_id) do
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

  defp run_checks_with_data(project_id, opts, validation_data) do
    effective_flow_result =
      ArtifactValidator.effective_flows(opts.format, validation_data.flows)

    artifact_context = %{
      active_flows: validation_data.active_flows,
      referenceable_variables: validation_data.referenceable_variables,
      stale_node_variable_refs_by_flow: validation_data.stale_node_variable_refs_by_flow,
      stale_node_ids_by_flow: validation_data.stale_node_ids_by_flow,
      effective_flow_result: effective_flow_result
    }

    {artifact_flows, _reachability_findings} = effective_flow_result

    checks = [
      fn ->
        ArtifactValidator.findings(
          project_id,
          opts,
          validation_data.flows,
          validation_data.sheets,
          artifact_context
        )
      end,
      fn ->
        check_canonical_flow_health(
          project_id,
          validation_data.flows,
          artifact_flows,
          artifact_context
        )
      end,
      fn -> check_circular_subflows(artifact_flows) end,
      fn -> check_missing_translations(project_id, opts, artifact_flows) end,
      fn -> check_orphan_sheets(project_id, validation_data.sheets) end
    ]

    Enum.flat_map(checks, fn check -> check.() end)
  end

  # =============================================================================
  # Data loading
  # =============================================================================

  defp load_validation_data(project_id, opts) do
    flows = load_flows_data(project_id, opts)
    sheets = load_sheets(project_id, opts)
    active_flows = load_active_flows(project_id, opts, flows)

    referenceable_variables =
      if flows == [], do: [], else: FlowReadModel.list_referenceable_variables(project_id)

    stale_node_variable_refs_by_flow =
      flows
      |> Enum.map(& &1.id)
      |> References.list_stale_node_variable_refs_by_flow()

    stale_node_ids_by_flow =
      Map.new(stale_node_variable_refs_by_flow, fn {flow_id, refs_by_node} ->
        {flow_id, refs_by_node |> Map.keys() |> MapSet.new()}
      end)

    %{
      flows: flows,
      sheets: sheets,
      active_flows: active_flows,
      referenceable_variables: referenceable_variables,
      stale_node_variable_refs_by_flow: stale_node_variable_refs_by_flow,
      stale_node_ids_by_flow: stale_node_ids_by_flow
    }
  end

  defp load_active_flows(_project_id, %{include_flows: true, flow_ids: :all}, flows), do: flows

  defp load_active_flows(project_id, _opts, flows) when flows != [], do: FlowReadModel.list_flows(project_id)

  defp load_active_flows(_project_id, _opts, _flows), do: []

  defp load_flows_data(_project_id, %ExportOptions{include_flows: false}), do: []

  defp load_flows_data(project_id, %ExportOptions{flow_ids: :all}) do
    FlowReadModel.list_flows_for_export(project_id)
  end

  defp load_flows_data(_project_id, %ExportOptions{flow_ids: []}), do: []

  defp load_flows_data(project_id, %ExportOptions{flow_ids: flow_ids}) do
    FlowReadModel.list_flows_for_export(project_id, filter_ids: flow_ids)
  end

  defp load_sheets(_project_id, %ExportOptions{include_sheets: false}), do: []

  defp load_sheets(project_id, %ExportOptions{sheet_ids: :all}) do
    Sheets.list_sheets_for_export(project_id)
  end

  defp load_sheets(_project_id, %ExportOptions{sheet_ids: []}), do: []

  defp load_sheets(project_id, %ExportOptions{sheet_ids: sheet_ids}) do
    Sheets.list_sheets_for_export(project_id, filter_ids: sheet_ids)
  end

  # Export consumes canonical health as a boundary, never as a second dashboard.
  # Only health that invalidates every target artifact crosses that boundary;
  # editorial quality is reduced to summaries that link back to the dashboard,
  # where the individual authoring findings already live.
  defp check_canonical_flow_health(_project_id, [], _artifact_flows, _context), do: []

  defp check_canonical_flow_health(project_id, flows, artifact_flows, context) do
    effective_nodes =
      Map.new(artifact_flows, fn flow ->
        {flow.id, MapSet.new(flow.nodes || [], & &1.id)}
      end)

    health_findings =
      project_id
      |> FlowReadModel.list_export_health_findings(flows, context)
      |> Enum.filter(&effective_health_finding?(&1, effective_nodes))

    artifact_findings =
      health_findings
      |> Enum.filter(&(&1.code in @artifact_health_codes))
      |> Enum.map(&artifact_health_finding/1)

    artifact_findings ++ aggregate_editorial_findings(health_findings)
  end

  defp effective_health_finding?(%{entity_id: nil}, _effective_nodes), do: true

  defp effective_health_finding?(finding, effective_nodes) do
    effective_nodes
    |> Map.get(finding.flow_id, MapSet.new())
    |> MapSet.member?(finding.entity_id)
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

  defp check_missing_translations(_project_id, %ExportOptions{include_localization: false}, _artifact_flows), do: []

  defp check_missing_translations(project_id, opts, artifact_flows) do
    languages =
      project_id
      |> LocalizationReadModel.list_target_locale_codes()
      |> selected_locales(opts.languages)

    if languages == [] do
      []
    else
      do_check_missing_translations(project_id, languages, opts, artifact_flows)
    end
  end

  defp selected_locales(locales, :all), do: locales
  defp selected_locales(locales, selected), do: Enum.filter(locales, &(&1 in selected))

  defp do_check_missing_translations(project_id, languages, opts, artifact_flows) do
    flow_node_ids =
      for flow <- artifact_flows,
          node <- flow.nodes,
          do: node.id

    readiness =
      LocalizationReadModel.export_readiness_by_locale(project_id, languages, opts, flow_node_ids)

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
    referenced_sheet_ids = FlowReadModel.list_speaker_sheet_ids(project_id)

    # Variable references belong to the Project-wide integrity model. Resolve
    # them from the already-loaded active Sheet blocks so Flow autonomy cannot
    # accidentally hide references authored by Scenes.
    block_id_to_sheet_id =
      for sheet <- sheets, block <- sheet.blocks, into: %{} do
        {block.id, sheet.id}
      end

    block_sheet_ids =
      block_id_to_sheet_id
      |> Map.keys()
      |> References.referenced_block_ids()
      |> MapSet.new(&Map.fetch!(block_id_to_sheet_id, &1))

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
