defmodule Storyarn.Flows.VariableReferenceTracker do
  @moduledoc """
  Owns the variable-reference projection produced by Flow nodes.

  The projection shares the `variable_references` table with other bounded
  contexts, but extraction, resolution, staleness and writes in this module are
  expressed exclusively in Flow vocabulary and use Flow-owned persistence
  records.
  """

  import Ecto.Query

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.Logic
  alias Storyarn.Flows.References.Data.BlockRecord
  alias Storyarn.Flows.References.Data.SheetRecord
  alias Storyarn.Flows.References.Data.TableColumnRecord
  alias Storyarn.Flows.References.Data.TableRowRecord
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  require Logic

  @regular_variable_types ~w(text rich_text number select multi_select boolean date)
  @table_variable_types ~w(number text boolean select multi_select date reference formula)
  @constant_table_variable_types ~w(formula)

  @spec update_references(FlowNode.t()) :: :ok | {:error, term()}
  def update_references(%FlowNode{} = node) do
    references = extract_references(node)
    replace_references(node.id, references)
  end

  @doc false
  @spec flow_node_references_current_ids([FlowNode.t()], integer()) :: MapSet.t(integer())
  def flow_node_references_current_ids(nodes, project_id) when is_list(nodes) and is_integer(project_id) do
    valid_nodes = Enum.filter(nodes, &valid_persisted_node?/1)
    specs = Enum.flat_map(valid_nodes, &reference_specs/1)
    resolved_block_ids = resolve_reference_block_ids(project_id, specs)
    expected_by_node = expected_reference_sets(specs, resolved_block_ids)
    actual_by_node = actual_reference_sets(Enum.map(valid_nodes, & &1.id))

    Enum.reduce(valid_nodes, MapSet.new(), fn node, current_ids ->
      expected = Map.get(expected_by_node, node.id, MapSet.new())
      actual = Map.get(actual_by_node, node.id, MapSet.new())

      if expected == actual,
        do: MapSet.put(current_ids, node.id),
        else: current_ids
    end)
  end

  @doc "Validates that complete Flow-node variable references resolve in the project."
  @spec validate_flow_node_variable_targets([FlowNode.t() | map()], integer()) ::
          :ok | {:error, term()}
  def validate_flow_node_variable_targets(nodes, project_id)
      when is_list(nodes) and is_integer(project_id) and project_id > 0 do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, accumulated} ->
      case strict_reference_specs(node) do
        {:ok, specs} -> {:cont, {:ok, accumulated ++ specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, specs} -> validate_resolvable_specs(project_id, specs)
      {:error, _reason} = error -> error
    end
  end

  def validate_flow_node_variable_targets(nodes, project_id),
    do: {:error, {:invalid_variable_reference_validation_scope, "flow_node", project_id, nodes}}

  @spec delete_references(integer()) :: :ok
  def delete_references(node_id) when is_integer(node_id) do
    Repo.delete_all(
      from reference in VariableReference,
        where:
          reference.source_type == "flow_node" and
            reference.source_id == ^node_id
    )

    :ok
  end

  @doc "Returns Flow-node IDs with variable references that no longer resolve."
  @spec list_stale_node_ids(integer()) :: MapSet.t(integer())
  def list_stale_node_ids(flow_id) when is_integer(flow_id) do
    flow_id
    |> then(&list_stale_node_ids_by_flow([&1]))
    |> Map.get(flow_id, MapSet.new())
  end

  @doc "Returns stale Flow-node IDs grouped by Flow in a fixed two queries."
  @spec list_stale_node_ids_by_flow([integer()]) :: %{integer() => MapSet.t(integer())}
  def list_stale_node_ids_by_flow([]), do: %{}

  def list_stale_node_ids_by_flow(flow_ids) when is_list(flow_ids) do
    flow_ids
    |> stale_reference_rows()
    |> Enum.reduce(%{}, fn {flow_id, node_id}, by_flow ->
      Map.update(by_flow, flow_id, MapSet.new([node_id]), &MapSet.put(&1, node_id))
    end)
  end

  @doc "Lists active Sheet IDs referenced by active Flow nodes in a project."
  @spec list_referenced_sheet_ids(integer()) :: MapSet.t(integer())
  def list_referenced_sheet_ids(project_id) when is_integer(project_id) do
    from(reference in VariableReference,
      join: node in FlowNode,
      on:
        reference.source_type == "flow_node" and
          reference.source_id == node.id,
      join: flow in Flow,
      on: flow.id == node.flow_id,
      join: block in BlockRecord,
      on: block.id == reference.block_id,
      join: sheet in SheetRecord,
      on: sheet.id == block.sheet_id,
      where:
        flow.project_id == ^project_id and is_nil(flow.deleted_at) and
          is_nil(node.deleted_at) and is_nil(block.deleted_at) and
          is_nil(sheet.deleted_at),
      select: sheet.id,
      distinct: true
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp valid_persisted_node?(%FlowNode{id: id, data: data}), do: is_integer(id) and is_map(data)

  defp valid_persisted_node?(_node), do: false

  defp extract_references(%FlowNode{} = node) do
    case flow_project_id(node.flow_id) do
      nil -> []
      project_id -> resolve_specs(project_id, reference_specs(node))
    end
  end

  defp flow_project_id(flow_id) do
    Repo.one(
      from flow in Flow,
        where: flow.id == ^flow_id and is_nil(flow.deleted_at),
        select: flow.project_id
    )
  end

  defp reference_specs(%FlowNode{id: node_id, type: "instruction", data: data}) do
    data
    |> Map.get("assignments", [])
    |> list_value()
    |> Enum.flat_map(&assignment_specs(node_id, &1))
  end

  defp reference_specs(%FlowNode{id: node_id, type: "condition", data: data}) do
    data
    |> Map.get("condition")
    |> Logic.condition_extract_all_rules()
    |> Enum.flat_map(&condition_rule_specs(node_id, &1))
  end

  defp reference_specs(%FlowNode{id: node_id, type: "dialogue", data: data}) do
    data
    |> Map.get("responses", [])
    |> list_value()
    |> Enum.flat_map(&dialogue_response_specs(node_id, &1))
  end

  defp reference_specs(%FlowNode{}), do: []

  defp dialogue_response_specs(node_id, %{} = response) do
    condition_specs(node_id, response["condition"]) ++
      (response
       |> response_assignments()
       |> list_value()
       |> Enum.flat_map(&assignment_specs(node_id, &1)))
  end

  defp dialogue_response_specs(_node_id, _response), do: []

  defp condition_specs(node_id, condition) when is_binary(condition) do
    case Jason.decode(condition) do
      {:ok, %{} = decoded} -> condition_specs(node_id, decoded)
      _invalid -> []
    end
  end

  defp condition_specs(node_id, condition) do
    condition
    |> Logic.condition_extract_all_rules()
    |> Enum.flat_map(&condition_rule_specs(node_id, &1))
  end

  defp condition_rule_specs(node_id, %{} = rule), do: variable_specs(node_id, "read", rule["sheet"], rule["variable"])

  defp condition_rule_specs(_node_id, _rule), do: []

  defp assignment_specs(node_id, %{} = assignment) do
    writes =
      variable_specs(
        node_id,
        "write",
        assignment["sheet"],
        assignment["variable"]
      )

    reads =
      if assignment["value_type"] == "variable_ref" do
        variable_specs(
          node_id,
          "read",
          assignment["value_sheet"],
          assignment["value"]
        )
      else
        []
      end

    writes ++ reads
  end

  defp assignment_specs(_node_id, _assignment), do: []

  defp variable_specs(node_id, kind, sheet_shortcut, variable_name)
       when is_binary(sheet_shortcut) and sheet_shortcut != "" and is_binary(variable_name) and variable_name != "" do
    [
      %{
        source_id: node_id,
        kind: kind,
        source_sheet: sheet_shortcut,
        source_variable: variable_name,
        resolution_key: resolution_key(sheet_shortcut, variable_name)
      }
    ]
  end

  defp variable_specs(_node_id, _kind, _sheet_shortcut, _variable_name), do: []

  defp resolution_key(sheet_shortcut, variable_name) do
    case String.split(variable_name, ".", parts: 3) do
      [table_name, row_slug, column_slug] ->
        {:table, sheet_shortcut, table_name, row_slug, column_slug}

      _regular ->
        {:regular, sheet_shortcut, variable_name}
    end
  end

  defp response_assignments(%{"instruction_assignments" => [_first | _rest] = assignments}), do: assignments

  defp response_assignments(%{"instruction_assignments" => invalid}) when invalid not in [nil, []], do: invalid

  defp response_assignments(response), do: decode_legacy_assignments(response["instruction"])

  defp decode_legacy_assignments(instruction) when instruction in [nil, ""], do: []

  defp decode_legacy_assignments(instruction) when is_binary(instruction) do
    case Jason.decode(instruction) do
      {:ok, assignments} when is_list(assignments) -> assignments
      _invalid -> []
    end
  end

  defp decode_legacy_assignments(_instruction), do: []

  defp strict_reference_specs(node) do
    with {:ok, normalized} <- normalize_node(node) do
      strict_specs_for_node(normalized)
    end
  end

  defp normalize_node(%FlowNode{id: id, type: type, data: data}) when is_integer(id) and is_binary(type) and is_map(data),
    do: {:ok, %{id: id, type: type, data: data}}

  defp normalize_node(%{} = node) do
    id = node["original_id"] || node[:original_id] || node["id"] || node[:id]
    type = node["type"] || node[:type]
    data = node["data"] || node[:data]

    if is_integer(id) and is_binary(type) and is_map(data),
      do: {:ok, %{id: id, type: type, data: data}},
      else: {:error, {:invalid_variable_reference_source, "flow_node", id}}
  end

  defp normalize_node(node), do: {:error, {:invalid_variable_reference_source, "flow_node", node}}

  defp strict_specs_for_node(%{id: id, type: "instruction", data: data}),
    do: strict_assignment_list(id, Map.get(data, "assignments", []))

  defp strict_specs_for_node(%{id: id, type: "condition", data: data}), do: strict_condition(id, data["condition"])

  defp strict_specs_for_node(%{id: id, type: "dialogue", data: data}),
    do: strict_responses(id, Map.get(data, "responses", []))

  defp strict_specs_for_node(%{type: _other}), do: {:ok, []}

  defp strict_assignment_list(_source_id, []), do: {:ok, []}

  defp strict_assignment_list(source_id, assignments) when is_list(assignments) do
    Enum.reduce_while(assignments, {:ok, []}, fn assignment, {:ok, specs} ->
      case strict_assignment(source_id, assignment) do
        {:ok, current} -> {:cont, {:ok, specs ++ current}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp strict_assignment_list(source_id, assignments), do: malformed(source_id, :assignments, assignments)

  defp strict_assignment(source_id, %{} = assignment) do
    with {:ok, writes} <-
           strict_draft_reference(
             source_id,
             "write",
             assignment["sheet"],
             assignment["variable"],
             :assignment_target
           ),
         {:ok, reads} <- strict_assignment_read(source_id, assignment) do
      {:ok, writes ++ reads}
    end
  end

  defp strict_assignment(source_id, assignment), do: malformed(source_id, :assignment, assignment)

  defp strict_assignment_read(source_id, %{"value_type" => "variable_ref"} = assignment) do
    strict_draft_reference(
      source_id,
      "read",
      assignment["value_sheet"],
      assignment["value"],
      :assignment_value
    )
  end

  defp strict_assignment_read(_source_id, _assignment), do: {:ok, []}

  defp strict_condition(_source_id, nil), do: {:ok, []}
  defp strict_condition(_source_id, condition) when condition == %{}, do: {:ok, []}

  defp strict_condition(source_id, %{} = condition) do
    case Logic.condition_validate(condition) do
      {:ok, valid_condition} ->
        valid_condition
        |> Logic.condition_extract_all_rules()
        |> strict_condition_rules(source_id)

      {:error, _reason} ->
        malformed(source_id, :condition, condition)
    end
  end

  defp strict_condition(source_id, condition), do: malformed(source_id, :condition, condition)

  defp strict_condition_rules(rules, source_id) do
    Enum.reduce_while(rules, {:ok, []}, fn rule, {:ok, specs} ->
      case strict_condition_rule(source_id, rule) do
        {:ok, current} -> {:cont, {:ok, specs ++ current}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp strict_condition_rule(source_id, rule) do
    strict_draft_reference(
      source_id,
      "read",
      rule["sheet"],
      rule["variable"],
      :condition_rule
    )
  end

  defp strict_responses(_source_id, []), do: {:ok, []}

  defp strict_responses(source_id, responses) when is_list(responses) do
    responses
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {response, index}, {:ok, specs} ->
      case strict_response(source_id, response, index) do
        {:ok, current} -> {:cont, {:ok, specs ++ current}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp strict_responses(source_id, responses), do: malformed(source_id, :dialogue_responses, responses)

  defp strict_response(source_id, %{} = response, index) do
    with {:ok, conditions} <- strict_response_condition(source_id, response["condition"], index),
         {:ok, assignments} <- strict_response_assignments(source_id, response, index) do
      {:ok, conditions ++ assignments}
    end
  end

  defp strict_response(source_id, response, index), do: malformed(source_id, {:dialogue_response, index}, response)

  defp strict_response_condition(_source_id, condition, _index) when condition in [nil, ""], do: {:ok, []}

  defp strict_response_condition(source_id, %{} = condition, _index), do: strict_condition(source_id, condition)

  defp strict_response_condition(source_id, condition, index) when is_binary(condition) do
    case Jason.decode(condition) do
      {:ok, %{} = decoded} -> strict_condition(source_id, decoded)
      _invalid -> malformed(source_id, {:response_condition, index}, condition)
    end
  end

  defp strict_response_condition(source_id, condition, index),
    do: malformed(source_id, {:response_condition, index}, condition)

  defp strict_response_assignments(source_id, response, index) do
    case Map.get(response, "instruction_assignments") do
      [_first | _rest] = assignments ->
        strict_assignment_list(source_id, assignments)

      assignments when assignments in [nil, []] ->
        strict_legacy_assignments(source_id, response["instruction"], index)

      invalid ->
        malformed(source_id, {:response_instruction_assignments, index}, invalid)
    end
  end

  defp strict_legacy_assignments(_source_id, instruction, _index) when instruction in [nil, ""], do: {:ok, []}

  defp strict_legacy_assignments(source_id, instruction, index) when is_binary(instruction) do
    case Jason.decode(instruction) do
      {:ok, assignments} when is_list(assignments) ->
        strict_assignment_list(source_id, assignments)

      _invalid ->
        malformed(source_id, {:response_instruction, index}, instruction)
    end
  end

  defp strict_legacy_assignments(source_id, instruction, index),
    do: malformed(source_id, {:response_instruction, index}, instruction)

  defp strict_draft_reference(source_id, kind, sheet, variable, context) do
    cond do
      nonempty?(sheet) and nonempty?(variable) ->
        {:ok, variable_specs(source_id, kind, sheet, variable)}

      (sheet in [nil, ""] and variable in [nil, ""]) or
          (nonempty?(sheet) and variable in [nil, ""]) ->
        {:ok, []}

      true ->
        malformed(source_id, context, {sheet, variable})
    end
  end

  defp nonempty?(value), do: is_binary(value) and String.trim(value) != ""

  defp malformed(source_id, context, value),
    do: {:error, {:malformed_variable_reference, "flow_node", source_id, context, value}}

  defp validate_resolvable_specs(_project_id, []), do: :ok

  defp validate_resolvable_specs(project_id, specs) do
    resolved = resolve_reference_block_ids(project_id, specs)

    case Enum.find(specs, &(not Map.has_key?(resolved, &1.resolution_key))) do
      nil ->
        :ok

      spec ->
        {:error,
         {:unresolved_variable_reference, "flow_node", spec.source_id, spec.kind, spec.source_sheet, spec.source_variable}}
    end
  end

  defp resolve_specs(project_id, specs) do
    resolved = resolve_reference_block_ids(project_id, specs)
    Enum.flat_map(specs, &resolved_reference(&1, resolved))
  end

  defp resolve_reference_block_ids(project_id, specs) do
    keys = MapSet.new(specs, & &1.resolution_key)

    regular_keys =
      for {:regular, _sheet, _variable} = key <- keys, do: key

    table_keys =
      for {:table, _sheet, _table, _row, _column} = key <- keys, do: key

    project_id
    |> resolve_regular_block_ids(regular_keys)
    |> Map.merge(resolve_table_block_ids(project_id, table_keys))
  end

  defp resolve_regular_block_ids(_project_id, []), do: %{}

  defp resolve_regular_block_ids(project_id, keys) do
    namespaces = keys |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    namespace_ids = Logic.resolve_variable_namespace_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    sheet_ids = Map.keys(namespace_by_id)
    variable_names = keys |> Enum.map(&elem(&1, 2)) |> Enum.uniq()

    from(block in BlockRecord,
      join: sheet in SheetRecord,
      on: sheet.id == block.sheet_id,
      where:
        sheet.project_id == ^project_id and sheet.id in ^sheet_ids and
          block.variable_name in ^variable_names and
          block.type in ^@regular_variable_types and block.is_constant == false and
          is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
      select: {sheet.id, block.variable_name, block.id}
    )
    |> Repo.all()
    |> Map.new(fn {sheet_id, variable_name, block_id} ->
      namespace = Map.fetch!(namespace_by_id, sheet_id)
      {{:regular, namespace, variable_name}, block_id}
    end)
  end

  defp resolve_table_block_ids(_project_id, []), do: %{}

  defp resolve_table_block_ids(project_id, keys) do
    namespaces = keys |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    namespace_ids = Logic.resolve_variable_namespace_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    sheet_ids = Map.keys(namespace_by_id)
    table_names = keys |> Enum.map(&elem(&1, 2)) |> Enum.uniq()
    row_slugs = keys |> Enum.map(&elem(&1, 3)) |> Enum.uniq()
    column_slugs = keys |> Enum.map(&elem(&1, 4)) |> Enum.uniq()

    BlockRecord
    |> from(as: :block)
    |> join(:inner, [block: block], sheet in SheetRecord,
      as: :sheet,
      on: sheet.id == block.sheet_id
    )
    |> join(:inner, [block: block], row in TableRowRecord,
      as: :row,
      on: row.block_id == block.id
    )
    |> join(:inner, [block: block], column in TableColumnRecord,
      as: :column,
      on: column.block_id == block.id
    )
    |> constrain_table_blocks(project_id, sheet_ids, table_names)
    |> constrain_table_cells(row_slugs, column_slugs)
    |> constrain_table_column_types()
    |> constrain_active_table_records()
    |> select([block: block, sheet: sheet, row: row, column: column], {
      sheet.id,
      block.variable_name,
      row.slug,
      column.slug,
      block.id
    })
    |> Repo.all()
    |> Map.new(fn {sheet_id, table_name, row_slug, column_slug, block_id} ->
      namespace = Map.fetch!(namespace_by_id, sheet_id)
      {{:table, namespace, table_name, row_slug, column_slug}, block_id}
    end)
  end

  defp constrain_table_blocks(query, project_id, sheet_ids, table_names) do
    where(
      query,
      [block: block, sheet: sheet],
      sheet.project_id == ^project_id and sheet.id in ^sheet_ids and
        block.variable_name in ^table_names and block.type == "table"
    )
  end

  defp constrain_table_cells(query, row_slugs, column_slugs) do
    where(
      query,
      [row: row, column: column],
      row.slug in ^row_slugs and column.slug in ^column_slugs
    )
  end

  defp constrain_table_column_types(query) do
    where(
      query,
      [column: column],
      column.type in ^@table_variable_types and
        (column.is_constant == false or column.type in ^@constant_table_variable_types)
    )
  end

  defp constrain_active_table_records(query) do
    where(
      query,
      [block: block, sheet: sheet],
      is_nil(sheet.deleted_at) and is_nil(block.deleted_at)
    )
  end

  defp resolved_reference(spec, resolved) do
    case Map.fetch(resolved, spec.resolution_key) do
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

  defp expected_reference_sets(specs, resolved) do
    specs
    |> Enum.group_by(& &1.source_id)
    |> Map.new(fn {source_id, source_specs} ->
      references =
        source_specs
        |> Enum.flat_map(&resolved_reference(&1, resolved))
        |> Enum.uniq_by(&{&1.block_id, &1.kind, &1.source_variable})
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

  defp actual_reference_sets([]), do: %{}

  defp actual_reference_sets(node_ids) do
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
    |> Enum.reduce(%{}, fn
      {source_id, block_id, kind, source_sheet, source_variable, flow_node_id}, references ->
        reference = {block_id, kind, source_sheet, source_variable, flow_node_id}
        Map.update(references, source_id, MapSet.new([reference]), &MapSet.put(&1, reference))
    end)
  end

  defp replace_references(node_id, references) do
    operation = fn ->
      delete_references(node_id)
      now = TimeHelpers.now()

      entries =
        references
        |> Enum.uniq_by(&{&1.block_id, &1.kind, &1.source_variable})
        |> Enum.map(fn reference ->
          %{
            source_type: "flow_node",
            source_id: node_id,
            flow_node_id: node_id,
            block_id: reference.block_id,
            kind: reference.kind,
            source_sheet: reference.source_sheet,
            source_variable: reference.source_variable,
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(VariableReference, entries, on_conflict: :nothing)
      :ok
    end

    result =
      if Repo.in_transaction?() do
        operation.()
      else
        case Repo.transaction(operation) do
          {:ok, :ok} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end

    case result do
      :ok -> :ok
      {:error, reason} -> {:error, {:variable_reference_write_failed, "flow_node", node_id, reason}}
    end
  end

  defp stale_reference_rows(flow_ids) do
    stale_regular_rows(flow_ids) ++ stale_table_rows(flow_ids)
  end

  defp stale_regular_rows(flow_ids) do
    Repo.all(
      from reference in VariableReference,
        join: node in FlowNode,
        on:
          reference.source_type == "flow_node" and
            node.id == reference.source_id,
        join: block in BlockRecord,
        on: block.id == reference.block_id,
        join: sheet in SheetRecord,
        on: sheet.id == block.sheet_id,
        where:
          node.flow_id in ^flow_ids and is_nil(node.deleted_at) and
            is_nil(sheet.deleted_at) and is_nil(block.deleted_at) and
            block.type != "table",
        where:
          not Logic.authoritative_variable_namespace_owner?(sheet) or
            reference.source_sheet !=
              coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)) or
            reference.source_variable != block.variable_name,
        distinct: true,
        select: {node.flow_id, node.id}
    )
  end

  defp stale_table_rows(flow_ids) do
    table_cell_exists =
      from row in TableRowRecord,
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

    Repo.all(
      from reference in VariableReference,
        as: :reference,
        join: node in FlowNode,
        on:
          reference.source_type == "flow_node" and
            node.id == reference.source_id,
        join: block in BlockRecord,
        as: :block,
        on: block.id == reference.block_id,
        join: sheet in SheetRecord,
        on: sheet.id == block.sheet_id,
        where:
          node.flow_id in ^flow_ids and is_nil(node.deleted_at) and
            is_nil(sheet.deleted_at) and is_nil(block.deleted_at) and
            block.type == "table",
        where:
          not Logic.authoritative_variable_namespace_owner?(sheet) or
            reference.source_sheet !=
              coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)) or
            not exists(table_cell_exists),
        distinct: true,
        select: {node.flow_id, node.id}
    )
  end

  defp list_value(value) when is_list(value), do: value
  defp list_value(_value), do: []
end
