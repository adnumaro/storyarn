defmodule Storyarn.References.VariableUsage do
  @moduledoc """
  Read paths for variable usage and stale-reference repair.

  Legacy editor reads remain delegated to `Flows.VariableReferenceTracker`;
  bounded, normalized lookup reads live here under the canonical References
  context.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.VariableReferenceTracker
  alias Storyarn.References.VariableReference
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Sheets

  @default_limit 25
  @max_limit 50

  defdelegate get_variable_usage(block_id, project_id), to: VariableReferenceTracker
  defdelegate count_variable_usage(block_id), to: VariableReferenceTracker
  defdelegate referenced_block_ids(block_ids), to: VariableReferenceTracker
  defdelegate count_stale_references(block_ids, project_id), to: VariableReferenceTracker

  def check_stale_variable_references(block_id, project_id),
    do: VariableReferenceTracker.check_stale_references(block_id, project_id)

  def repair_stale_variable_references(project_id), do: VariableReferenceTracker.repair_stale_references(project_id)

  defdelegate list_stale_node_ids(flow_id), to: VariableReferenceTracker

  @doc """
  Returns active reads and writes for one validated variable definition.

  Formula bindings are included as read usages. Results contain only source
  identity and navigation metadata; authored node, scene and formula payloads
  are never selected.
  """
  @spec list_variable_usages(integer(), map(), keyword()) ::
          %{items: [map()], truncated: boolean()}
  def list_variable_usages(project_id, definition, opts \\ []) when is_map(definition) do
    limit = bounded_limit(opts)
    fetch_limit = limit + 1

    tracked =
      flow_usages(project_id, definition, fetch_limit) ++
        pin_usages(project_id, definition, fetch_limit) ++
        zone_usages(project_id, definition, fetch_limit)

    formula_page =
      Sheets.list_formula_variable_usages(project_id, definition.qualified_ref, limit: limit)

    formula = Enum.map(formula_page.items, &formula_usage/1)

    items =
      Enum.sort_by(
        tracked ++ formula,
        &{String.downcase(&1.container_name), to_string(&1.source_type), &1.source_id, to_string(&1.kind)}
      )

    %{
      items: Enum.take(items, limit),
      truncated: length(items) > limit or formula_page.truncated
    }
  end

  defp flow_usages(project_id, definition, limit) do
    VariableReference
    |> join(:inner, [reference], node in FlowNode,
      on: reference.source_type == "flow_node" and reference.source_id == node.id
    )
    |> join(:inner, [_reference, node], flow in Flow, on: flow.id == node.flow_id)
    |> where(
      [_reference, node, flow],
      flow.project_id == ^project_id and is_nil(flow.deleted_at) and is_nil(node.deleted_at)
    )
    |> scope_definition(definition)
    |> order_by([reference, _node, flow],
      asc: flow.name,
      asc: reference.kind,
      asc: reference.id
    )
    |> limit(^limit)
    |> select([reference, node, flow], %{
      reference_id: reference.id,
      kind: reference.kind,
      source_type: :flow_node,
      source_id: node.id,
      source_kind: node.type,
      source_label: nil,
      container_type: :flow,
      container_id: flow.id,
      container_name: flow.name,
      stale:
        reference.source_sheet != ^definition.sheet_shortcut or
          reference.source_variable != ^definition.variable_name
    })
    |> Repo.all()
  end

  defp pin_usages(project_id, definition, limit) do
    VariableReference
    |> join(:inner, [reference], pin in ScenePin,
      on: reference.source_type == "scene_pin" and reference.source_id == pin.id
    )
    |> join(:inner, [_reference, pin], scene in Scene, on: scene.id == pin.scene_id)
    |> where(
      [_reference, _pin, scene],
      scene.project_id == ^project_id and is_nil(scene.deleted_at)
    )
    |> scope_definition(definition)
    |> order_by([reference, _pin, scene],
      asc: scene.name,
      asc: reference.kind,
      asc: reference.id
    )
    |> limit(^limit)
    |> select([reference, pin, scene], %{
      reference_id: reference.id,
      kind: reference.kind,
      source_type: :scene_pin,
      source_id: pin.id,
      source_kind: "pin",
      source_label: pin.label,
      container_type: :scene,
      container_id: scene.id,
      container_name: scene.name,
      stale:
        reference.source_sheet != ^definition.sheet_shortcut or
          reference.source_variable != ^definition.variable_name
    })
    |> Repo.all()
  end

  defp zone_usages(project_id, definition, limit) do
    VariableReference
    |> join(:inner, [reference], zone in SceneZone,
      on: reference.source_type == "scene_zone" and reference.source_id == zone.id
    )
    |> join(:inner, [_reference, zone], scene in Scene, on: scene.id == zone.scene_id)
    |> where(
      [_reference, _zone, scene],
      scene.project_id == ^project_id and is_nil(scene.deleted_at)
    )
    |> scope_definition(definition)
    |> order_by([reference, _zone, scene],
      asc: scene.name,
      asc: reference.kind,
      asc: reference.id
    )
    |> limit(^limit)
    |> select([reference, zone, scene], %{
      reference_id: reference.id,
      kind: reference.kind,
      source_type: :scene_zone,
      source_id: zone.id,
      source_kind: "zone",
      source_label: zone.name,
      container_type: :scene,
      container_id: scene.id,
      container_name: scene.name,
      stale:
        reference.source_sheet != ^definition.sheet_shortcut or
          reference.source_variable != ^definition.variable_name
    })
    |> Repo.all()
  end

  defp scope_definition(query, %{table_name: nil, block_id: block_id}) do
    where(query, [reference, ...], reference.block_id == ^block_id)
  end

  defp scope_definition(query, %{block_id: block_id, row_slug: row_slug, column_slug: column_slug}) do
    where(
      query,
      [reference, ...],
      reference.block_id == ^block_id and
        fragment("split_part(?, '.', 2)", reference.source_variable) == ^row_slug and
        fragment("split_part(?, '.', 3)", reference.source_variable) == ^column_slug
    )
  end

  defp formula_usage(usage) do
    %{
      reference_id: "formula:#{usage.block_id}:#{usage.row_id}:#{usage.column_id}",
      kind: "read",
      source_type: :table_formula,
      source_id: usage.column_id,
      source_kind: "formula",
      source_label: usage.column_name,
      container_type: :sheet,
      container_id: usage.sheet_id,
      container_name: usage.sheet_name,
      block_id: usage.block_id,
      row_id: usage.row_id,
      column_id: usage.column_id,
      stale: false
    }
  end

  defp bounded_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> max(1)
    |> min(@max_limit)
  end
end
