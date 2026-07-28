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
  alias Storyarn.Shared.StringUtils
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
      fn -> check_flow_health(flows_data) end,
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
      fn -> ArtifactValidator.findings(project_id, opts, flows_data, sheets) end,
      fn -> check_flow_health(flows_data) end,
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
  # Check: flow health (structural) — routed through the health engine
  # =============================================================================
  #
  # This used to be three hand-rolled checks — missing_entry, orphan_nodes and
  # unreachable_nodes — with their own raw-connection BFS. They disagreed with
  # the health engine on real flows, always in the direction of noise:
  #
  #   * the orphan check skipped `entry` and `exit`, so a flow with no
  #     connections at all reported zero orphans;
  #   * the BFS walked connection rows, so it never resolved a jump -> hub
  #     virtual edge and called everything behind a jump unreachable;
  #   * it counted connections sitting on pins the node no longer has as real
  #     wiring, so a stale response pin looked connected.
  #
  # There is one flow-health vocabulary now and the export path reads it rather
  # than reimplementing it. `analyze_loaded_flow_structure/1` is the structural
  # half; it re-uses the flows the validator already preloaded.

  # The rules whose names predate the consolidation. Consumers match on these
  # atoms, so the health code is renamed rather than the finding re-labelled.
  @export_rule_by_health_code %{
    missing_entry: :missing_entry,
    isolated_node: :orphan_nodes,
    unreachable_node: :unreachable_nodes
  }

  # `check_broken_references/2` already reports these, at :error. Surfacing them
  # again at :warning would report one broken reference twice.
  #
  # ONLY the `stale_*` half. The split is: a reference that is SET but dangling
  # is the legacy check's ("references non-existent hub/flow"); a reference that
  # was never configured is health's, because the legacy check cannot see it —
  # `has_broken_hub_ref?/2` requires `target != nil and target != ""` and
  # `has_broken_ref?/3` requires `target != nil`. Since an unconfigured jump
  # stores `""` (`Nodes.Jump.Node.default_data/0`) and an unconfigured subflow
  # stores `nil` (`Nodes.Subflow.Node.default_data/0`), filtering `missing_*` here
  # meant an unconfigured node produced NO export finding at all, from either
  # side. Nothing double-reports: the two predicates skip exactly the blanks
  # health claims.
  @health_codes_reported_elsewhere [
    :stale_jump_target,
    :stale_subflow_reference
  ]

  defp check_flow_health(flows) do
    Enum.flat_map(flows, fn flow ->
      flow
      |> Flows.analyze_loaded_flow_structure()
      |> Map.fetch!(:findings)
      |> Enum.reject(&(&1.code in @health_codes_reported_elsewhere))
      |> Enum.map(&health_finding(&1, flow))
    end)
  end

  # Only `missing_entry` blocks an export, exactly as before. Every code the
  # consolidation newly surfaces lands at :warning: whether any of them should
  # block is a product decision, and making it here would stop exports that
  # succeed today.
  defp health_finding(%{code: :missing_entry} = finding, flow) do
    finding
    |> base_health_finding(flow)
    |> Map.put(:level, :error)
  end

  defp health_finding(finding, flow), do: base_health_finding(finding, flow)

  defp base_health_finding(finding, flow) do
    maybe_put_node(
      finding,
      %{
        level: :warning,
        rule: Map.get(@export_rule_by_health_code, finding.code, finding.code),
        message: health_message(finding, flow),
        flow_id: flow.id,
        flow_name: flow.name
      },
      flow
    )
  end

  defp maybe_put_node(%{entity_id: nil}, export_finding, _flow), do: export_finding

  defp maybe_put_node(finding, export_finding, flow) do
    node = Enum.find(flow.nodes, &(&1.id == finding.entity_id))

    export_finding
    |> Map.put(:node_id, finding.entity_id)
    |> Map.put(:node_type, finding.entity_type)
    |> Map.put(:entity_id, finding.entity_id)
    |> Map.put(:entity_type, finding.entity_type)
    |> Map.put(:entity_label, if(node, do: Flows.node_label(node), else: Flows.node_label(finding)))
  end

  # =============================================================================
  # Check: empty_dialogue / missing_speakers (warning)
  # =============================================================================
  #
  # These two are the EDITORIAL half of flow health (`HealthChecker`'s
  # `missing_dialogue_text` and `missing_dialogue_speaker`) and the predicates
  # below are already identical to the checker's. They stay here only because
  # `Flows.analyze_loaded_flow_structure/1` is the structural half: no facade
  # function composes both halves for an already-loaded flow, and reaching into
  # `StructuralAnalysis`/`HealthChecker` directly would break the context facade.
  # They do NOT diverge from health today — unlike the three structural rules
  # that were removed.
  #
  # To fold them into `check_flow_health/1`, `Flows` needs a composed reading for
  # a loaded flow. **Do not write the obvious version.** `Topology.from_loaded/1`
  # resolves subflow/exit data but does NOT apply `Flows.add_health_flags/3`, and
  # the editorial checks read `has_type_warnings` / `has_stale_refs` straight off
  # a node's `data`. Measured on a flow with a live type mismatch:
  #
  #     from_loaded |> StructuralAnalysis.findings()
  #       => [:incomplete_instruction_assignment, :isolated_node]
  #     the editor path
  #       => [:incomplete_instruction_assignment, :isolated_node, :variable_type_mismatch]
  #
  # So the naive helper would buy the two codes below and silently lose
  # `variable_type_mismatch` — and `stale_variable_reference` with it, by
  # construction, since it rides the same flag. A correct helper has to do the
  # sweep's two loads (`References.list_stale_node_ids/1` plus the project
  # variable set) and pass them through `add_health_flags/3` first.

  defp check_empty_dialogue(flows) do
    count =
      Enum.sum(
        for flow <- flows do
          Enum.count(flow.nodes, fn node ->
            node.type == "dialogue" and
              (get_in(node.data, ["text"]) || "") |> strip_html() |> String.trim() == ""
          end)
        end
      )

    aggregate_editorial_finding(:empty_dialogue, count)
  end

  # =============================================================================
  # Check: missing_speakers (warning)
  # =============================================================================

  defp check_missing_speakers(flows) do
    count =
      Enum.sum(
        for flow <- flows do
          Enum.count(flow.nodes, fn node ->
            node.type == "dialogue" and
              node.data |> get_in(["speaker_sheet_id"]) |> StringUtils.blank?()
          end)
        end
      )

    aggregate_editorial_finding(:missing_speakers, count)
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
  # Check: broken_references (error)
  # =============================================================================

  defp check_broken_references(project_id, flows) do
    # Check jump nodes referencing non-existent hubs
    jump_findings = check_broken_jump_refs(flows)

    # Check subflow nodes referencing deleted/non-existent flows
    valid_flow_ids = project_id |> Flows.list_flows() |> MapSet.new(& &1.id)
    subflow_findings = check_broken_subflow_refs(flows, valid_flow_ids)

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
              ~s|"%{node}" in flow "%{flow_name}" references non-existent hub "%{target}"|,
              node: Flows.node_label(node),
              flow_name: flow.name,
              target: target
            ),
          flow_id: flow.id,
          flow_name: flow.name,
          node_id: node.id,
          node_type: node.type,
          entity_id: node.id,
          entity_type: node.type,
          entity_label: Flows.node_label(node),
          ref_type: :hub,
          ref_value: target
        }
      end)
    end)
  end

  defp check_broken_subflow_refs(flows, valid_flow_ids) do
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
              ~s("%{node}" in flow "%{flow_name}" references non-existent flow),
              node: Flows.node_label(node),
              flow_name: flow.name
            ),
          flow_id: flow.id,
          flow_name: flow.name,
          node_id: node.id,
          node_type: node.type,
          entity_id: node.id,
          entity_type: node.type,
          entity_label: Flows.node_label(node),
          ref_type: :flow
        }
      end)
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

  defp has_broken_hub_ref?(node, hub_ids) do
    target = get_in(node.data, ["target_hub_id"])
    target != nil and target != "" and not MapSet.member?(hub_ids, target)
  end

  defp has_broken_ref?(node, field, valid_ids) do
    target = get_in(node.data, [field])
    target != nil and not MapSet.member?(valid_ids, target)
  end

  defp strip_html(text), do: Storyarn.Shared.HtmlUtils.strip_html(text)

  # =============================================================================
  # Health finding messages
  # =============================================================================
  #
  # Rebuilt from the finding's own code, entity and flow name. The three rules
  # that predate the consolidation keep their exact original strings so existing
  # translations still match.

  defp health_message(%{code: :missing_entry}, flow) do
    dgettext("projects", "Flow \"%{name}\" has no Entry node", name: flow.name)
  end

  defp health_message(%{code: :multiple_entries}, flow) do
    dgettext("projects", "Flow \"%{name}\" has more than one Entry node", name: flow.name)
  end

  defp health_message(%{code: :isolated_node} = finding, flow) do
    dgettext(
      "projects",
      ~s("%{node}" in flow "%{flow_name}" has no connections),
      node: health_node_label(finding, flow),
      flow_name: flow.name
    )
  end

  defp health_message(%{code: :unreachable_node} = finding, flow) do
    dgettext(
      "projects",
      ~s("%{node}" in flow "%{flow_name}" is not reachable from Entry),
      node: health_node_label(finding, flow),
      flow_name: flow.name
    )
  end

  defp health_message(%{code: :no_outgoing_connection} = finding, flow) do
    dgettext(
      "projects",
      ~s("%{node}" in flow "%{flow_name}" has no outgoing connection),
      node: health_node_label(finding, flow),
      flow_name: flow.name
    )
  end

  defp health_message(%{code: :missing_output_connections} = finding, flow) do
    dgettext(
      "projects",
      ~s("%{node}" in flow "%{flow_name}" leaves one or more outputs unconnected),
      node: health_node_label(finding, flow),
      flow_name: flow.name
    )
  end

  defp health_message(%{code: :invalid_input_pins} = finding, flow) do
    dgettext(
      "projects",
      ~s("%{node}" in flow "%{flow_name}" has connections on input pins it no longer has),
      node: health_node_label(finding, flow),
      flow_name: flow.name
    )
  end

  defp health_message(%{code: :invalid_output_pins} = finding, flow) do
    dgettext(
      "projects",
      ~s("%{node}" in flow "%{flow_name}" has connections on output pins it no longer has),
      node: health_node_label(finding, flow),
      flow_name: flow.name
    )
  end

  defp health_message(%{code: :orphan_hub} = finding, flow) do
    dgettext(
      "projects",
      ~s("%{node}" in flow "%{flow_name}" is never targeted by a Jump),
      node: health_node_label(finding, flow),
      flow_name: flow.name
    )
  end

  defp health_message(%{code: :missing_jump_target} = finding, flow) do
    dgettext(
      "projects",
      ~s("%{node}" in flow "%{flow_name}" has no target hub set),
      node: health_node_label(finding, flow),
      flow_name: flow.name
    )
  end

  defp health_message(%{code: :missing_subflow_reference} = finding, flow) do
    dgettext(
      "projects",
      ~s("%{node}" in flow "%{flow_name}" has no referenced flow set),
      node: health_node_label(finding, flow),
      flow_name: flow.name
    )
  end

  defp health_message(%{code: :missing_exit_flow_reference} = finding, flow) do
    dgettext(
      "projects",
      ~s("%{node}" in flow "%{flow_name}" has no return flow set),
      node: health_node_label(finding, flow),
      flow_name: flow.name
    )
  end

  defp health_message(%{code: :stale_exit_flow_reference} = finding, flow) do
    dgettext(
      "projects",
      ~s("%{node}" in flow "%{flow_name}" returns to a flow that no longer exists),
      node: health_node_label(finding, flow),
      flow_name: flow.name
    )
  end

  defp health_node_label(finding, flow) do
    case Enum.find(flow.nodes, &(&1.id == finding.entity_id)) do
      nil -> Flows.node_label(%{type: finding.entity_type})
      node -> Flows.node_label(node)
    end
  end
end
