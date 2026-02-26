defmodule Storyarn.Flows.VariableReferenceTracker do
  @moduledoc """
  Tracks which sources read/write which variables (blocks).

  Handles ALL polymorphic variable reference sources:
  - **Flow nodes** — condition rules → reads, instruction assignments → writes
  - **Map zones** — instruction action_data → writes, display variable_ref → reads, condition → reads
  - **Map pins** — instruction action_data → writes, display variable_ref → reads, condition → reads

  Called after every node data or zone action_data save. Extracts variable
  references from the source's structured data and upserts them into the
  variable_references table with `source_type` ("flow_node" or "scene_zone").

  Stores `source_sheet` and `source_variable` alongside each reference so that
  staleness detection and repair can be done with simple SQL comparisons
  instead of scanning JSON in Elixir.

  > **Note:** This module lives under `Storyarn.Flows` for historical reasons
  > but operates across context boundaries via the polymorphic `source_type`
  > column. A future refactor may promote it to `Storyarn.Sheets` or a shared
  > module.
  """

  import Ecto.Query

  alias Storyarn.Flows.{Condition, Flow, FlowNode, VariableReference}
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @doc """
  Updates variable references for a node after its data changes.
  Dispatches to the correct extractor based on node type.
  """
  @spec update_references(FlowNode.t()) :: :ok
  def update_references(%FlowNode{} = node) do
    refs =
      case node.type do
        "instruction" -> extract_write_refs(node)
        "condition" -> extract_read_refs(node)
        _ -> []
      end

    replace_references("flow_node", node.id, refs, flow_node_id: node.id)
  end

  @doc """
  Deletes all variable references for a node.
  Called when a node is deleted (as backup — DB cascade handles this too).
  """
  @spec delete_references(integer()) :: :ok
  def delete_references(node_id) do
    from(vr in VariableReference,
      where: vr.source_type == "flow_node" and vr.source_id == ^node_id
    )
    |> Repo.delete_all()

    :ok
  end

  # ---------------------------------------------------------------------------
  # Map zone variable references
  # ---------------------------------------------------------------------------

  @doc """
  Updates variable references for a map zone after its action_data changes.
  Extracts assignment write refs and display read refs.
  """
  @spec update_scene_zone_references(map(), keyword()) :: :ok
  def update_scene_zone_references(zone, opts \\ [])

  def update_scene_zone_references(%{id: zone_id, scene_id: scene_id} = zone, opts) do
    project_id = opts[:project_id] || Storyarn.Scenes.get_scene_project_id(scene_id)

    refs =
      if project_id do
        extract_zone_variable_refs(zone, project_id)
      else
        []
      end

    replace_references("scene_zone", zone_id, refs)
  end

  def update_scene_zone_references(_zone, _opts), do: :ok

  @doc """
  Deletes all variable references for a map zone.
  """
  @spec delete_map_zone_references(integer()) :: :ok
  def delete_map_zone_references(zone_id) do
    from(vr in VariableReference,
      where: vr.source_type == "scene_zone" and vr.source_id == ^zone_id
    )
    |> Repo.delete_all()

    :ok
  end

  # ---------------------------------------------------------------------------
  # Map pin variable references
  # ---------------------------------------------------------------------------

  @doc """
  Updates variable references for a map pin after its action_data changes.
  Extracts assignment write refs and display read refs.
  """
  @spec update_scene_pin_references(map(), keyword()) :: :ok
  def update_scene_pin_references(pin, opts \\ [])

  def update_scene_pin_references(%{id: pin_id, scene_id: scene_id} = pin, opts) do
    project_id = opts[:project_id] || Storyarn.Scenes.get_scene_project_id(scene_id)

    refs =
      if project_id do
        extract_pin_variable_refs(pin, project_id)
      else
        []
      end

    replace_references("scene_pin", pin_id, refs)
  end

  def update_scene_pin_references(_pin, _opts), do: :ok

  @doc """
  Deletes all variable references for a map pin.
  """
  @spec delete_map_pin_references(integer()) :: :ok
  def delete_map_pin_references(pin_id) do
    from(vr in VariableReference,
      where: vr.source_type == "scene_pin" and vr.source_id == ^pin_id
    )
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Returns all variable references for a block, with source info.
  Includes flow node, map zone, and map pin sources.
  Used by the sheet editor's variable usage section.
  """
  @spec get_variable_usage(integer(), integer()) :: [map()]
  def get_variable_usage(block_id, project_id) do
    flow_refs = get_flow_node_variable_usage(block_id, project_id)
    zone_refs = get_scene_zone_variable_usage(block_id, project_id)
    pin_refs = get_scene_pin_variable_usage(block_id, project_id)
    flow_refs ++ zone_refs ++ pin_refs
  end

  defp get_flow_node_variable_usage(block_id, project_id) do
    from(vr in VariableReference,
      join: n in FlowNode,
      on: vr.source_type == "flow_node" and n.id == vr.source_id,
      join: f in Flow,
      on: f.id == n.flow_id,
      where: vr.block_id == ^block_id,
      where: f.project_id == ^project_id,
      where: is_nil(f.deleted_at),
      select: %{
        source_type: vr.source_type,
        kind: vr.kind,
        flow_id: f.id,
        flow_name: f.name,
        flow_shortcut: f.shortcut,
        node_id: n.id,
        node_type: n.type,
        node_data: n.data
      },
      order_by: [asc: vr.kind, asc: f.name]
    )
    |> Repo.all()
  end

  defp get_scene_zone_variable_usage(block_id, project_id) do
    Storyarn.Scenes.get_scene_zone_variable_usage(block_id, project_id)
  end

  defp get_scene_pin_variable_usage(block_id, project_id) do
    Storyarn.Scenes.get_scene_pin_variable_usage(block_id, project_id)
  end

  @doc """
  Counts variable references for a block, grouped by kind.
  Returns %{"read" => N, "write" => M}.
  """
  @spec count_variable_usage(integer()) :: map()
  def count_variable_usage(block_id) do
    from(vr in VariableReference,
      where: vr.block_id == ^block_id,
      group_by: vr.kind,
      select: {vr.kind, count(vr.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns variable usage for a block with stale detection.
  Each ref map gets an additional `:stale` boolean computed via SQL comparison
  of `source_sheet`/`source_variable` against the current sheet shortcut and
  block variable_name.

  Returns both flow node and map zone sources. Each result includes a
  `:source_type` field ("flow_node" or "scene_zone") to distinguish them.

  Filters out references whose sheet or block has been soft-deleted.
  """
  @spec check_stale_references(integer(), integer()) :: [map()]
  def check_stale_references(block_id, project_id) do
    flow_refs = check_stale_flow_node_references(block_id, project_id)
    zone_refs = check_stale_scene_zone_references(block_id, project_id)
    pin_refs = check_stale_scene_pin_references(block_id, project_id)
    flow_refs ++ zone_refs ++ pin_refs
  end

  defp check_stale_flow_node_references(block_id, project_id) do
    Storyarn.Sheets.check_stale_flow_node_variable_references(block_id, project_id)
  end

  defp check_stale_scene_zone_references(block_id, project_id) do
    Storyarn.Scenes.check_stale_scene_zone_variable_references(block_id, project_id)
  end

  defp check_stale_scene_pin_references(block_id, project_id) do
    Storyarn.Scenes.check_stale_scene_pin_variable_references(block_id, project_id)
  end

  @doc """
  Repairs all stale variable references across a project.
  Updates node JSON to reflect current sheet shortcut + variable names.
  Returns `{:ok, count}` where count is the number of repaired nodes,
  or `{:error, reason}` if the transaction fails.
  """
  @spec repair_stale_references(integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def repair_stale_references(project_id) do
    # Get all variable references for this project with current block info + source fields
    refs_with_info =
      Storyarn.Sheets.list_variable_refs_with_block_info_for_repair(project_id)
      |> Enum.map(&compute_table_current_variable/1)

    # Group by node_id to batch repairs per node
    repairs_by_node =
      refs_with_info
      |> Enum.group_by(& &1.node_id)
      |> Enum.reduce(%{}, fn {node_id, refs}, acc ->
        first = hd(refs)
        repaired_data = repair_node_data(first.node_type, first.node_data, refs)

        if repaired_data != first.node_data do
          Map.put(acc, node_id, repaired_data)
        else
          acc
        end
      end)

    # Apply repairs inside a transaction
    Repo.transaction(fn ->
      Enum.each(repairs_by_node, fn {node_id, new_data} ->
        node = Repo.get!(FlowNode, node_id)
        # Use do_update_node_data path via Flows facade to re-trigger reference tracking
        Storyarn.Flows.update_node_data(node, new_data)
      end)

      map_size(repairs_by_node)
    end)
  end

  @doc """
  Returns a MapSet of node IDs in a flow that have at least one stale reference.
  Uses pure SQL comparison — no JSON scanning in Elixir.
  """
  @spec list_stale_node_ids(integer()) :: MapSet.t()
  def list_stale_node_ids(flow_id) do
    regular_ids = list_stale_regular_node_ids(flow_id)
    table_ids = list_stale_table_node_ids(flow_id)
    MapSet.union(regular_ids, table_ids)
  end

  defp list_stale_regular_node_ids(flow_id) do
    Storyarn.Sheets.list_stale_regular_node_ids(flow_id)
  end

  defp list_stale_table_node_ids(flow_id) do
    Storyarn.Sheets.list_stale_table_node_ids(flow_id)
  end

  # -- Private --

  defp extract_write_refs(node) do
    assignments = node.data["assignments"] || []
    project_id = get_project_id(node.flow_id)

    if project_id do
      Enum.flat_map(assignments, &extract_assignment_refs(&1, project_id))
    else
      []
    end
  end

  defp extract_assignment_refs(assign, project_id) do
    write_ref = resolve_write_ref(project_id, assign)
    read_ref = resolve_assignment_read_ref(project_id, assign)
    write_ref ++ read_ref
  end

  defp resolve_write_ref(project_id, assign) do
    case resolve_block(project_id, assign["sheet"], assign["variable"]) do
      nil ->
        []

      block_id ->
        [
          %{
            block_id: block_id,
            kind: "write",
            source_sheet: assign["sheet"],
            source_variable: assign["variable"]
          }
        ]
    end
  end

  defp resolve_assignment_read_ref(project_id, %{"value_type" => "variable_ref"} = assign) do
    case resolve_block(project_id, assign["value_sheet"], assign["value"]) do
      nil ->
        []

      block_id ->
        [
          %{
            block_id: block_id,
            kind: "read",
            source_sheet: assign["value_sheet"],
            source_variable: assign["value"]
          }
        ]
    end
  end

  defp resolve_assignment_read_ref(_project_id, _assign), do: []

  defp extract_read_refs(node) do
    rules = Condition.extract_all_rules(node.data["condition"])
    project_id = get_project_id(node.flow_id)

    if project_id do
      Enum.flat_map(rules, &resolve_rule_read_ref(&1, project_id))
    else
      []
    end
  end

  defp resolve_rule_read_ref(rule, project_id) do
    case resolve_block(project_id, rule["sheet"], rule["variable"]) do
      nil ->
        []

      block_id ->
        [
          %{
            block_id: block_id,
            kind: "read",
            source_sheet: rule["sheet"],
            source_variable: rule["variable"]
          }
        ]
    end
  end

  defp get_project_id(flow_id) do
    from(f in Flow, where: f.id == ^flow_id, select: f.project_id)
    |> Repo.one()
  end

  defp resolve_block(project_id, sheet_shortcut, variable_name)
       when is_binary(sheet_shortcut) and sheet_shortcut != "" and
              is_binary(variable_name) and variable_name != "" do
    case String.split(variable_name, ".", parts: 3) do
      [table_name, row_slug, column_slug] ->
        resolve_table_block(project_id, sheet_shortcut, table_name, row_slug, column_slug)

      _ ->
        resolve_regular_block(project_id, sheet_shortcut, variable_name)
    end
  end

  defp resolve_block(_, _, _), do: nil

  defp resolve_regular_block(project_id, sheet_shortcut, variable_name) do
    Storyarn.Sheets.resolve_block_id_by_variable(project_id, sheet_shortcut, variable_name)
  end

  defp resolve_table_block(project_id, sheet_shortcut, table_name, row_slug, column_slug) do
    Storyarn.Sheets.resolve_table_block_id_by_variable(
      project_id,
      sheet_shortcut,
      table_name,
      row_slug,
      column_slug
    )
  end

  # Repairs node data by replacing stale shortcut/variable references with current values.
  # Uses deterministic matching via source_sheet/source_variable stored in the reference.
  defp repair_node_data("instruction", data, refs) do
    assignments = data["assignments"] || []

    assignments =
      assignments
      |> repair_write_targets(Enum.filter(refs, &(&1.kind == "write")))
      |> repair_read_sources(Enum.filter(refs, &(&1.kind == "read")))

    Map.put(data, "assignments", assignments)
  end

  defp repair_node_data("condition", data, refs) do
    condition = data["condition"]

    if is_nil(condition) do
      data
    else
      read_refs = Enum.filter(refs, &(&1.kind == "read"))

      updated_condition =
        if condition["blocks"] do
          updated_blocks = Enum.map(condition["blocks"], &repair_block(&1, read_refs))
          Map.put(condition, "blocks", updated_blocks)
        else
          updated_rules = repair_condition_rules(condition["rules"] || [], read_refs)
          Map.put(condition, "rules", updated_rules)
        end

      Map.put(data, "condition", updated_condition)
    end
  end

  defp repair_node_data(_, data, _refs), do: data

  # Deterministic repair: match each assignment's sheet+variable to a ref's source_sheet+source_variable.
  defp repair_write_targets(assignments, write_refs) do
    Enum.map(assignments, fn assignment ->
      matching_ref =
        Enum.find(write_refs, fn ref ->
          ref.source_sheet == assignment["sheet"] and
            ref.source_variable == assignment["variable"]
        end)

      if matching_ref do
        assignment
        |> Map.put("sheet", matching_ref.current_shortcut)
        |> Map.put("variable", matching_ref.current_variable)
      else
        assignment
      end
    end)
  end

  # Deterministic repair for variable_ref read sources in instruction assignments.
  defp repair_read_sources(assignments, read_refs) do
    Enum.map(assignments, &repair_read_source(&1, read_refs))
  end

  defp repair_read_source(%{"value_type" => "variable_ref"} = assignment, read_refs) do
    matching_ref =
      Enum.find(read_refs, fn ref ->
        ref.source_sheet == assignment["value_sheet"] and
          ref.source_variable == assignment["value"]
      end)

    if matching_ref do
      assignment
      |> Map.put("value_sheet", matching_ref.current_shortcut)
      |> Map.put("value", matching_ref.current_variable)
    else
      assignment
    end
  end

  defp repair_read_source(assignment, _read_refs), do: assignment

  # Deterministic repair for condition rules.
  defp repair_condition_rules(rules, read_refs) do
    Enum.map(rules, fn rule ->
      matching_ref =
        Enum.find(read_refs, fn ref ->
          ref.source_sheet == rule["sheet"] and
            ref.source_variable == rule["variable"]
        end)

      if matching_ref do
        rule
        |> Map.put("sheet", matching_ref.current_shortcut)
        |> Map.put("variable", matching_ref.current_variable)
      else
        rule
      end
    end)
  end

  defp repair_block(%{"type" => "block", "rules" => rules} = block, read_refs) do
    Map.put(block, "rules", repair_condition_rules(rules || [], read_refs))
  end

  defp repair_block(%{"type" => "group", "blocks" => inner_blocks} = group, read_refs) do
    Map.put(group, "blocks", Enum.map(inner_blocks || [], &repair_block(&1, read_refs)))
  end

  defp repair_block(block, _read_refs), do: block

  # For table blocks, the repair query returns current_variable = b.variable_name (e.g. "attributes")
  # but the source_variable is a composite path (e.g. "attributes.strength.value").
  # We reconstruct the full path using the current table name + the original row/col slugs.
  defp compute_table_current_variable(%{source_variable: sv, current_variable: cv} = ref) do
    case String.split(sv, ".", parts: 3) do
      [_old_table, row_slug, col_slug] ->
        %{ref | current_variable: "#{cv}.#{row_slug}.#{col_slug}"}

      _ ->
        ref
    end
  end

  defp extract_zone_variable_refs(zone, project_id) do
    action_refs = extract_action_variable_refs(zone, project_id)
    condition_refs = extract_condition_variable_refs(zone, project_id)
    action_refs ++ condition_refs
  end

  defp extract_pin_variable_refs(pin, project_id) do
    action_refs = extract_action_variable_refs(pin, project_id)
    condition_refs = extract_condition_variable_refs(pin, project_id)
    action_refs ++ condition_refs
  end

  # Shared extraction for action_type + action_data (zones and pins)
  defp extract_action_variable_refs(element, project_id) do
    case Map.get(element, :action_type) do
      "instruction" ->
        assignments = (Map.get(element, :action_data) || %{})["assignments"] || []
        Enum.flat_map(assignments, &extract_assignment_refs(&1, project_id))

      "display" ->
        variable_ref = (Map.get(element, :action_data) || %{})["variable_ref"]
        resolve_display_variable_ref(project_id, variable_ref)

      _ ->
        []
    end
  end

  # Shared extraction for condition read refs (zones and pins)
  defp extract_condition_variable_refs(element, project_id) do
    condition = Map.get(element, :condition)

    if is_nil(condition) do
      []
    else
      rules = Condition.extract_all_rules(condition)
      Enum.flat_map(rules, &resolve_rule_read_ref(&1, project_id))
    end
  end

  defp resolve_display_variable_ref(_project_id, nil), do: []
  defp resolve_display_variable_ref(_project_id, ""), do: []

  defp resolve_display_variable_ref(project_id, variable_ref) do
    case String.split(variable_ref, ".", parts: 2) do
      [sheet_shortcut, variable_name] ->
        case resolve_block(project_id, sheet_shortcut, variable_name) do
          nil ->
            []

          block_id ->
            [
              %{
                block_id: block_id,
                kind: "read",
                source_sheet: sheet_shortcut,
                source_variable: variable_name
              }
            ]
        end

      _ ->
        []
    end
  end

  defp replace_references(source_type, source_id, refs, opts \\ []) do
    Repo.transaction(fn ->
      from(vr in VariableReference,
        where: vr.source_type == ^source_type and vr.source_id == ^source_id
      )
      |> Repo.delete_all()

      unique_refs = Enum.uniq_by(refs, fn r -> {r.block_id, r.kind, r.source_variable} end)
      now = TimeHelpers.now()

      entries =
        Enum.map(unique_refs, fn ref ->
          %{
            source_type: source_type,
            source_id: source_id,
            flow_node_id: Keyword.get(opts, :flow_node_id),
            block_id: ref.block_id,
            kind: ref.kind,
            source_sheet: ref.source_sheet,
            source_variable: ref.source_variable,
            inserted_at: now,
            updated_at: now
          }
        end)

      if entries != [] do
        Repo.insert_all(VariableReference, entries, on_conflict: :nothing)
      end
    end)

    :ok
  end
end
