defmodule Storyarn.Projects.References.VariableReferenceQueries do
  @moduledoc """
  Read-side queries for variable usage and stale-reference detection.

  This module owns no writes. It composes References-owned records and the
  narrower source-specific projections while preserving the existing result
  shapes used by editors and health checks.
  """

  import Ecto.Query

  alias Storyarn.Projects.References.Persistence.BlockRecord, as: Block
  alias Storyarn.Projects.References.Persistence.FlowNodeRecord
  alias Storyarn.Projects.References.Persistence.FlowRecord
  alias Storyarn.Projects.References.Persistence.SceneAmbientFlowRecord, as: SceneAmbientFlow
  alias Storyarn.Projects.References.Persistence.ScenePinRecord, as: ScenePin
  alias Storyarn.Projects.References.Persistence.SceneRecord, as: Scene
  alias Storyarn.Projects.References.Persistence.SceneZoneRecord, as: SceneZone
  alias Storyarn.Projects.References.Persistence.SheetRecord, as: Sheet
  alias Storyarn.Projects.References.VariableNamespaceResolver
  alias Storyarn.Projects.References.VariableProjectionQueries
  alias Storyarn.Projects.References.VariableReference
  alias Storyarn.Repo

  require VariableNamespaceResolver

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
        join: n in FlowNodeRecord,
        on: vr.source_type == "flow_node" and n.id == vr.source_id,
        join: f in FlowRecord,
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
    VariableProjectionQueries.get_scene_zone_variable_usage(block_id, project_id)
  end

  defp get_scene_pin_variable_usage(block_id, project_id) do
    VariableProjectionQueries.get_scene_pin_variable_usage(block_id, project_id)
  end

  defp get_scene_ambient_flow_variable_usage(block_id, project_id) do
    VariableProjectionQueries.get_scene_ambient_flow_variable_usage(block_id, project_id)
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
      left_join: node in FlowNodeRecord,
      as: :node,
      on: reference.source_type == "flow_node" and node.id == reference.source_id,
      left_join: flow in FlowRecord,
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
      on: ambient_scene.id == ambient_flow.scene_id,
      left_join: ambient_target_flow in FlowRecord,
      as: :ambient_target_flow,
      on: ambient_target_flow.id == ambient_flow.flow_id
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
        ambient_scene: ambient_scene,
        ambient_target_flow: ambient_target_flow
      ] in query,
      where:
        fragment(
          """
          (? = 'flow_node' AND ? IS NOT NULL AND ? IS NULL AND ? = ? AND ? IS NULL)
          OR (? = 'scene_zone' AND ? IS NOT NULL AND ? = ? AND ? IS NULL)
          OR (? = 'scene_pin' AND ? IS NOT NULL AND ? = ? AND ? IS NULL)
          OR (? = 'scene_ambient_flow' AND ? IS NOT NULL AND ? = ? AND ? IS NULL AND ? = ?)
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
          ambient_scene.deleted_at,
          ambient_target_flow.project_id,
          ambient_scene.project_id
        )
    )
  end

  defp filter_stale_variable_references(query) do
    from([reference: reference, block: block, sheet: sheet] in query,
      where:
        not VariableNamespaceResolver.authoritative_namespace_owner?(sheet) or
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
            coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
            block.id,
            reference.source_variable,
            block.variable_name,
            reference.source_sheet,
            coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
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

  Returns Flow-node, Scene-zone, Scene-pin, and Scene-ambient-flow sources.
  Each result includes a `:source_type` field to distinguish them.

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
    VariableProjectionQueries.check_stale_flow_node_variable_references(block_id, project_id)
  end

  defp check_stale_scene_zone_references(block_id, project_id) do
    VariableProjectionQueries.check_stale_scene_zone_variable_references(block_id, project_id)
  end

  defp check_stale_scene_pin_references(block_id, project_id) do
    VariableProjectionQueries.check_stale_scene_pin_variable_references(block_id, project_id)
  end

  defp check_stale_scene_ambient_flow_references(block_id, project_id) do
    VariableProjectionQueries.check_stale_scene_ambient_flow_variable_references(
      block_id,
      project_id
    )
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
    VariableProjectionQueries.list_stale_regular_node_ids(flow_id)
  end

  defp list_stale_table_node_ids(flow_id) do
    VariableProjectionQueries.list_stale_table_node_ids(flow_id)
  end

  # -- Private --
end
