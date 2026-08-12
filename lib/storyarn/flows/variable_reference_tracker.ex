defmodule Storyarn.Flows.VariableReferenceTracker do
  @moduledoc """
  Tracks which sources read/write which variables (blocks).

  Handles ALL polymorphic variable reference sources:
  - **Flow nodes** — condition/dialogue rules → reads, instruction/dialogue assignments → writes
  - **Map zones** — action assignments → writes, display variable_ref → reads, condition → reads
  - **Map pins** — flow/display references and conditions → reads
  - **Scene ambient flows** — on-event variable_ref → reads

  Called after every Flow node, Scene pin/zone, or Scene ambient-flow save.
  Extracts references from the source's structured data and upserts them into
  `variable_references` with one of the four supported `source_type` values:
  `"flow_node"`, `"scene_pin"`, `"scene_zone"`, or
  `"scene_ambient_flow"`.

  Stores `source_sheet` and `source_variable` alongside each reference so that
  staleness detection and repair can be done with simple SQL comparisons
  instead of scanning JSON in Elixir.

  > **Note:** This module lives under `Storyarn.Flows` for historical reasons
  > but operates across context boundaries via the polymorphic `source_type`
  > column. A future refactor may promote it to `Storyarn.Sheets` or a shared
  > module.
  """

  import Ecto.Query

  alias Storyarn.Collaboration
  alias Storyarn.Flows.Condition
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeUpdate
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow
  alias Storyarn.Sheets.VariableCatalog

  @rebuild_batch_size 100
  @regular_variable_types VariableCatalog.regular_variable_types()
  @table_variable_types VariableCatalog.table_variable_types()
  @constant_table_variable_types VariableCatalog.constant_table_variable_types()

  @type rebuild_error ::
          {:invalid_project_id, term()}
          | {:project_variable_reference_rebuild_failed,
             %{
               project_id: integer(),
               source_type: String.t(),
               source_id: integer(),
               reason: term()
             }}

  @doc """
  Restores variable-reference rows that can be resolved from every active
  source in a project.

  Active sources are:

  * non-deleted nodes that belong to non-deleted flows
  * pins, zones, and ambient-flow links that belong to non-deleted scenes

  This operation is deliberately additive. Existing rows may represent stale
  references after a Sheet shortcut, block variable, or table slug changed;
  those rows must remain available to the stale-reference repair workflow.
  Replacing all rows here would destroy that recovery information.

  The caller is responsible for the outer transaction so the rebuild can be
  committed or rolled back with the operation that made it necessary.
  """
  @spec rebuild_project_variable_references(integer()) :: :ok | {:error, rebuild_error()}
  def rebuild_project_variable_references(project_id) when is_integer(project_id) and project_id > 0 do
    with :ok <-
           rebuild_sources(
             active_flow_nodes_query(project_id),
             project_id,
             "flow_node",
             &restore_missing_flow_node_references/1
           ),
         :ok <-
           rebuild_sources(
             active_scene_pins_query(project_id),
             project_id,
             "scene_pin",
             &restore_missing_scene_pin_references(&1, project_id)
           ),
         :ok <-
           rebuild_sources(
             active_scene_zones_query(project_id),
             project_id,
             "scene_zone",
             &restore_missing_scene_zone_references(&1, project_id)
           ) do
      rebuild_sources(
        active_scene_ambient_flows_query(project_id),
        project_id,
        "scene_ambient_flow",
        &restore_missing_scene_ambient_flow_references(&1, project_id)
      )
    end
  end

  def rebuild_project_variable_references(project_id), do: {:error, {:invalid_project_id, project_id}}

  @doc """
  Updates variable references for a node after its data changes.
  Dispatches to the correct extractor based on node type.
  """
  @spec update_references(FlowNode.t()) :: :ok | {:error, term()}
  def update_references(%FlowNode{} = node) do
    refs = extract_flow_node_variable_refs(node)

    replace_references("flow_node", node.id, refs, flow_node_id: node.id)
  end

  @doc false
  @spec flow_node_references_current_ids([FlowNode.t()], integer()) ::
          MapSet.t(integer())
  def flow_node_references_current_ids(nodes, project_id) when is_list(nodes) and is_integer(project_id) do
    valid_nodes =
      Enum.filter(nodes, fn
        %FlowNode{id: node_id, data: data}
        when is_integer(node_id) and is_map(data) ->
          true

        _node ->
          false
      end)

    node_ids = Enum.map(valid_nodes, & &1.id)
    specs = Enum.flat_map(valid_nodes, &flow_node_reference_specs/1)
    resolved_block_ids = resolve_reference_block_ids(project_id, specs)
    expected_by_node = expected_flow_node_reference_sets(specs, resolved_block_ids)
    actual_by_node = actual_flow_node_reference_sets(node_ids)

    Enum.reduce(valid_nodes, MapSet.new(), fn node, current_ids ->
      expected = Map.get(expected_by_node, node.id, MapSet.new())
      actual = Map.get(actual_by_node, node.id, MapSet.new())

      if expected == actual,
        do: MapSet.put(current_ids, node.id),
        else: current_ids
    end)
  end

  @doc """
  Validates that every complete variable reference embedded in Flow node data
  resolves to an active block in the project.

  This accepts both persisted `FlowNode` structs and snapshot node maps. It is
  intentionally stricter than the reference rebuild path: rebuilds preserve
  incomplete editor drafts and skip stale names, while an in-place historical
  restore must fail closed rather than persist a nominal reference that cannot
  be represented in `variable_references`.
  """
  @spec validate_flow_node_variable_targets([FlowNode.t() | map()], integer()) ::
          :ok | {:error, term()}
  def validate_flow_node_variable_targets(nodes, project_id)
      when is_list(nodes) and is_integer(project_id) and project_id > 0 do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, specs} ->
      case strict_flow_node_reference_specs(node) do
        {:ok, node_specs} -> {:cont, {:ok, specs ++ node_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, specs} -> validate_resolvable_specs(project_id, "flow_node", specs)
      {:error, _reason} = error -> error
    end
  end

  def validate_flow_node_variable_targets(nodes, project_id),
    do: {:error, {:invalid_variable_reference_validation_scope, "flow_node", project_id, nodes}}

  @doc """
  Validates complete variable references embedded in Scene pin or zone data.

  `source_type` must be `"scene_pin"` or `"scene_zone"`. Elements may be
  persisted structs or snapshot maps with string keys. This API lets restore
  builders share the exact resolver used by runtime reference tracking.
  """
  @spec validate_scene_element_variable_targets([map()], integer(), String.t()) ::
          :ok | {:error, term()}
  def validate_scene_element_variable_targets(elements, project_id, source_type)
      when is_list(elements) and is_integer(project_id) and project_id > 0 and source_type in ["scene_pin", "scene_zone"] do
    elements
    |> Enum.reduce_while({:ok, []}, fn element, {:ok, specs} ->
      case strict_scene_element_reference_specs(element, source_type) do
        {:ok, element_specs} -> {:cont, {:ok, specs ++ element_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, specs} -> validate_resolvable_specs(project_id, source_type, specs)
      {:error, _reason} = error -> error
    end
  end

  def validate_scene_element_variable_targets(elements, project_id, source_type),
    do: {:error, {:invalid_variable_reference_validation_scope, source_type, project_id, elements}}

  @doc """
  Validates a mixed collection of snapshot variable-reference sources with one
  batched target resolution.

  Each source map must include `source_type` (`"flow_node"`, `"scene_pin"`,
  `"scene_zone"`, or `"scene_ambient_flow"`) and `source_id`. Flow sources
  also carry `type` and `data`; pin/zone sources carry `action_type`,
  `action_data`, and `condition`; ambient-flow sources carry `trigger_type`
  and `trigger_config`.
  """
  @spec validate_snapshot_variable_references(integer(), [map()]) ::
          :ok | {:error, term()}
  def validate_snapshot_variable_references(project_id, sources)
      when is_integer(project_id) and project_id > 0 and is_list(sources) do
    sources
    |> Enum.reduce_while({:ok, []}, fn source, {:ok, specs} ->
      case strict_snapshot_source_reference_specs(source) do
        {:ok, source_type, source_specs} ->
          tagged_specs = Enum.map(source_specs, &Map.put(&1, :source_type, source_type))
          {:cont, {:ok, specs ++ tagged_specs}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, specs} -> validate_resolvable_specs(project_id, nil, specs)
      {:error, _reason} = error -> error
    end
  end

  def validate_snapshot_variable_references(project_id, sources),
    do: {:error, {:invalid_variable_reference_validation_scope, :mixed, project_id, sources}}

  @doc """
  Deletes all variable references for a node.
  Called when a node is deleted (as backup — DB cascade handles this too).
  """
  @spec delete_references(integer()) :: :ok
  def delete_references(node_id) do
    Repo.delete_all(from(vr in VariableReference, where: vr.source_type == "flow_node" and vr.source_id == ^node_id))
    :ok
  end

  # ---------------------------------------------------------------------------
  # Map zone variable references
  # ---------------------------------------------------------------------------

  @doc """
  Updates variable references for a map zone after its action_data changes.
  Extracts assignment write refs and display read refs.
  """
  @spec update_scene_zone_references(map(), keyword()) :: :ok | {:error, term()}
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
    Repo.delete_all(from(vr in VariableReference, where: vr.source_type == "scene_zone" and vr.source_id == ^zone_id))
    :ok
  end

  # ---------------------------------------------------------------------------
  # Map pin variable references
  # ---------------------------------------------------------------------------

  @doc """
  Updates variable references for a map pin after its action_data changes.
  Extracts assignment write refs and display read refs.
  """
  @spec update_scene_pin_references(map(), keyword()) :: :ok | {:error, term()}
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
    Repo.delete_all(from(vr in VariableReference, where: vr.source_type == "scene_pin" and vr.source_id == ^pin_id))
    :ok
  end

  @doc "Updates the read reference for an on-event Scene ambient-flow trigger."
  @spec update_scene_ambient_flow_references(map(), keyword()) :: :ok | {:error, term()}
  def update_scene_ambient_flow_references(ambient_flow, opts \\ [])

  def update_scene_ambient_flow_references(%{id: ambient_flow_id, scene_id: scene_id} = ambient_flow, opts) do
    project_id = opts[:project_id] || Storyarn.Scenes.get_scene_project_id(scene_id)

    refs =
      if project_id do
        extract_ambient_flow_variable_refs(ambient_flow, project_id)
      else
        []
      end

    replace_references("scene_ambient_flow", ambient_flow_id, refs)
  end

  def update_scene_ambient_flow_references(_ambient_flow, _opts), do: :ok

  @doc "Deletes all variable references for a Scene ambient-flow link."
  @spec delete_scene_ambient_flow_references(integer()) :: :ok
  def delete_scene_ambient_flow_references(ambient_flow_id) do
    Repo.delete_all(
      from(reference in VariableReference,
        where:
          reference.source_type == "scene_ambient_flow" and
            reference.source_id == ^ambient_flow_id
      )
    )

    :ok
  end

  @doc """
  Returns all variable references for a block, with source info.
  Includes Flow node, Scene zone/pin, and Scene ambient-flow sources.
  Used by the sheet editor's variable usage section.
  """
  @spec get_variable_usage(integer(), integer()) :: [map()]
  def get_variable_usage(block_id, project_id) do
    flow_refs = get_flow_node_variable_usage(block_id, project_id)
    zone_refs = get_scene_zone_variable_usage(block_id, project_id)
    pin_refs = get_scene_pin_variable_usage(block_id, project_id)
    ambient_flow_refs = get_scene_ambient_flow_variable_usage(block_id, project_id)
    flow_refs ++ zone_refs ++ pin_refs ++ ambient_flow_refs
  end

  defp get_flow_node_variable_usage(block_id, project_id) do
    Repo.all(
      from(vr in VariableReference,
        join: n in FlowNode,
        on: vr.source_type == "flow_node" and n.id == vr.source_id,
        join: f in Flow,
        on: f.id == n.flow_id,
        where: vr.block_id == ^block_id,
        where: f.project_id == ^project_id,
        where: is_nil(f.deleted_at),
        where: is_nil(n.deleted_at),
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
    )
  end

  defp get_scene_zone_variable_usage(block_id, project_id) do
    Storyarn.Scenes.get_scene_zone_variable_usage(block_id, project_id)
  end

  defp get_scene_pin_variable_usage(block_id, project_id) do
    Storyarn.Scenes.get_scene_pin_variable_usage(block_id, project_id)
  end

  defp get_scene_ambient_flow_variable_usage(block_id, project_id) do
    Storyarn.Scenes.get_scene_ambient_flow_variable_usage(block_id, project_id)
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
  Returns a MapSet of block IDs that have at least one variable reference.
  Uses DISTINCT to avoid counting — just checks existence.
  """
  @spec referenced_block_ids([integer()]) :: MapSet.t()
  def referenced_block_ids([]), do: MapSet.new()

  def referenced_block_ids(block_ids) do
    from(vr in VariableReference,
      where: vr.block_id in ^block_ids,
      distinct: vr.block_id,
      select: vr.block_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "Returns stale reference counts for many blocks in one grouped query."
  @spec count_stale_references([integer()], integer()) :: %{integer() => non_neg_integer()}
  def count_stale_references([], _project_id), do: %{}

  def count_stale_references(block_ids, project_id) do
    block_ids
    |> stale_reference_count_query(project_id)
    |> Repo.all()
    |> Map.new()
  end

  defp stale_reference_count_query(block_ids, project_id) do
    VariableReference
    |> join_stale_reference_sources()
    |> scope_stale_reference_sources(block_ids, project_id)
    |> filter_active_reference_sources(project_id)
    |> filter_stale_variable_references()
    |> group_stale_reference_counts()
  end

  defp join_stale_reference_sources(query) do
    from(reference in query,
      as: :reference,
      join: block in Block,
      as: :block,
      on: block.id == reference.block_id,
      join: sheet in Sheet,
      as: :sheet,
      on: sheet.id == block.sheet_id,
      left_join: node in FlowNode,
      as: :node,
      on: reference.source_type == "flow_node" and node.id == reference.source_id,
      left_join: flow in Flow,
      as: :flow,
      on: flow.id == node.flow_id,
      left_join: zone in SceneZone,
      as: :zone,
      on: reference.source_type == "scene_zone" and zone.id == reference.source_id,
      left_join: zone_scene in Scene,
      as: :zone_scene,
      on: zone_scene.id == zone.scene_id,
      left_join: pin in ScenePin,
      as: :pin,
      on: reference.source_type == "scene_pin" and pin.id == reference.source_id,
      left_join: pin_scene in Scene,
      as: :pin_scene,
      on: pin_scene.id == pin.scene_id,
      left_join: ambient_flow in SceneAmbientFlow,
      as: :ambient_flow,
      on:
        reference.source_type == "scene_ambient_flow" and
          ambient_flow.id == reference.source_id,
      left_join: ambient_scene in Scene,
      as: :ambient_scene,
      on: ambient_scene.id == ambient_flow.scene_id
    )
  end

  defp scope_stale_reference_sources(query, block_ids, project_id) do
    from([reference: reference, block: block, sheet: sheet] in query,
      where:
        reference.block_id in ^block_ids and sheet.project_id == ^project_id and
          is_nil(sheet.deleted_at) and is_nil(block.deleted_at)
    )
  end

  defp filter_active_reference_sources(query, project_id) do
    from(
      [
        reference: reference,
        node: node,
        flow: flow,
        zone: zone,
        zone_scene: zone_scene,
        pin: pin,
        pin_scene: pin_scene,
        ambient_flow: ambient_flow,
        ambient_scene: ambient_scene
      ] in query,
      where:
        fragment(
          """
          (? = 'flow_node' AND ? IS NOT NULL AND ? IS NULL AND ? = ? AND ? IS NULL)
          OR (? = 'scene_zone' AND ? IS NOT NULL AND ? = ? AND ? IS NULL)
          OR (? = 'scene_pin' AND ? IS NOT NULL AND ? = ? AND ? IS NULL)
          OR (? = 'scene_ambient_flow' AND ? IS NOT NULL AND ? = ? AND ? IS NULL)
          """,
          reference.source_type,
          node.id,
          node.deleted_at,
          flow.project_id,
          ^project_id,
          flow.deleted_at,
          reference.source_type,
          zone.id,
          zone_scene.project_id,
          ^project_id,
          zone_scene.deleted_at,
          reference.source_type,
          pin.id,
          pin_scene.project_id,
          ^project_id,
          pin_scene.deleted_at,
          reference.source_type,
          ambient_flow.id,
          ambient_scene.project_id,
          ^project_id,
          ambient_scene.deleted_at
        )
    )
  end

  defp filter_stale_variable_references(query) do
    from([reference: reference, block: block, sheet: sheet] in query,
      where:
        fragment(
          """
          CASE WHEN ? = 'table' THEN
            ? != ? OR NOT EXISTS (
              SELECT 1 FROM table_rows tr
              JOIN table_columns tc ON tc.block_id = tr.block_id
              WHERE tr.block_id = ?
                AND ? = ? || '.' || tr.slug || '.' || tc.slug
            )
          ELSE
            ? != ? OR ? != ?
          END
          """,
          block.type,
          reference.source_sheet,
          sheet.shortcut,
          block.id,
          reference.source_variable,
          block.variable_name,
          reference.source_sheet,
          sheet.shortcut,
          reference.source_variable,
          block.variable_name
        )
    )
  end

  defp group_stale_reference_counts(query) do
    from([reference: reference] in query,
      group_by: reference.block_id,
      select: {reference.block_id, count(reference.id)}
    )
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
    ambient_flow_refs = check_stale_scene_ambient_flow_references(block_id, project_id)
    flow_refs ++ zone_refs ++ pin_refs ++ ambient_flow_refs
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

  defp check_stale_scene_ambient_flow_references(block_id, project_id) do
    Storyarn.Scenes.check_stale_scene_ambient_flow_variable_references(block_id, project_id)
  end

  @doc """
  Repairs all stale variable references across a project.
  Updates node JSON to reflect current sheet shortcut + variable names.
  Returns `{:ok, count}` where count is the number of repaired nodes,
  or `{:error, {:partial_variable_reference_repair, details}}` when one or
  more independent node repairs fail. Successful nodes remain repaired and
  `details.repaired_count` reports that progress.
  """
  @spec repair_stale_references(integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def repair_stale_references(project_id) do
    # Get all variable references for this project with current block info + source fields
    refs_with_info =
      project_id
      |> Storyarn.Sheets.list_variable_refs_with_block_info_for_repair()
      |> Enum.map(&compute_table_current_variable/1)

    # Group by node_id to batch repairs per node
    repairs_by_node =
      refs_with_info
      |> Enum.group_by(& &1.node_id)
      |> Enum.reduce(%{}, fn {node_id, refs}, acc ->
        first = hd(refs)
        repaired_data = repair_node_data(first.node_type, first.node_data, refs)

        if repaired_data == first.node_data do
          acc
        else
          Map.put(acc, node_id, repaired_data)
        end
      end)

    repairs_by_node
    |> apply_repairs()
    |> broadcast_repair_result(project_id)
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

  defp apply_repairs(repairs_by_node) do
    {repaired_count, failures} =
      repairs_by_node
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce({0, []}, &collect_repair_result/2)

    case failures do
      [] ->
        {:ok, repaired_count}

      failures ->
        {:error,
         {:partial_variable_reference_repair, %{repaired_count: repaired_count, failures: Enum.reverse(failures)}}}
    end
  end

  defp collect_repair_result({node_id, _data} = repair, {repaired_count, failures}) do
    case repair_single_node(repair) do
      {:ok, _node, _meta} -> {repaired_count + 1, failures}
      :skip -> {repaired_count, failures}
      {:error, reason} -> {repaired_count, [{node_id, reason} | failures]}
    end
  end

  defp repair_single_node({node_id, new_data}) do
    case Repo.get(FlowNode, node_id) do
      nil -> :skip
      node -> NodeUpdate.update_node_data_without_dashboard_broadcast(node, new_data)
    end
  end

  defp broadcast_repair_result({:ok, count} = result, project_id) when count > 0 do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    result
  end

  defp broadcast_repair_result(
         {:error, {:partial_variable_reference_repair, %{repaired_count: count}}} = result,
         project_id
       )
       when count > 0 do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    result
  end

  defp broadcast_repair_result(result, _project_id), do: result

  # -- Private --

  defp strict_flow_node_reference_specs(%FlowNode{id: source_id, type: type, data: data})
       when is_integer(source_id) and is_map(data) do
    case type do
      "instruction" ->
        strict_assignment_list_specs(
          "flow_node",
          source_id,
          Map.get(data, "assignments", [])
        )

      "condition" ->
        strict_condition_reference_specs(
          "flow_node",
          source_id,
          Map.get(data, "condition")
        )

      "dialogue" ->
        strict_dialogue_response_reference_specs(source_id, Map.get(data, "responses", []))

      _other ->
        {:ok, []}
    end
  end

  defp strict_flow_node_reference_specs(%{} = node) do
    source_id = node["original_id"] || node[:original_id] || node["id"] || node[:id]
    type = node["type"] || node[:type]
    data = node["data"] || node[:data]

    if is_integer(source_id) and is_binary(type) and is_map(data) do
      strict_flow_node_reference_specs(%FlowNode{id: source_id, type: type, data: data})
    else
      {:error, {:invalid_variable_reference_source, "flow_node", source_id}}
    end
  end

  defp strict_flow_node_reference_specs(node), do: {:error, {:invalid_variable_reference_source, "flow_node", node}}

  defp strict_snapshot_source_reference_specs(%{} = source) do
    source_type = Map.get(source, :source_type) || Map.get(source, "source_type")
    source_id = Map.get(source, :source_id) || Map.get(source, "source_id")

    strict_snapshot_source_reference_specs(source, source_type, source_id)
  end

  defp strict_snapshot_source_reference_specs(source), do: {:error, {:invalid_variable_reference_source, :mixed, source}}

  defp strict_snapshot_source_reference_specs(source, "flow_node" = source_type, source_id) do
    node = %{
      "original_id" => source_id,
      "type" => Map.get(source, :type) || Map.get(source, "type"),
      "data" => Map.get(source, :data) || Map.get(source, "data")
    }

    tag_snapshot_reference_specs(strict_flow_node_reference_specs(node), source_type)
  end

  defp strict_snapshot_source_reference_specs(source, scene_type, source_id)
       when scene_type in ["scene_pin", "scene_zone"] do
    element = %{
      "original_id" => source_id,
      "action_type" => Map.get(source, :action_type) || Map.get(source, "action_type"),
      "action_data" => Map.get(source, :action_data) || Map.get(source, "action_data") || %{},
      "condition" => Map.get(source, :condition) || Map.get(source, "condition")
    }

    tag_snapshot_reference_specs(strict_scene_element_reference_specs(element, scene_type), scene_type)
  end

  defp strict_snapshot_source_reference_specs(source, "scene_ambient_flow" = source_type, source_id) do
    ambient_flow = %{
      "original_id" => source_id,
      "trigger_type" => Map.get(source, :trigger_type) || Map.get(source, "trigger_type"),
      "trigger_config" => Map.get(source, :trigger_config) || Map.get(source, "trigger_config") || %{}
    }

    tag_snapshot_reference_specs(strict_scene_ambient_flow_reference_specs(ambient_flow), source_type)
  end

  defp strict_snapshot_source_reference_specs(_source, invalid_type, source_id) do
    {:error, {:invalid_variable_reference_source_type, invalid_type, source_id}}
  end

  defp tag_snapshot_reference_specs({:ok, specs}, source_type), do: {:ok, source_type, specs}
  defp tag_snapshot_reference_specs({:error, _reason} = error, _source_type), do: error

  defp strict_dialogue_response_reference_specs(_source_id, []), do: {:ok, []}

  defp strict_dialogue_response_reference_specs(source_id, responses) when is_list(responses) do
    responses
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {response, index}, {:ok, specs} ->
      case strict_dialogue_response_reference_specs(source_id, response, index) do
        {:ok, response_specs} -> {:cont, {:ok, specs ++ response_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp strict_dialogue_response_reference_specs(source_id, responses) do
    malformed_variable_reference("flow_node", source_id, :dialogue_responses, responses)
  end

  defp strict_dialogue_response_reference_specs(source_id, %{} = response, index) do
    with {:ok, condition_specs} <-
           strict_response_condition_specs(source_id, response["condition"], index),
         {:ok, assignment_specs} <- strict_response_assignment_specs(source_id, response, index) do
      {:ok, condition_specs ++ assignment_specs}
    end
  end

  defp strict_dialogue_response_reference_specs(source_id, response, index) do
    malformed_variable_reference("flow_node", source_id, {:dialogue_response, index}, response)
  end

  defp strict_response_condition_specs(_source_id, condition, _index) when condition in [nil, ""], do: {:ok, []}

  defp strict_response_condition_specs(source_id, %{} = condition, _index) do
    strict_condition_reference_specs("flow_node", source_id, condition)
  end

  defp strict_response_condition_specs(source_id, condition, index) when is_binary(condition) do
    case Jason.decode(condition) do
      {:ok, %{} = decoded} -> strict_condition_reference_specs("flow_node", source_id, decoded)
      _invalid -> malformed_variable_reference("flow_node", source_id, {:response_condition, index}, condition)
    end
  end

  defp strict_response_condition_specs(source_id, condition, index) do
    malformed_variable_reference("flow_node", source_id, {:response_condition, index}, condition)
  end

  defp strict_response_assignment_specs(source_id, response, index) do
    case Map.get(response, "instruction_assignments") do
      [_assignment | _rest] = assignments ->
        strict_assignment_list_specs("flow_node", source_id, assignments)

      assignments when assignments in [nil, []] ->
        strict_legacy_response_assignment_specs(source_id, response["instruction"], index)

      invalid ->
        malformed_variable_reference(
          "flow_node",
          source_id,
          {:response_instruction_assignments, index},
          invalid
        )
    end
  end

  defp strict_legacy_response_assignment_specs(_source_id, instruction, _index) when instruction in [nil, ""],
    do: {:ok, []}

  defp strict_legacy_response_assignment_specs(source_id, instruction, index) when is_binary(instruction) do
    case Jason.decode(instruction) do
      {:ok, assignments} when is_list(assignments) ->
        strict_assignment_list_specs("flow_node", source_id, assignments)

      _invalid ->
        malformed_variable_reference("flow_node", source_id, {:response_instruction, index}, instruction)
    end
  end

  defp strict_legacy_response_assignment_specs(source_id, instruction, index) do
    malformed_variable_reference("flow_node", source_id, {:response_instruction, index}, instruction)
  end

  defp strict_scene_ambient_flow_reference_specs(%{
         "original_id" => source_id,
         "trigger_type" => "on_event",
         "trigger_config" => %{} = config
       })
       when is_integer(source_id) do
    strict_qualified_variable_reference_specs(
      "scene_ambient_flow",
      source_id,
      config["variable_ref"],
      :ambient_event_variable_ref
    )
  end

  defp strict_scene_ambient_flow_reference_specs(%{"original_id" => source_id, "trigger_type" => trigger_type})
       when is_integer(source_id) and is_binary(trigger_type), do: {:ok, []}

  defp strict_scene_ambient_flow_reference_specs(ambient_flow) do
    source_id = if is_map(ambient_flow), do: ambient_flow["original_id"], else: ambient_flow
    {:error, {:invalid_variable_reference_source, "scene_ambient_flow", source_id}}
  end

  defp strict_scene_element_reference_specs(
         %{id: source_id, action_data: action_data, condition: condition} = element,
         source_type
       )
       when is_integer(source_id) and is_map(action_data) do
    with {:ok, action_specs} <- strict_scene_action_reference_specs(element, source_type),
         {:ok, condition_specs} <-
           strict_condition_reference_specs(
             source_type,
             source_id,
             condition
           ) do
      {:ok, action_specs ++ condition_specs}
    end
  end

  defp strict_scene_element_reference_specs(%{} = element, source_type) do
    source_id =
      Map.get(element, :id) || Map.get(element, "original_id") ||
        Map.get(element, :original_id) || Map.get(element, "id")

    if is_integer(source_id) do
      normalized = %{
        id: source_id,
        action_type: Map.get(element, :action_type) || Map.get(element, "action_type"),
        action_data: Map.get(element, :action_data) || Map.get(element, "action_data") || %{},
        condition: Map.get(element, :condition) || Map.get(element, "condition")
      }

      strict_scene_element_reference_specs(normalized, source_type)
    else
      {:error, {:invalid_variable_reference_source, source_type, source_id}}
    end
  end

  defp strict_scene_element_reference_specs(element, source_type),
    do: {:error, {:invalid_variable_reference_source, source_type, element}}

  defp strict_scene_action_reference_specs(element, source_type) do
    case element.action_type do
      "action" ->
        strict_assignment_list_specs(
          source_type,
          element.id,
          Map.get(element.action_data, "assignments", [])
        )

      "display" ->
        strict_qualified_variable_reference_specs(
          source_type,
          element.id,
          element.action_data["variable_ref"],
          :display_variable_ref
        )

      "collection" ->
        strict_collection_item_reference_specs(
          source_type,
          element.id,
          Map.get(element.action_data, "items")
        )

      _other ->
        {:ok, []}
    end
  end

  defp strict_collection_item_reference_specs(source_type, source_id, items) when is_list(items) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, specs} ->
      case strict_collection_item_reference_specs(source_type, source_id, item, index) do
        {:ok, item_specs} -> {:cont, {:ok, specs ++ item_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp strict_collection_item_reference_specs(source_type, source_id, items) do
    malformed_variable_reference(source_type, source_id, :collection_items, items)
  end

  defp strict_collection_item_reference_specs(source_type, source_id, %{} = item, index) do
    with {:ok, condition_specs} <-
           strict_collection_item_condition_specs(
             source_type,
             source_id,
             Map.get(item, "condition"),
             index
           ),
         {:ok, instruction_specs} <-
           strict_collection_item_instruction_specs(
             source_type,
             source_id,
             Map.get(item, "instruction"),
             index
           ) do
      {:ok, condition_specs ++ instruction_specs}
    end
  end

  defp strict_collection_item_reference_specs(source_type, source_id, item, index) do
    malformed_variable_reference(source_type, source_id, {:collection_item, index}, item)
  end

  defp strict_collection_item_condition_specs(_source_type, _source_id, nil, _index), do: {:ok, []}

  defp strict_collection_item_condition_specs(_source_type, _source_id, condition, _index)
       when is_map(condition) and map_size(condition) == 0, do: {:ok, []}

  defp strict_collection_item_condition_specs(source_type, source_id, condition, index) do
    case strict_condition_reference_specs(source_type, source_id, condition) do
      {:error, {:malformed_variable_reference, ^source_type, ^source_id, :condition, _value}} ->
        malformed_variable_reference(
          source_type,
          source_id,
          {:collection_item_condition, index},
          condition
        )

      result ->
        result
    end
  end

  defp strict_collection_item_instruction_specs(_source_type, _source_id, nil, _index), do: {:ok, []}

  defp strict_collection_item_instruction_specs(source_type, source_id, %{} = instruction, index) do
    case strict_assignment_list_specs(
           source_type,
           source_id,
           Map.get(instruction, "assignments", [])
         ) do
      {:error, {:malformed_variable_reference, ^source_type, ^source_id, :assignments, _value}} ->
        malformed_variable_reference(
          source_type,
          source_id,
          {:collection_item_assignments, index},
          Map.get(instruction, "assignments")
        )

      result ->
        result
    end
  end

  defp strict_collection_item_instruction_specs(source_type, source_id, instruction, index) do
    malformed_variable_reference(
      source_type,
      source_id,
      {:collection_item_instruction, index},
      instruction
    )
  end

  defp strict_assignment_list_specs(_source_type, _source_id, []), do: {:ok, []}

  defp strict_assignment_list_specs(source_type, source_id, assignments) when is_list(assignments) do
    Enum.reduce_while(assignments, {:ok, []}, fn assignment, {:ok, specs} ->
      case strict_assignment_reference_specs(
             source_type,
             source_id,
             assignment
           ) do
        {:ok, assignment_specs} -> {:cont, {:ok, specs ++ assignment_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp strict_assignment_list_specs(source_type, source_id, assignments) do
    malformed_variable_reference(source_type, source_id, :assignments, assignments)
  end

  defp strict_assignment_reference_specs(source_type, source_id, %{} = assignment) do
    with {:ok, write_spec} <-
           strict_required_reference_spec(
             source_type,
             source_id,
             "write",
             assignment["sheet"],
             assignment["variable"],
             :assignment_target
           ),
         {:ok, read_specs} <-
           strict_assignment_read_specs(source_type, source_id, assignment) do
      {:ok, [write_spec | read_specs]}
    end
  end

  defp strict_assignment_reference_specs(source_type, source_id, assignment) do
    malformed_variable_reference(source_type, source_id, :assignment, assignment)
  end

  defp strict_assignment_read_specs(source_type, source_id, %{"value_type" => "variable_ref"} = assignment) do
    case strict_required_reference_spec(
           source_type,
           source_id,
           "read",
           assignment["value_sheet"],
           assignment["value"],
           :assignment_value
         ) do
      {:ok, spec} -> {:ok, [spec]}
      {:error, _reason} = error -> error
    end
  end

  defp strict_assignment_read_specs(_source_type, _source_id, _assignment), do: {:ok, []}

  defp strict_condition_reference_specs(_source_type, _source_id, nil), do: {:ok, []}

  defp strict_condition_reference_specs(source_type, source_id, %{} = condition) do
    case Condition.validate(condition) do
      {:ok, valid_condition} ->
        valid_condition
        |> Condition.extract_all_rules()
        |> strict_condition_rule_specs(source_type, source_id)

      {:error, _reason} ->
        malformed_variable_reference(source_type, source_id, :condition, condition)
    end
  end

  defp strict_condition_reference_specs(source_type, source_id, condition) do
    malformed_variable_reference(source_type, source_id, :condition, condition)
  end

  defp strict_condition_rule_specs(rules, source_type, source_id) do
    Enum.reduce_while(rules, {:ok, []}, fn rule, {:ok, specs} ->
      strict_condition_rule_spec(rule, specs, source_type, source_id)
    end)
  end

  defp strict_condition_rule_spec(rule, specs, source_type, source_id) do
    case strict_required_reference_spec(
           source_type,
           source_id,
           "read",
           rule["sheet"],
           rule["variable"],
           :condition_rule
         ) do
      {:ok, spec} -> {:cont, {:ok, [spec | specs]}}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp strict_required_reference_spec(source_type, source_id, kind, sheet_shortcut, variable_name, context) do
    case reference_specs(source_id, kind, sheet_shortcut, variable_name) do
      [spec] -> {:ok, spec}
      [] -> malformed_variable_reference(source_type, source_id, context, {sheet_shortcut, variable_name})
    end
  end

  defp strict_qualified_variable_reference_specs(source_type, source_id, value, context) when is_binary(value) do
    case qualified_reference_specs(source_id, "read", value) do
      [spec] -> {:ok, [spec]}
      [] -> malformed_variable_reference(source_type, source_id, context, value)
    end
  end

  defp strict_qualified_variable_reference_specs(source_type, source_id, value, context) do
    malformed_variable_reference(source_type, source_id, context, value)
  end

  defp malformed_variable_reference(source_type, source_id, context, value) do
    {:error, {:malformed_variable_reference, source_type, source_id, context, value}}
  end

  defp validate_resolvable_specs(_project_id, _source_type, []), do: :ok

  defp validate_resolvable_specs(project_id, source_type, specs) do
    resolved_block_ids = resolve_reference_block_ids(project_id, specs)

    case Enum.find(specs, &(not Map.has_key?(resolved_block_ids, &1.resolution_key))) do
      nil ->
        :ok

      spec ->
        source_type = Map.get(spec, :source_type, source_type)

        {:error,
         {:unresolved_variable_reference, source_type, spec.source_id, spec.kind, spec.source_sheet, spec.source_variable}}
    end
  end

  defp flow_node_reference_specs(%FlowNode{id: node_id, type: "instruction", data: data}) do
    data
    |> Map.get("assignments", [])
    |> list_value()
    |> Enum.flat_map(&assignment_reference_specs(node_id, &1))
  end

  defp flow_node_reference_specs(%FlowNode{id: node_id, type: "condition", data: data}) do
    data
    |> Map.get("condition")
    |> Condition.extract_all_rules()
    |> Enum.flat_map(fn rule ->
      reference_specs(
        node_id,
        "read",
        rule["sheet"],
        rule["variable"]
      )
    end)
  end

  defp flow_node_reference_specs(%FlowNode{id: node_id, type: "dialogue", data: data}) do
    data
    |> Map.get("responses", [])
    |> list_value()
    |> Enum.flat_map(&dialogue_response_reference_specs(node_id, &1))
  end

  defp flow_node_reference_specs(%FlowNode{}), do: []

  defp dialogue_response_reference_specs(node_id, %{} = response) do
    response_condition_reference_specs(node_id, response["condition"]) ++
      response_assignment_reference_specs(node_id, response)
  end

  defp dialogue_response_reference_specs(_node_id, _response), do: []

  defp response_condition_reference_specs(node_id, condition) when is_binary(condition) do
    condition
    |> Condition.parse()
    |> condition_reference_specs(node_id)
  end

  defp response_condition_reference_specs(node_id, condition), do: condition_reference_specs(condition, node_id)

  defp condition_reference_specs(condition, node_id) do
    condition
    |> Condition.extract_all_rules()
    |> Enum.flat_map(fn rule ->
      reference_specs(node_id, "read", rule["sheet"], rule["variable"])
    end)
  end

  defp response_assignment_reference_specs(node_id, response) do
    response
    |> response_assignments()
    |> list_value()
    |> Enum.flat_map(&assignment_reference_specs(node_id, &1))
  end

  defp response_assignments(%{"instruction_assignments" => [_assignment | _rest] = assignments}), do: assignments
  defp response_assignments(%{"instruction_assignments" => invalid}) when invalid not in [nil, []], do: invalid
  defp response_assignments(response), do: decode_legacy_response_assignments(response["instruction"])

  defp decode_legacy_response_assignments(instruction) when instruction in [nil, ""], do: []

  defp decode_legacy_response_assignments(instruction) when is_binary(instruction) do
    case Jason.decode(instruction) do
      {:ok, assignments} when is_list(assignments) -> assignments
      _invalid -> []
    end
  end

  defp decode_legacy_response_assignments(_instruction), do: []

  defp assignment_reference_specs(node_id, assignment) when is_map(assignment) do
    write_specs =
      reference_specs(
        node_id,
        "write",
        assignment["sheet"],
        assignment["variable"]
      )

    read_specs =
      if assignment["value_type"] == "variable_ref" do
        reference_specs(
          node_id,
          "read",
          assignment["value_sheet"],
          assignment["value"]
        )
      else
        []
      end

    write_specs ++ read_specs
  end

  defp assignment_reference_specs(_node_id, _assignment), do: []

  defp reference_specs(node_id, kind, sheet_shortcut, variable_name)
       when is_binary(sheet_shortcut) and sheet_shortcut != "" and is_binary(variable_name) and variable_name != "" do
    [
      %{
        source_id: node_id,
        kind: kind,
        source_sheet: sheet_shortcut,
        source_variable: variable_name,
        resolution_key: variable_resolution_key(sheet_shortcut, variable_name)
      }
    ]
  end

  defp reference_specs(_node_id, _kind, _sheet_shortcut, _variable_name), do: []

  defp qualified_reference_specs(source_id, kind, qualified_ref) when is_binary(qualified_ref) and qualified_ref != "" do
    if String.trim(qualified_ref) == "" do
      []
    else
      {source_sheet, source_variable} = qualified_reference_error_parts(qualified_ref)

      [
        %{
          source_id: source_id,
          kind: kind,
          source_sheet: source_sheet,
          source_variable: source_variable,
          resolution_key: {:qualified, qualified_ref}
        }
      ]
    end
  end

  defp qualified_reference_specs(_source_id, _kind, _qualified_ref), do: []

  defp qualified_reference_error_parts(qualified_ref) do
    parts = String.split(qualified_ref, ".")

    case List.pop_at(parts, -1) do
      {variable_name, sheet_parts} when sheet_parts != [] -> {Enum.join(sheet_parts, "."), variable_name}
      _invalid -> {qualified_ref, qualified_ref}
    end
  end

  defp variable_resolution_key(sheet_shortcut, variable_name) do
    case String.split(variable_name, ".", parts: 3) do
      [table_name, row_slug, column_slug] ->
        {:table, sheet_shortcut, table_name, row_slug, column_slug}

      _regular_variable ->
        {:regular, sheet_shortcut, variable_name}
    end
  end

  defp resolve_reference_block_ids(project_id, specs) do
    resolution_keys = MapSet.new(specs, & &1.resolution_key)

    regular_keys =
      for {:regular, _sheet, _variable} = key <- resolution_keys,
          do: key

    table_keys =
      for {:table, _sheet, _table, _row, _column} = key <-
            resolution_keys,
          do: key

    qualified_refs =
      for {:qualified, qualified_ref} <- resolution_keys,
          do: qualified_ref

    project_id
    |> resolve_regular_block_ids(regular_keys)
    |> Map.merge(resolve_table_block_ids(project_id, table_keys))
    |> Map.merge(resolve_qualified_reference_definitions(project_id, qualified_refs))
  end

  defp resolve_qualified_reference_definitions(_project_id, []), do: %{}

  defp resolve_qualified_reference_definitions(project_id, qualified_refs) do
    definitions =
      qualified_regular_reference_definitions(project_id, qualified_refs) ++
        qualified_table_reference_definitions(project_id, qualified_refs)

    Map.new(definitions, fn {qualified_ref, source_sheet, source_variable, block_id} ->
      {{:qualified, qualified_ref}, %{block_id: block_id, source_sheet: source_sheet, source_variable: source_variable}}
    end)
  end

  defp qualified_regular_reference_definitions(project_id, qualified_refs) do
    Repo.all(
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
            is_nil(block.deleted_at) and
            block.type in ^@regular_variable_types and
            block.is_constant == false and
            not is_nil(block.variable_name) and block.variable_name != "" and
            fragment(
              "COALESCE(?, CAST(? AS TEXT)) || '.' || ?",
              sheet.shortcut,
              sheet.id,
              block.variable_name
            ) in ^qualified_refs,
        select: {
          fragment(
            "COALESCE(?, CAST(? AS TEXT)) || '.' || ?",
            sheet.shortcut,
            sheet.id,
            block.variable_name
          ),
          coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
          block.variable_name,
          block.id
        }
      )
    )
  end

  defp qualified_table_reference_definitions(project_id, qualified_refs) do
    from(column in TableColumn, as: :column)
    |> join(:inner, [column: column], block in Block,
      as: :block,
      on: block.id == column.block_id
    )
    |> join(:inner, [block: block], sheet in Sheet,
      as: :sheet,
      on: sheet.id == block.sheet_id
    )
    |> join(:inner, [block: block], row in TableRow,
      as: :row,
      on: row.block_id == block.id
    )
    |> where(
      [column: column, block: block, sheet: sheet, row: row],
      sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
        is_nil(block.deleted_at) and not is_nil(block.variable_name) and
        block.variable_name != "" and
        fragment(
          "COALESCE(?, CAST(? AS TEXT)) || '.' || ? || '.' || ? || '.' || ?",
          sheet.shortcut,
          sheet.id,
          block.variable_name,
          row.slug,
          column.slug
        ) in ^qualified_refs
    )
    |> filter_table_variable_targets()
    |> select([column: column, block: block, sheet: sheet, row: row], {
      fragment(
        "COALESCE(?, CAST(? AS TEXT)) || '.' || ? || '.' || ? || '.' || ?",
        sheet.shortcut,
        sheet.id,
        block.variable_name,
        row.slug,
        column.slug
      ),
      coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
      fragment("? || '.' || ? || '.' || ?", block.variable_name, row.slug, column.slug),
      block.id
    })
    |> Repo.all()
  end

  defp filter_table_variable_targets(query) do
    from([column: column, block: block] in query,
      where:
        block.type == "table" and
          column.type in ^@table_variable_types and
          (column.is_constant == false or
             column.type in ^@constant_table_variable_types)
    )
  end

  defp resolve_regular_block_ids(_project_id, []), do: %{}

  defp resolve_regular_block_ids(project_id, keys) do
    shortcuts =
      keys
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()

    variable_names =
      keys
      |> Enum.map(&elem(&1, 2))
      |> Enum.uniq()

    from(block in Block,
      join: sheet in Sheet,
      on: sheet.id == block.sheet_id,
      where:
        sheet.project_id == ^project_id and
          sheet.shortcut in ^shortcuts and
          block.variable_name in ^variable_names and
          block.type in ^@regular_variable_types and
          block.is_constant == false and
          is_nil(sheet.deleted_at) and
          is_nil(block.deleted_at),
      select: {sheet.shortcut, block.variable_name, block.id}
    )
    |> Repo.all()
    |> Map.new(fn {shortcut, variable_name, block_id} ->
      {{:regular, shortcut, variable_name}, block_id}
    end)
  end

  defp resolve_table_block_ids(_project_id, []), do: %{}

  defp resolve_table_block_ids(project_id, keys) do
    shortcuts = keys |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    table_names = keys |> Enum.map(&elem(&1, 2)) |> Enum.uniq()
    row_slugs = keys |> Enum.map(&elem(&1, 3)) |> Enum.uniq()
    column_slugs = keys |> Enum.map(&elem(&1, 4)) |> Enum.uniq()

    from(block in Block, as: :block)
    |> join(:inner, [block: block], sheet in Sheet,
      as: :sheet,
      on: sheet.id == block.sheet_id
    )
    |> join(:inner, [block: block], row in TableRow,
      as: :row,
      on: row.block_id == block.id
    )
    |> join(:inner, [block: block], column in TableColumn,
      as: :column,
      on: column.block_id == block.id
    )
    |> where(
      [block: block, sheet: sheet, row: row, column: column],
      sheet.project_id == ^project_id and
        sheet.shortcut in ^shortcuts and
        block.variable_name in ^table_names and
        row.slug in ^row_slugs and
        column.slug in ^column_slugs and
        is_nil(sheet.deleted_at) and
        is_nil(block.deleted_at)
    )
    |> filter_table_variable_targets()
    |> select([block: block, sheet: sheet, row: row, column: column], {
      sheet.shortcut,
      block.variable_name,
      row.slug,
      column.slug,
      block.id
    })
    |> Repo.all()
    |> Map.new(fn {shortcut, table_name, row_slug, column_slug, block_id} ->
      {{:table, shortcut, table_name, row_slug, column_slug}, block_id}
    end)
  end

  defp expected_flow_node_reference_sets(specs, resolved_block_ids) do
    specs
    |> Enum.group_by(& &1.source_id)
    |> Map.new(fn {source_id, source_specs} ->
      references =
        source_specs
        |> Enum.flat_map(&resolved_flow_node_reference(&1, resolved_block_ids))
        |> Enum.uniq_by(fn reference ->
          {
            reference.block_id,
            reference.kind,
            reference.source_variable
          }
        end)
        |> MapSet.new(fn reference ->
          {
            reference.block_id,
            reference.kind,
            reference.source_sheet,
            reference.source_variable,
            source_id
          }
        end)

      {source_id, references}
    end)
  end

  defp resolved_flow_node_reference(spec, resolved_block_ids) do
    case Map.fetch(resolved_block_ids, spec.resolution_key) do
      {:ok, %{block_id: block_id, source_sheet: source_sheet, source_variable: source_variable}} ->
        [
          %{
            block_id: block_id,
            kind: spec.kind,
            source_sheet: source_sheet,
            source_variable: source_variable
          }
        ]

      {:ok, block_id} ->
        [
          %{
            block_id: block_id,
            kind: spec.kind,
            source_sheet: spec.source_sheet,
            source_variable: spec.source_variable
          }
        ]

      :error ->
        []
    end
  end

  defp extract_flow_node_variable_refs(%FlowNode{} = node) do
    case get_project_id(node.flow_id) do
      nil ->
        []

      project_id ->
        specs = flow_node_reference_specs(node)
        resolved_block_ids = resolve_reference_block_ids(project_id, specs)
        Enum.flat_map(specs, &resolved_flow_node_reference(&1, resolved_block_ids))
    end
  end

  defp actual_flow_node_reference_sets([]), do: %{}

  defp actual_flow_node_reference_sets(node_ids) do
    from(reference in VariableReference,
      where:
        reference.source_type == "flow_node" and
          reference.source_id in ^node_ids,
      select: {
        reference.source_id,
        reference.block_id,
        reference.kind,
        reference.source_sheet,
        reference.source_variable,
        reference.flow_node_id
      }
    )
    |> Repo.all()
    |> Enum.reduce(
      %{},
      fn
        {
          source_id,
          block_id,
          kind,
          source_sheet,
          source_variable,
          flow_node_id
        },
        references ->
          reference =
            {
              block_id,
              kind,
              source_sheet,
              source_variable,
              flow_node_id
            }

          Map.update(
            references,
            source_id,
            MapSet.new([reference]),
            &MapSet.put(&1, reference)
          )
      end
    )
  end

  defp list_value(value) when is_list(value), do: value
  defp list_value(_value), do: []

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
    Repo.one(from(f in Flow, where: f.id == ^flow_id, select: f.project_id))
  end

  defp resolve_block(project_id, sheet_shortcut, variable_name)
       when is_binary(sheet_shortcut) and sheet_shortcut != "" and is_binary(variable_name) and variable_name != "" do
    case String.split(variable_name, ".", parts: 3) do
      [table_name, row_slug, column_slug] ->
        resolve_table_block(project_id, sheet_shortcut, table_name, row_slug, column_slug)

      _ ->
        resolve_regular_block(project_id, sheet_shortcut, variable_name)
    end
  end

  defp resolve_block(_, _, _), do: nil

  defp resolve_regular_block(project_id, sheet_shortcut, variable_name) do
    key = {:regular, sheet_shortcut, variable_name}
    project_id |> resolve_regular_block_ids([key]) |> Map.get(key)
  end

  defp resolve_table_block(project_id, sheet_shortcut, table_name, row_slug, column_slug) do
    key = {:table, sheet_shortcut, table_name, row_slug, column_slug}
    project_id |> resolve_table_block_ids([key]) |> Map.get(key)
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
          condition
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

  defp extract_ambient_flow_variable_refs(
         %{trigger_type: "on_event", trigger_config: %{"variable_ref" => variable_ref}},
         project_id
       ) do
    resolve_display_variable_ref(project_id, variable_ref)
  end

  defp extract_ambient_flow_variable_refs(_ambient_flow, _project_id), do: []

  # Shared extraction for action_type + action_data (zones and pins)
  defp extract_action_variable_refs(element, project_id) do
    case Map.get(element, :action_type) do
      "action" ->
        assignments = (Map.get(element, :action_data) || %{})["assignments"] || []
        Enum.flat_map(assignments, &extract_assignment_refs(&1, project_id))

      "display" ->
        variable_ref = (Map.get(element, :action_data) || %{})["variable_ref"]
        resolve_display_variable_ref(project_id, variable_ref)

      "collection" ->
        element
        |> Map.get(:action_data, %{})
        |> Map.get("items", [])
        |> list_value()
        |> Enum.flat_map(&extract_collection_item_variable_refs(&1, project_id))

      _ ->
        []
    end
  end

  defp extract_collection_item_variable_refs(%{} = item, project_id) do
    condition_refs = extract_condition_refs(Map.get(item, "condition"), project_id)

    assignment_refs =
      item
      |> Map.get("instruction")
      |> collection_instruction_assignments()
      |> Enum.flat_map(&extract_assignment_refs(&1, project_id))

    condition_refs ++ assignment_refs
  end

  defp extract_collection_item_variable_refs(_item, _project_id), do: []

  defp collection_instruction_assignments(%{} = instruction) do
    instruction
    |> Map.get("assignments", [])
    |> list_value()
  end

  defp collection_instruction_assignments(_instruction), do: []

  # Shared extraction for condition read refs (zones and pins)
  defp extract_condition_variable_refs(element, project_id) do
    element
    |> Map.get(:condition)
    |> extract_condition_refs(project_id)
  end

  defp extract_condition_refs(condition, project_id) do
    if is_nil(condition) do
      []
    else
      rules = Condition.extract_all_rules(condition)
      Enum.flat_map(rules, &resolve_rule_read_ref(&1, project_id))
    end
  end

  defp resolve_display_variable_ref(_project_id, nil), do: []
  defp resolve_display_variable_ref(_project_id, ""), do: []

  defp resolve_display_variable_ref(project_id, variable_ref) when is_binary(variable_ref) do
    specs = qualified_reference_specs(0, "read", variable_ref)
    resolved_block_ids = resolve_reference_block_ids(project_id, specs)
    Enum.flat_map(specs, &resolved_flow_node_reference(&1, resolved_block_ids))
  end

  defp resolve_display_variable_ref(_project_id, _variable_ref), do: []

  defp replace_references(source_type, source_id, refs, opts \\ []) do
    result =
      Repo.transaction(fn ->
        Repo.delete_all(
          from(vr in VariableReference,
            where: vr.source_type == ^source_type and vr.source_id == ^source_id
          )
        )

        unique_refs = Enum.uniq_by(refs, fn ref -> {ref.block_id, ref.kind, ref.source_variable} end)
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

        insert_reference_entries(entries)
      end)

    case result do
      {:ok, :ok} ->
        :ok

      {:error, reason} ->
        {:error, {:variable_reference_write_failed, source_type, source_id, reason}}
    end
  end

  defp restore_missing_flow_node_references(%FlowNode{} = node) do
    refs = extract_flow_node_variable_refs(node)

    insert_missing_references("flow_node", node.id, refs, flow_node_id: node.id)
  end

  defp restore_missing_scene_pin_references(pin, project_id) do
    insert_missing_references(
      "scene_pin",
      pin.id,
      extract_pin_variable_refs(pin, project_id)
    )
  end

  defp restore_missing_scene_zone_references(zone, project_id) do
    insert_missing_references(
      "scene_zone",
      zone.id,
      extract_zone_variable_refs(zone, project_id)
    )
  end

  defp restore_missing_scene_ambient_flow_references(ambient_flow, project_id) do
    insert_missing_references(
      "scene_ambient_flow",
      ambient_flow.id,
      extract_ambient_flow_variable_refs(ambient_flow, project_id)
    )
  end

  defp insert_missing_references(source_type, source_id, refs, opts \\ []) do
    entries = reference_entries(source_type, source_id, refs, opts)

    case Repo.insert_all(VariableReference, entries, on_conflict: :nothing) do
      {count, _} when count >= 0 and count <= length(entries) ->
        :ok

      result ->
        {:error, {:variable_reference_additive_insert_count_mismatch, source_type, source_id, length(entries), result}}
    end
  end

  defp reference_entries(source_type, source_id, refs, opts) do
    now = TimeHelpers.now()

    refs
    |> Enum.uniq_by(fn ref -> {ref.block_id, ref.kind, ref.source_variable} end)
    |> Enum.map(fn ref ->
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
  end

  defp insert_reference_entries([]), do: :ok

  defp insert_reference_entries(entries) do
    case Repo.insert_all(VariableReference, entries, on_conflict: :nothing) do
      {count, _} when count == length(entries) ->
        :ok

      result ->
        Repo.rollback({:variable_reference_insert_count_mismatch, length(entries), result})
    end
  end

  defp active_flow_nodes_query(project_id) do
    from(node in FlowNode,
      join: flow in Flow,
      on: flow.id == node.flow_id,
      where:
        flow.project_id == ^project_id and is_nil(flow.deleted_at) and
          is_nil(node.deleted_at)
    )
  end

  defp active_scene_pins_query(project_id) do
    from(pin in ScenePin,
      join: scene in Scene,
      on: scene.id == pin.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at)
    )
  end

  defp active_scene_zones_query(project_id) do
    from(zone in SceneZone,
      join: scene in Scene,
      on: scene.id == zone.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at)
    )
  end

  defp active_scene_ambient_flows_query(project_id) do
    from(ambient_flow in SceneAmbientFlow,
      join: scene in Scene,
      on: scene.id == ambient_flow.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at)
    )
  end

  defp rebuild_sources(query, project_id, source_type, update_fun, after_id \\ 0) do
    sources =
      Repo.all(
        from(source in query,
          where: source.id > ^after_id,
          order_by: [asc: source.id],
          limit: ^@rebuild_batch_size
        )
      )

    case rebuild_source_batch(sources, project_id, source_type, update_fun) do
      :ok when length(sources) == @rebuild_batch_size ->
        rebuild_sources(query, project_id, source_type, update_fun, List.last(sources).id)

      result ->
        result
    end
  end

  defp rebuild_source_batch(sources, project_id, source_type, update_fun) do
    Enum.reduce_while(sources, :ok, fn source, :ok ->
      case update_fun.(source) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt,
           {:error,
            {:project_variable_reference_rebuild_failed,
             %{
               project_id: project_id,
               source_type: source_type,
               source_id: source.id,
               reason: reason
             }}}}

        result ->
          {:halt,
           {:error,
            {:project_variable_reference_rebuild_failed,
             %{
               project_id: project_id,
               source_type: source_type,
               source_id: source.id,
               reason: {:unexpected_result, result}
             }}}}
      end
    end)
  end
end
