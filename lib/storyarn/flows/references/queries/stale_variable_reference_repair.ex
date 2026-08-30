defmodule Storyarn.Flows.References.Queries.StaleVariableReferenceRepair do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.References.Projections.BlockRecord
  alias Storyarn.Flows.References.Projections.SheetRecord
  alias Storyarn.Flows.References.Queries.VariableNamespaces
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Repo

  require VariableNamespaces

  @spec list_with_current_targets(integer()) :: [map()]
  def list_with_current_targets(project_id) do
    project_id
    |> base_query()
    |> Repo.all()
  end

  @spec list_node_with_current_targets(integer(), integer()) :: [map()]
  def list_node_with_current_targets(project_id, node_id) do
    project_id
    |> base_query()
    |> where([_reference, node], node.id == ^node_id)
    |> Repo.all()
  end

  @spec current_targets(integer(), [integer()]) :: %{optional(integer()) => map()}
  def current_targets(_project_id, []), do: %{}

  def current_targets(project_id, block_ids) do
    from(block in BlockRecord,
      join: sheet in SheetRecord,
      on: sheet.id == block.sheet_id,
      where:
        block.id in ^block_ids and sheet.project_id == ^project_id and
          is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
      where: VariableNamespaces.authoritative_owner?(sheet),
      select:
        {block.id,
         %{
           current_shortcut: coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
           current_variable: block.variable_name
         }}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp base_query(project_id) do
    from(reference in VariableReference,
      join: node in FlowNode,
      on:
        reference.source_type == "flow_node" and
          node.id == reference.source_id,
      join: flow in Flow,
      on: flow.id == node.flow_id,
      join: block in BlockRecord,
      on: block.id == reference.block_id,
      join: sheet in SheetRecord,
      on: sheet.id == block.sheet_id,
      where: flow.project_id == ^project_id,
      where: is_nil(flow.deleted_at),
      where: is_nil(sheet.deleted_at),
      where: is_nil(block.deleted_at),
      where: VariableNamespaces.authoritative_owner?(sheet),
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
  end
end
