defmodule Storyarn.References.VariableUsage do
  @moduledoc """
  Read paths for variable usage and stale-reference repair.

  Legacy editor reads remain delegated to the cross-context projection owner;
  bounded, normalized lookup reads live here under the canonical References
  context.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Persistence.SceneAmbientFlowRecord, as: SceneAmbientFlow
  alias Storyarn.Projects.Persistence.ScenePinRecord, as: ScenePin
  alias Storyarn.Projects.Persistence.SceneRecord, as: Scene
  alias Storyarn.Projects.Persistence.SceneZoneRecord, as: SceneZone
  alias Storyarn.References.FlowCondition
  alias Storyarn.References.Persistence.FlowNodeRecord
  alias Storyarn.References.Persistence.FlowRecord
  alias Storyarn.References.VariableReference
  alias Storyarn.References.VariableReferenceTracker
  alias Storyarn.Repo
  alias Storyarn.Sheets

  @default_limit 25
  # Predicate search may need to inspect more authored occurrences than the
  # palette ultimately renders. This remains a hard scan ceiling.
  @max_limit 250

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
        zone_usages(project_id, definition, fetch_limit) ++
        ambient_flow_usages(project_id, definition, fetch_limit)

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
    |> join(:inner, [reference], node in FlowNodeRecord,
      on: reference.source_type == "flow_node" and reference.source_id == node.id
    )
    |> join(:inner, [_reference, node], flow in FlowRecord, on: flow.id == node.flow_id)
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
      block_id: reference.block_id,
      source_variable: reference.source_variable,
      kind: reference.kind,
      source_type: :flow_node,
      source_id: node.id,
      source_kind: node.type,
      source_label: nil,
      source_data: node.data,
      container_type: :flow,
      container_id: flow.id,
      container_name: flow.name,
      stale:
        reference.source_sheet != ^definition.sheet_shortcut or
          reference.source_variable != ^definition.variable_name
    })
    |> Repo.all()
    |> Enum.flat_map(fn usage ->
      usage
      |> expand_flow_usage(definition, limit)
      |> keep_tracked_kind(usage.kind)
    end)
    |> Enum.take(limit)
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
      block_id: reference.block_id,
      source_variable: reference.source_variable,
      kind: reference.kind,
      source_type: :scene_pin,
      source_id: pin.id,
      source_kind: "pin",
      source_label: pin.label,
      source_data: pin.condition,
      container_type: :scene,
      container_id: scene.id,
      container_name: scene.name,
      stale:
        reference.source_sheet != ^definition.sheet_shortcut or
          reference.source_variable != ^definition.variable_name
    })
    |> Repo.all()
    |> Enum.flat_map(fn usage ->
      usage
      |> expand_condition_usage(definition, usage.source_data, limit)
      |> prefer_specific_occurrences(usage)
      |> keep_tracked_kind(usage.kind)
    end)
    |> Enum.take(limit)
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
      block_id: reference.block_id,
      source_variable: reference.source_variable,
      kind: reference.kind,
      source_type: :scene_zone,
      source_id: zone.id,
      source_kind: "zone",
      source_label: zone.name,
      source_data: %{condition: zone.condition, action_data: zone.action_data},
      container_type: :scene,
      container_id: scene.id,
      container_name: scene.name,
      stale:
        reference.source_sheet != ^definition.sheet_shortcut or
          reference.source_variable != ^definition.variable_name
    })
    |> Repo.all()
    |> Enum.flat_map(fn usage ->
      condition = expand_condition_usage(usage, definition, usage.source_data.condition, limit)

      assignments =
        usage.source_data.action_data
        |> Map.get("assignments", [])
        |> expand_assignment_usage(usage, definition, limit)

      (condition ++ assignments)
      |> prefer_specific_occurrences(usage)
      |> keep_tracked_kind(usage.kind)
    end)
    |> Enum.take(limit)
  end

  defp ambient_flow_usages(project_id, definition, limit) do
    VariableReference
    |> join(:inner, [reference], ambient_flow in SceneAmbientFlow,
      on:
        reference.source_type == "scene_ambient_flow" and
          reference.source_id == ambient_flow.id
    )
    |> join(:inner, [_reference, ambient_flow], scene in Scene, on: scene.id == ambient_flow.scene_id)
    |> join(:inner, [_reference, ambient_flow, _scene], flow in FlowRecord, on: flow.id == ambient_flow.flow_id)
    |> where(
      [_reference, _ambient_flow, scene, _flow],
      scene.project_id == ^project_id and is_nil(scene.deleted_at)
    )
    |> scope_definition(definition)
    |> order_by([reference, ambient_flow, scene, _flow],
      asc: scene.name,
      asc: reference.kind,
      asc: ambient_flow.id,
      asc: reference.id
    )
    |> limit(^limit)
    |> select([reference, ambient_flow, scene, flow], %{
      reference_id: reference.id,
      block_id: reference.block_id,
      source_variable: reference.source_variable,
      kind: reference.kind,
      semantic: :read,
      source_type: :scene_ambient_flow,
      source_id: ambient_flow.id,
      source_kind: "ambient_event",
      source_label: flow.name,
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

  defp expand_flow_usage(%{source_kind: "instruction", source_data: data} = usage, definition, limit) do
    data
    |> Map.get("assignments", [])
    |> expand_assignment_usage(usage, definition, limit)
    |> prefer_specific_occurrences(usage)
  end

  defp expand_flow_usage(%{source_kind: "condition", source_data: data} = usage, definition, limit) do
    usage
    |> expand_condition_usage(definition, Map.get(data, "condition"), limit)
    |> prefer_specific_occurrences(usage)
  end

  defp expand_flow_usage(%{source_kind: "dialogue", source_data: data} = usage, definition, limit) do
    occurrences =
      data
      |> Map.get("responses", [])
      |> Stream.filter(&is_map/1)
      |> Stream.with_index()
      |> Stream.flat_map(fn {response, index} ->
        base = %{
          usage
          | reference_id: "#{usage.reference_id}:response:#{index}",
            source_label: response_label(response, index)
        }

        condition =
          expand_condition_usage(
            base,
            definition,
            normalize_condition(Map.get(response, "condition")),
            limit
          )

        assignments =
          response
          |> Map.get("instruction_assignments", legacy_assignments(response))
          |> expand_assignment_usage(base, definition, limit)

        condition ++ assignments
      end)
      |> Enum.take(limit)

    prefer_specific_occurrences(occurrences, usage)
  end

  defp expand_flow_usage(usage, _definition, _limit), do: [Map.delete(usage, :source_data)]

  defp expand_condition_usage(usage, definition, condition, limit) do
    condition
    |> normalize_condition()
    |> FlowCondition.extract_all_rules()
    |> Stream.filter(&targets_definition?(&1, definition))
    |> Stream.with_index()
    |> Stream.map(fn {rule, index} ->
      usage
      |> Map.delete(:source_data)
      |> Map.merge(%{
        reference_id: "#{usage.reference_id}:condition:#{index}",
        kind: "read",
        semantic: :condition,
        operator: Map.get(rule, "operator"),
        operand: Map.get(rule, "value"),
        value_type: "literal"
      })
    end)
    |> Enum.take(limit)
  end

  defp expand_assignment_usage(assignments, usage, definition, limit) when is_list(assignments) do
    assignments
    |> Stream.flat_map(&assignment_occurrences(&1, usage, definition))
    |> Enum.take(limit)
  end

  defp expand_assignment_usage(_assignments, _usage, _definition, _limit), do: []

  defp assignment_occurrences(assignment, usage, definition) when is_map(assignment) do
    write =
      if targets_definition?(assignment, definition) do
        [
          usage
          |> Map.delete(:source_data)
          |> Map.merge(%{
            reference_id: "#{usage.reference_id}:write:#{assignment_identity(assignment)}",
            kind: "write",
            semantic: :write,
            operator: Map.get(assignment, "operator"),
            operand: assignment_operand(assignment),
            value_type: Map.get(assignment, "value_type", "literal")
          })
        ]
      else
        []
      end

    read =
      if assignment_value_targets_definition?(assignment, definition) do
        [
          usage
          |> Map.delete(:source_data)
          |> Map.merge(%{
            reference_id: "#{usage.reference_id}:read:#{assignment_identity(assignment)}",
            kind: "read",
            semantic: :read,
            operator: "variable_ref",
            operand: nil,
            value_type: "variable_ref"
          })
        ]
      else
        []
      end

    write ++ read
  end

  defp assignment_occurrences(_assignment, _usage, _definition), do: []

  defp targets_definition?(source, definition) do
    source["sheet"] == definition.sheet_shortcut and
      source["variable"] == definition.variable_name
  end

  defp assignment_value_targets_definition?(assignment, definition) do
    assignment["value_type"] == "variable_ref" and
      assignment["value_sheet"] == definition.sheet_shortcut and
      assignment["value"] == definition.variable_name
  end

  defp assignment_operand(%{"operator" => "set_true"}), do: true
  defp assignment_operand(%{"operator" => "set_false"}), do: false
  defp assignment_operand(%{"operator" => "clear"}), do: ""
  defp assignment_operand(assignment), do: Map.get(assignment, "value")

  defp assignment_identity(assignment) do
    case Map.get(assignment, "id") do
      id when is_binary(id) and id != "" -> id
      _missing -> :erlang.phash2(assignment)
    end
  end

  defp response_label(response, index) do
    case Map.get(response, "text") do
      text when is_binary(text) and text != "" -> text
      _missing -> "Response #{index + 1}"
    end
  end

  defp legacy_assignments(%{"instruction" => assignment}) when is_map(assignment), do: [assignment]
  defp legacy_assignments(_response), do: []

  defp normalize_condition(condition) when is_map(condition), do: condition
  defp normalize_condition(condition) when is_binary(condition), do: FlowCondition.parse(condition)
  defp normalize_condition(_condition), do: nil

  defp prefer_specific_occurrences([], usage), do: [Map.delete(usage, :source_data)]
  defp prefer_specific_occurrences(occurrences, _usage), do: occurrences

  defp keep_tracked_kind(occurrences, tracked_kind) do
    Enum.filter(occurrences, fn
      %{semantic: :write} -> tracked_kind == "write"
      %{semantic: semantic} when semantic in [:read, :condition] -> tracked_kind == "read"
      %{kind: kind} -> kind == tracked_kind
      _occurrence -> false
    end)
  end

  defp bounded_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> max(1)
    |> min(@max_limit)
  end
end
