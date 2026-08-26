defmodule Storyarn.Sheets.References.Queries.VariableUsage do
  @moduledoc """
  Sheets-owned read model for tracked variable usages and staleness.

  It keeps editor safeguards, health batching, and the Sheet references panel
  independent from the contexts that write the shared reference projection.
  """

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.References.Data.FlowNodeRecord
  alias Storyarn.Sheets.References.Data.FlowRecord
  alias Storyarn.Sheets.References.Data.SceneAmbientFlowRecord
  alias Storyarn.Sheets.References.Data.ScenePinRecord
  alias Storyarn.Sheets.References.Data.SceneRecord
  alias Storyarn.Sheets.References.Data.SceneZoneRecord
  alias Storyarn.Sheets.References.Data.VariableReferenceRecord
  alias Storyarn.Sheets.Sheet

  require Storyarn.Sheets.Logic

  @stale_variable_reference_sql """
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
  """

  defmacrop stale_variable_reference(block, reference, sheet) do
    sql = @stale_variable_reference_sql

    quote do
      not Storyarn.Sheets.Logic.authoritative_namespace_owner?(unquote(sheet)) or
        fragment(
          unquote(sql),
          unquote(block).type,
          unquote(reference).source_sheet,
          coalesce(
            unquote(sheet).shortcut,
            fragment("CAST(? AS TEXT)", unquote(sheet).id)
          ),
          unquote(block).id,
          unquote(reference).source_variable,
          unquote(block).variable_name,
          unquote(reference).source_sheet,
          coalesce(
            unquote(sheet).shortcut,
            fragment("CAST(? AS TEXT)", unquote(sheet).id)
          ),
          unquote(reference).source_variable,
          unquote(block).variable_name
        )
    end
  end

  @spec count_variable_usage(integer()) :: map()
  def count_variable_usage(block_id) do
    from(reference in VariableReferenceRecord,
      where: reference.block_id == ^block_id,
      group_by: reference.kind,
      select: {reference.kind, count(reference.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @spec count_stale_references([integer()], integer()) ::
          %{integer() => non_neg_integer()}
  def count_stale_references([], _project_id), do: %{}

  def count_stale_references(block_ids, project_id) do
    block_ids
    |> stale_reference_count_query(project_id)
    |> Repo.all()
    |> Map.new()
  end

  @spec check_stale_references(integer(), integer()) :: [map()]
  def check_stale_references(block_id, project_id) do
    check_stale_flow_node_references(block_id, project_id) ++
      check_stale_scene_zone_references(block_id, project_id) ++
      check_stale_scene_pin_references(block_id, project_id) ++
      check_stale_scene_ambient_flow_references(block_id, project_id)
  end

  @doc "Returns only stale/current Flow-node usages for one Sheet variable."
  @spec check_stale_flow_node_references(integer(), integer()) :: [map()]
  def check_stale_flow_node_references(block_id, project_id) do
    Repo.all(
      from(reference in VariableReferenceRecord,
        join: node in FlowNodeRecord,
        on: reference.source_type == "flow_node" and node.id == reference.source_id,
        join: flow in FlowRecord,
        on: flow.id == node.flow_id,
        join: block in Block,
        on: block.id == reference.block_id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: reference.block_id == ^block_id,
        where: flow.project_id == ^project_id,
        where: is_nil(flow.deleted_at),
        where: is_nil(node.deleted_at),
        where: is_nil(sheet.deleted_at),
        where: is_nil(block.deleted_at),
        select: %{
          source_type: reference.source_type,
          kind: reference.kind,
          flow_id: flow.id,
          flow_name: flow.name,
          flow_shortcut: flow.shortcut,
          node_id: node.id,
          node_type: node.type,
          node_data: node.data,
          source_sheet: reference.source_sheet,
          source_variable: reference.source_variable,
          stale: stale_variable_reference(block, reference, sheet)
        },
        order_by: [asc: reference.kind, asc: flow.name]
      )
    )
  end

  defp stale_reference_count_query(block_ids, project_id) do
    VariableReferenceRecord
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
      left_join: zone in SceneZoneRecord,
      as: :zone,
      on: reference.source_type == "scene_zone" and zone.id == reference.source_id,
      left_join: zone_scene in SceneRecord,
      as: :zone_scene,
      on: zone_scene.id == zone.scene_id,
      left_join: pin in ScenePinRecord,
      as: :pin,
      on: reference.source_type == "scene_pin" and pin.id == reference.source_id,
      left_join: pin_scene in SceneRecord,
      as: :pin_scene,
      on: pin_scene.id == pin.scene_id,
      left_join: ambient_flow in SceneAmbientFlowRecord,
      as: :ambient_flow,
      on:
        reference.source_type == "scene_ambient_flow" and
          ambient_flow.id == reference.source_id,
      left_join: ambient_scene in SceneRecord,
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
      where: stale_variable_reference(block, reference, sheet)
    )
  end

  defp group_stale_reference_counts(query) do
    from([reference: reference] in query,
      group_by: reference.block_id,
      select: {reference.block_id, count(reference.id)}
    )
  end

  defp check_stale_scene_zone_references(block_id, project_id) do
    Repo.all(
      from(reference in VariableReferenceRecord,
        join: zone in SceneZoneRecord,
        on: reference.source_type == "scene_zone" and zone.id == reference.source_id,
        join: scene in SceneRecord,
        on: scene.id == zone.scene_id,
        join: block in Block,
        on: block.id == reference.block_id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: reference.block_id == ^block_id,
        where: scene.project_id == ^project_id,
        where: is_nil(scene.deleted_at),
        where: is_nil(sheet.deleted_at),
        where: is_nil(block.deleted_at),
        select: %{
          source_type: reference.source_type,
          kind: reference.kind,
          scene_id: scene.id,
          scene_name: scene.name,
          zone_id: zone.id,
          zone_name: zone.name,
          zone_action_data: zone.action_data,
          source_sheet: reference.source_sheet,
          source_variable: reference.source_variable,
          stale: stale_variable_reference(block, reference, sheet)
        },
        order_by: [asc: reference.kind, asc: scene.name]
      )
    )
  end

  defp check_stale_scene_pin_references(block_id, project_id) do
    Repo.all(
      from(reference in VariableReferenceRecord,
        join: pin in ScenePinRecord,
        on: reference.source_type == "scene_pin" and pin.id == reference.source_id,
        join: scene in SceneRecord,
        on: scene.id == pin.scene_id,
        join: block in Block,
        on: block.id == reference.block_id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: reference.block_id == ^block_id,
        where: scene.project_id == ^project_id,
        where: is_nil(scene.deleted_at),
        where: is_nil(sheet.deleted_at),
        where: is_nil(block.deleted_at),
        select: %{
          source_type: reference.source_type,
          kind: reference.kind,
          scene_id: scene.id,
          scene_name: scene.name,
          pin_id: pin.id,
          pin_label: pin.label,
          source_sheet: reference.source_sheet,
          source_variable: reference.source_variable,
          stale: stale_variable_reference(block, reference, sheet)
        },
        order_by: [asc: reference.kind, asc: scene.name]
      )
    )
  end

  defp check_stale_scene_ambient_flow_references(block_id, project_id) do
    Repo.all(
      from(reference in VariableReferenceRecord,
        join: ambient_flow in SceneAmbientFlowRecord,
        on:
          reference.source_type == "scene_ambient_flow" and
            ambient_flow.id == reference.source_id,
        join: scene in SceneRecord,
        on: scene.id == ambient_flow.scene_id,
        join: flow in FlowRecord,
        on: flow.id == ambient_flow.flow_id and flow.project_id == scene.project_id,
        join: block in Block,
        on: block.id == reference.block_id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: reference.block_id == ^block_id,
        where: scene.project_id == ^project_id,
        where: is_nil(scene.deleted_at),
        where: is_nil(sheet.deleted_at),
        where: is_nil(block.deleted_at),
        select: %{
          source_type: reference.source_type,
          kind: reference.kind,
          scene_id: scene.id,
          scene_name: scene.name,
          ambient_flow_id: ambient_flow.id,
          ambient_flow_name: flow.name,
          trigger_config: ambient_flow.trigger_config,
          source_sheet: reference.source_sheet,
          source_variable: reference.source_variable,
          stale: stale_variable_reference(block, reference, sheet)
        },
        order_by: [asc: reference.kind, asc: scene.name, asc: ambient_flow.id]
      )
    )
  end
end
