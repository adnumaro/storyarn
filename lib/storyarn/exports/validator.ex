defmodule Storyarn.Exports.Validator do
  @moduledoc """
  Pre-export validation for projects.

  Checks for broken references, orphan nodes, missing translations,
  and other issues that would cause problems in exported files.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Repo

  alias Storyarn.Flows.{Flow, FlowNode, VariableReference}
  alias Storyarn.Localization.{LocalizedText, ProjectLanguage}
  alias Storyarn.Sheets.Sheet

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

  # =============================================================================
  # Check runner
  # =============================================================================

  defp run_all_checks(project_id, opts) do
    # Load data needed for multiple checks
    flows_data = load_flows_data(project_id, opts)
    sheets = load_sheets(project_id)

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

  defp load_flows_data(project_id, _opts) do
    active_nodes_query = from(n in FlowNode, where: is_nil(n.deleted_at))

    from(f in Flow,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      preload: [nodes: ^active_nodes_query, connections: []]
    )
    |> Repo.all()
  end

  defp load_sheets(project_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      select: %{id: s.id, name: s.name, shortcut: s.shortcut}
    )
    |> Repo.all()
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
        message: "Flow \"#{flow.name}\" has no Entry node",
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
      |> Enum.reject(&(&1.type in ["entry", "exit"] or MapSet.member?(connected_ids, &1.id)))
      |> Enum.map(fn node ->
        %{
          level: :warning,
          rule: :orphan_nodes,
          message:
            "#{node.type} node (id: #{node.id}) in flow \"#{flow.name}\" has no connections",
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
      |> Enum.filter(&(MapSet.member?(unreachable_ids, &1.id) and &1.type != "entry"))
      |> Enum.map(fn node ->
        %{
          level: :warning,
          rule: :unreachable_nodes,
          message:
            "#{node.type} node (id: #{node.id}) in flow \"#{flow.name}\" is not reachable from Entry",
          flow_id: flow.id,
          flow_name: flow.name,
          node_id: node.id,
          node_type: node.type
        }
      end)
    end
  end

  # =============================================================================
  # Check: empty_dialogue (warning)
  # =============================================================================

  defp check_empty_dialogue(flows) do
    Enum.flat_map(flows, fn flow ->
      flow.nodes
      |> Enum.filter(fn node ->
        node.type == "dialogue" and
          ((get_in(node.data, ["text"]) || "") |> strip_html() |> String.trim()) == ""
      end)
      |> Enum.map(fn node ->
        %{
          level: :warning,
          rule: :empty_dialogue,
          message: "Dialogue node (id: #{node.id}) in flow \"#{flow.name}\" has no text",
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
          (get_in(node.data, ["speaker_sheet_id"]) |> nil_or_empty?())
      end)
      |> Enum.map(fn node ->
        %{
          level: :warning,
          rule: :missing_speakers,
          message:
            "Dialogue node (id: #{node.id}) in flow \"#{flow.name}\" has no speaker assigned",
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
          |> Enum.map(&get_in(&1.data, ["target_flow_id"]))
          |> Enum.reject(&is_nil/1)

        if targets != [], do: Map.put(acc, flow.id, targets), else: acc
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
        message: "Flow \"#{flow_name}\" is part of a circular subflow reference chain",
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
    subflow_findings = check_broken_subflow_refs(project_id, flows)

    # Check scene nodes referencing non-existent scenes
    scene_findings = check_broken_scene_refs(project_id, flows)

    jump_findings ++ subflow_findings ++ scene_findings
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
            "Jump node (id: #{node.id}) in flow \"#{flow.name}\" references non-existent hub \"#{target}\"",
          flow_id: flow.id,
          flow_name: flow.name,
          node_id: node.id,
          ref_type: :hub,
          ref_value: target
        }
      end)
    end)
  end

  defp check_broken_subflow_refs(_project_id, flows) do
    valid_flow_ids = MapSet.new(flows, & &1.id)

    Enum.flat_map(flows, fn flow ->
      flow.nodes
      |> Enum.filter(fn node ->
        node.type == "subflow" and has_broken_ref?(node, "target_flow_id", valid_flow_ids)
      end)
      |> Enum.map(fn node ->
        %{
          level: :error,
          rule: :broken_references,
          message:
            "Subflow node (id: #{node.id}) in flow \"#{flow.name}\" references non-existent flow",
          flow_id: flow.id,
          flow_name: flow.name,
          node_id: node.id,
          ref_type: :flow
        }
      end)
    end)
  end

  defp check_broken_scene_refs(project_id, flows) do
    valid_scene_ids =
      from(s in Storyarn.Scenes.Scene,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        select: s.id
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.flat_map(flows, fn flow ->
      flow.nodes
      |> Enum.filter(fn node ->
        node.type == "scene" and has_broken_ref?(node, "scene_id", valid_scene_ids)
      end)
      |> Enum.map(fn node ->
        %{
          level: :error,
          rule: :broken_references,
          message:
            "Scene node (id: #{node.id}) in flow \"#{flow.name}\" references non-existent scene",
          flow_id: flow.id,
          flow_name: flow.name,
          node_id: node.id,
          ref_type: :scene
        }
      end)
    end)
  end

  # =============================================================================
  # Check: missing_translations (warning)
  # =============================================================================

  defp check_missing_translations(project_id, _opts) do
    languages =
      from(l in ProjectLanguage,
        where: l.project_id == ^project_id and l.is_source == false,
        select: l.locale_code
      )
      |> Repo.all()

    if languages == [] do
      []
    else
      do_check_missing_translations(project_id, languages)
    end
  end

  defp do_check_missing_translations(project_id, languages) do
    total_sources =
      from(lt in LocalizedText,
        where: lt.project_id == ^project_id,
        select:
          fragment("count(DISTINCT (?, ?, ?))", lt.source_type, lt.source_id, lt.source_field)
      )
      |> Repo.one() || 0

    pending_by_locale =
      from(lt in LocalizedText,
        where:
          lt.project_id == ^project_id and
            lt.locale_code in ^languages and
            lt.status in ["pending", "draft"],
        group_by: lt.locale_code,
        select: {lt.locale_code, count(lt.id)}
      )
      |> Repo.all()
      |> Map.new()

    languages
    |> Enum.filter(&(Map.get(pending_by_locale, &1, 0) > 0))
    |> Enum.map(fn locale ->
      pending = Map.get(pending_by_locale, locale, 0)

      %{
        level: :warning,
        rule: :missing_translations,
        message:
          "#{pending} of #{total_sources} strings are untranslated for locale \"#{locale}\"",
        locale: locale,
        pending_count: pending,
        total_count: total_sources
      }
    end)
  end

  # =============================================================================
  # Check: orphan_sheets (info)
  # =============================================================================

  defp check_orphan_sheets(project_id, sheets) do
    # Find sheets referenced by flow nodes (speaker_sheet_id)
    # speaker_sheet_id is stored as string in JSONB — only cast valid integers
    referenced_sheet_ids =
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where: f.project_id == ^project_id and is_nil(n.deleted_at) and is_nil(f.deleted_at),
        where: fragment("?->>'speaker_sheet_id' ~ '^[0-9]+$'", n.data),
        select: fragment("(?->>'speaker_sheet_id')::integer", n.data)
      )
      |> Repo.all()
      |> MapSet.new()

    # Also check variable_references — blocks referenced by flow nodes
    block_sheet_ids =
      from(vr in VariableReference,
        join: b in Storyarn.Sheets.Block,
        on: vr.block_id == b.id,
        join: s in Sheet,
        on: b.sheet_id == s.id,
        where: s.project_id == ^project_id,
        select: s.id
      )
      |> Repo.all()
      |> MapSet.new()

    all_referenced = MapSet.union(referenced_sheet_ids, block_sheet_ids)

    # Also check scene pin/zone sheet references
    pin_sheet_ids =
      from(p in Storyarn.Scenes.ScenePin,
        join: s in Storyarn.Scenes.Scene,
        on: p.scene_id == s.id,
        where: s.project_id == ^project_id and not is_nil(p.sheet_id),
        select: p.sheet_id
      )
      |> Repo.all()
      |> MapSet.new()

    all_referenced = MapSet.union(all_referenced, pin_sheet_ids)

    sheets
    |> Enum.reject(&(MapSet.member?(all_referenced, &1.id) or &1.shortcut == nil))
    |> Enum.map(fn sheet ->
      %{
        level: :info,
        rule: :orphan_sheets,
        message: "Sheet \"#{sheet.name}\" has no references from flows or scenes",
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
      Enum.flat_map(queue, fn node_id ->
        Map.get(adj, node_id, [])
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

      Map.get(graph, start_id, [])
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

  defp strip_html(text) when is_binary(text) do
    Regex.replace(~r/<[^>]+>/, text, "")
  end

  defp strip_html(_), do: ""

  defp nil_or_empty?(nil), do: true
  defp nil_or_empty?(""), do: true
  defp nil_or_empty?(_), do: false
end
