defmodule Storyarn.References.VariableProjectionQueries do
  @moduledoc """
  References-owned reads for variable usage, staleness and repair.

  These queries intentionally consume the shared SQL tables through local
  records. Their result shapes preserve the legacy projection contract without
  importing Sheet or Scene schemas and facades.
  """

  import Ecto.Query, warn: false

  alias Storyarn.References.Persistence.BlockRecord
  alias Storyarn.References.Persistence.FlowNodeRecord
  alias Storyarn.References.Persistence.FlowRecord
  alias Storyarn.References.Persistence.SceneAmbientFlowRecord
  alias Storyarn.References.Persistence.ScenePinRecord
  alias Storyarn.References.Persistence.SceneRecord
  alias Storyarn.References.Persistence.SceneZoneRecord
  alias Storyarn.References.Persistence.SheetRecord
  alias Storyarn.References.Persistence.TableColumnRecord
  alias Storyarn.References.Persistence.TableRowRecord
  alias Storyarn.References.VariableNamespaceResolver
  alias Storyarn.References.VariableReference
  alias Storyarn.Repo

  require VariableNamespaceResolver

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
      not VariableNamespaceResolver.authoritative_namespace_owner?(unquote(sheet)) or
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

  @spec get_scene_project_id(integer()) :: integer() | nil
  def get_scene_project_id(scene_id) do
    Repo.one(
      from(scene in SceneRecord,
        where: scene.id == ^scene_id,
        select: scene.project_id
      )
    )
  end

  @spec get_scene_zone_variable_usage(integer(), integer()) :: [map()]
  def get_scene_zone_variable_usage(block_id, project_id) do
    Repo.all(
      from(reference in VariableReference,
        join: zone in SceneZoneRecord,
        on:
          reference.source_type == "scene_zone" and
            zone.id == reference.source_id,
        join: scene in SceneRecord,
        on: scene.id == zone.scene_id,
        where: reference.block_id == ^block_id,
        where: scene.project_id == ^project_id,
        where: is_nil(scene.deleted_at),
        select: %{
          source_type: reference.source_type,
          kind: reference.kind,
          scene_id: scene.id,
          scene_name: scene.name,
          zone_id: zone.id,
          zone_name: zone.name,
          zone_action_data: zone.action_data
        },
        order_by: [asc: reference.kind, asc: scene.name]
      )
    )
  end

  @spec get_scene_pin_variable_usage(integer(), integer()) :: [map()]
  def get_scene_pin_variable_usage(block_id, project_id) do
    Repo.all(
      from(reference in VariableReference,
        join: pin in ScenePinRecord,
        on:
          reference.source_type == "scene_pin" and
            pin.id == reference.source_id,
        join: scene in SceneRecord,
        on: scene.id == pin.scene_id,
        where: reference.block_id == ^block_id,
        where: scene.project_id == ^project_id,
        where: is_nil(scene.deleted_at),
        select: %{
          source_type: reference.source_type,
          kind: reference.kind,
          scene_id: scene.id,
          scene_name: scene.name,
          pin_id: pin.id,
          pin_label: pin.label
        },
        order_by: [asc: reference.kind, asc: scene.name]
      )
    )
  end

  @spec get_scene_ambient_flow_variable_usage(integer(), integer()) :: [map()]
  def get_scene_ambient_flow_variable_usage(block_id, project_id) do
    Repo.all(
      from(reference in VariableReference,
        join: ambient_flow in SceneAmbientFlowRecord,
        on:
          reference.source_type == "scene_ambient_flow" and
            ambient_flow.id == reference.source_id,
        join: scene in SceneRecord,
        on: scene.id == ambient_flow.scene_id,
        join: flow in FlowRecord,
        on:
          flow.id == ambient_flow.flow_id and
            flow.project_id == scene.project_id,
        where: reference.block_id == ^block_id,
        where: scene.project_id == ^project_id,
        where: is_nil(scene.deleted_at),
        select: %{
          source_type: reference.source_type,
          kind: reference.kind,
          scene_id: scene.id,
          scene_name: scene.name,
          ambient_flow_id: ambient_flow.id,
          ambient_flow_name: flow.name,
          trigger_config: ambient_flow.trigger_config
        },
        order_by: [asc: reference.kind, asc: scene.name, asc: ambient_flow.id]
      )
    )
  end

  @spec check_stale_flow_node_variable_references(integer(), integer()) :: [map()]
  def check_stale_flow_node_variable_references(block_id, project_id) do
    Repo.all(
      from(reference in VariableReference,
        join: node in FlowNodeRecord,
        on:
          reference.source_type == "flow_node" and
            node.id == reference.source_id,
        join: flow in FlowRecord,
        on: flow.id == node.flow_id,
        join: block in BlockRecord,
        on: block.id == reference.block_id,
        join: sheet in SheetRecord,
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

  @spec check_stale_scene_zone_variable_references(integer(), integer()) :: [map()]
  def check_stale_scene_zone_variable_references(block_id, project_id) do
    Repo.all(
      from(reference in VariableReference,
        join: zone in SceneZoneRecord,
        on:
          reference.source_type == "scene_zone" and
            zone.id == reference.source_id,
        join: scene in SceneRecord,
        on: scene.id == zone.scene_id,
        join: block in BlockRecord,
        on: block.id == reference.block_id,
        join: sheet in SheetRecord,
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

  @spec check_stale_scene_pin_variable_references(integer(), integer()) :: [map()]
  def check_stale_scene_pin_variable_references(block_id, project_id) do
    Repo.all(
      from(reference in VariableReference,
        join: pin in ScenePinRecord,
        on:
          reference.source_type == "scene_pin" and
            pin.id == reference.source_id,
        join: scene in SceneRecord,
        on: scene.id == pin.scene_id,
        join: block in BlockRecord,
        on: block.id == reference.block_id,
        join: sheet in SheetRecord,
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

  @spec check_stale_scene_ambient_flow_variable_references(integer(), integer()) ::
          [map()]
  def check_stale_scene_ambient_flow_variable_references(block_id, project_id) do
    Repo.all(
      from(reference in VariableReference,
        join: ambient_flow in SceneAmbientFlowRecord,
        on:
          reference.source_type == "scene_ambient_flow" and
            ambient_flow.id == reference.source_id,
        join: scene in SceneRecord,
        on: scene.id == ambient_flow.scene_id,
        join: flow in FlowRecord,
        on:
          flow.id == ambient_flow.flow_id and
            flow.project_id == scene.project_id,
        join: block in BlockRecord,
        on: block.id == reference.block_id,
        join: sheet in SheetRecord,
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

  @spec list_variable_refs_with_block_info_for_repair(integer()) :: [map()]
  def list_variable_refs_with_block_info_for_repair(project_id) do
    Repo.all(
      from(reference in VariableReference,
        join: node in FlowNodeRecord,
        on:
          reference.source_type == "flow_node" and
            node.id == reference.source_id,
        join: flow in FlowRecord,
        on: flow.id == node.flow_id,
        join: block in BlockRecord,
        on: block.id == reference.block_id,
        join: sheet in SheetRecord,
        on: sheet.id == block.sheet_id,
        where: flow.project_id == ^project_id,
        where: is_nil(flow.deleted_at),
        where: is_nil(sheet.deleted_at),
        where: is_nil(block.deleted_at),
        where: VariableNamespaceResolver.authoritative_namespace_owner?(sheet),
        select: %{
          node_id: node.id,
          node_type: node.type,
          node_data: node.data,
          kind: reference.kind,
          block_id: reference.block_id,
          current_shortcut: coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
          current_variable: block.variable_name,
          source_sheet: reference.source_sheet,
          source_variable: reference.source_variable
        }
      )
    )
  end

  @spec list_stale_regular_node_ids(integer()) :: MapSet.t(integer())
  def list_stale_regular_node_ids(flow_id) do
    [flow_id]
    |> stale_regular_refs()
    |> node_ids_for_flow(flow_id)
  end

  @spec list_stale_table_node_ids(integer()) :: MapSet.t(integer())
  def list_stale_table_node_ids(flow_id) do
    [flow_id]
    |> stale_table_refs()
    |> node_ids_for_flow(flow_id)
  end

  defp stale_regular_refs(flow_ids) do
    Repo.all(
      from(reference in VariableReference,
        join: node in FlowNodeRecord,
        on:
          reference.source_type == "flow_node" and
            node.id == reference.source_id,
        join: block in BlockRecord,
        on: block.id == reference.block_id,
        join: sheet in SheetRecord,
        on: sheet.id == block.sheet_id,
        where: node.flow_id in ^flow_ids,
        where: is_nil(sheet.deleted_at),
        where: is_nil(block.deleted_at),
        where: block.type != "table",
        where:
          not VariableNamespaceResolver.authoritative_namespace_owner?(sheet) or
            reference.source_sheet !=
              coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)) or
            reference.source_variable != block.variable_name,
        distinct: true,
        select: {
          node.flow_id,
          node.id,
          reference.source_sheet,
          reference.source_variable
        }
      )
    )
  end

  defp stale_table_refs(flow_ids) do
    table_cell_exists =
      from(row in TableRowRecord,
        join: column in TableColumnRecord,
        on: column.block_id == row.block_id,
        where:
          parent_as(:reference).source_variable ==
            fragment(
              "? || '.' || ? || '.' || ?",
              parent_as(:block).variable_name,
              row.slug,
              column.slug
            ),
        select: 1
      )

    Repo.all(
      from(reference in VariableReference,
        as: :reference,
        join: node in FlowNodeRecord,
        on:
          reference.source_type == "flow_node" and
            node.id == reference.source_id,
        join: block in BlockRecord,
        as: :block,
        on: block.id == reference.block_id,
        join: sheet in SheetRecord,
        on: sheet.id == block.sheet_id,
        where: node.flow_id in ^flow_ids,
        where: is_nil(sheet.deleted_at),
        where: is_nil(block.deleted_at),
        where: block.type == "table",
        where:
          not VariableNamespaceResolver.authoritative_namespace_owner?(sheet) or
            reference.source_sheet !=
              coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)) or
            not exists(table_cell_exists),
        distinct: true,
        select: {
          node.flow_id,
          node.id,
          reference.source_sheet,
          reference.source_variable
        }
      )
    )
  end

  defp node_ids_for_flow(refs, flow_id) do
    for {^flow_id, node_id, _source_sheet, _source_variable} <- refs,
        into: MapSet.new(),
        do: node_id
  end
end
