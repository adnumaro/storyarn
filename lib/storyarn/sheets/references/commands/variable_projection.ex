defmodule Storyarn.Sheets.References.Commands.VariableProjection do
  @moduledoc """
  Rebuilds the variable-reference projection needed after a Sheet restore.

  This is a Sheet-owned consumer of the shared persistence tables. It deliberately
  duplicates the extraction rules needed by Sheet restoration instead of calling
  another bounded context's writer. Rebuilds are additive so stale rows remain
  available to the existing repair workflow.
  """

  import Ecto.Query

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Logic
  alias Storyarn.Sheets.References.Data.FlowNodeRecord
  alias Storyarn.Sheets.References.Data.FlowRecord
  alias Storyarn.Sheets.References.Data.SceneAmbientFlowRecord
  alias Storyarn.Sheets.References.Data.ScenePinRecord
  alias Storyarn.Sheets.References.Data.SceneRecord
  alias Storyarn.Sheets.References.Data.SceneZoneRecord
  alias Storyarn.Sheets.References.Data.VariableReferenceRecord
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow

  require Logic

  @batch_size 100
  @condition_logic_types ~w(all any)
  @type rebuild_error ::
          {:invalid_project_id, term()}
          | {:project_variable_reference_rebuild_failed,
             %{
               project_id: integer(),
               source_type: String.t(),
               source_id: integer(),
               reason: term()
             }}

  @spec rebuild_project(integer()) :: :ok | {:error, rebuild_error()}
  def rebuild_project(project_id) when is_integer(project_id) and project_id > 0 do
    with :ok <- rebuild_sources(active_flow_nodes_query(project_id), project_id, "flow_node"),
         :ok <- rebuild_sources(active_scene_pins_query(project_id), project_id, "scene_pin"),
         :ok <- rebuild_sources(active_scene_zones_query(project_id), project_id, "scene_zone") do
      rebuild_sources(
        active_scene_ambient_flows_query(project_id),
        project_id,
        "scene_ambient_flow"
      )
    end
  end

  def rebuild_project(project_id), do: {:error, {:invalid_project_id, project_id}}

  defp rebuild_sources(query, project_id, source_type, after_id \\ 0) do
    sources =
      Repo.all(
        from(source in query,
          where: source.id > ^after_id,
          order_by: [asc: source.id],
          limit: ^@batch_size
        )
      )

    case rebuild_source_batch(sources, project_id, source_type) do
      :ok when length(sources) == @batch_size ->
        rebuild_sources(query, project_id, source_type, List.last(sources).id)

      result ->
        result
    end
  end

  defp rebuild_source_batch(sources, project_id, source_type) do
    Enum.reduce_while(sources, :ok, fn source, :ok ->
      case restore_missing_references(source_type, source, project_id) do
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
      end
    end)
  end

  defp restore_missing_references("flow_node", source, project_id) do
    source
    |> flow_reference_specs()
    |> resolve_references(project_id)
    |> insert_missing_references("flow_node", source.id, flow_node_id: source.id)
  end

  defp restore_missing_references(source_type, source, project_id) when source_type in ["scene_pin", "scene_zone"] do
    source
    |> scene_element_reference_specs()
    |> resolve_references(project_id)
    |> insert_missing_references(source_type, source.id)
  end

  defp restore_missing_references("scene_ambient_flow", source, project_id) do
    source
    |> ambient_flow_reference_specs()
    |> resolve_references(project_id)
    |> insert_missing_references("scene_ambient_flow", source.id)
  end

  defp insert_missing_references(references, source_type, source_id, opts \\ []) do
    now = TimeHelpers.now()

    entries =
      references
      |> Enum.uniq_by(&{&1.block_id, &1.kind, &1.source_variable})
      |> Enum.map(fn reference ->
        %{
          source_type: source_type,
          source_id: source_id,
          flow_node_id: Keyword.get(opts, :flow_node_id),
          block_id: reference.block_id,
          kind: reference.kind,
          source_sheet: reference.source_sheet,
          source_variable: reference.source_variable,
          inserted_at: now,
          updated_at: now
        }
      end)

    case Repo.insert_all(VariableReferenceRecord, entries, on_conflict: :nothing) do
      {count, _rows} when count >= 0 and count <= length(entries) -> :ok
      result -> {:error, {:variable_reference_additive_insert_count_mismatch, length(entries), result}}
    end
  end

  defp flow_reference_specs(%FlowNodeRecord{id: id, type: "instruction", data: data}) do
    data
    |> Map.get("assignments", [])
    |> list_value()
    |> Enum.flat_map(&assignment_specs(id, &1))
  end

  defp flow_reference_specs(%FlowNodeRecord{id: id, type: "condition", data: data}) do
    condition_specs(id, Map.get(data, "condition"))
  end

  defp flow_reference_specs(%FlowNodeRecord{id: id, type: "dialogue", data: data}) do
    data
    |> Map.get("responses", [])
    |> list_value()
    |> Enum.flat_map(&dialogue_response_specs(id, &1))
  end

  defp flow_reference_specs(%FlowNodeRecord{}), do: []

  defp dialogue_response_specs(source_id, %{} = response) do
    condition_specs(source_id, Map.get(response, "condition")) ++
      (response
       |> response_assignments()
       |> Enum.flat_map(&assignment_specs(source_id, &1)))
  end

  defp dialogue_response_specs(_source_id, _response), do: []

  defp response_assignments(%{"instruction_assignments" => [_first | _rest] = assignments}), do: assignments

  defp response_assignments(%{"instruction_assignments" => invalid}) when invalid not in [nil, []], do: []

  defp response_assignments(response) do
    case Map.get(response, "instruction") do
      instruction when is_binary(instruction) and instruction != "" ->
        case Jason.decode(instruction) do
          {:ok, assignments} when is_list(assignments) -> assignments
          _invalid -> []
        end

      _instruction ->
        []
    end
  end

  defp scene_element_reference_specs(source) do
    source_id = source.id

    scene_action_reference_specs(source, source_id) ++
      condition_specs(source_id, Map.get(source, :condition))
  end

  defp scene_action_reference_specs(source, source_id) do
    action_data = Map.get(source, :action_data) || %{}

    case Map.get(source, :action_type) do
      "action" ->
        action_data
        |> Map.get("assignments", [])
        |> list_value()
        |> Enum.flat_map(&assignment_specs(source_id, &1))

      "display" ->
        qualified_specs(source_id, "read", Map.get(action_data, "variable_ref"))

      "collection" ->
        action_data
        |> Map.get("items", [])
        |> list_value()
        |> Enum.flat_map(&collection_item_specs(source_id, &1))

      _other ->
        []
    end
  end

  defp collection_item_specs(source_id, %{} = item) do
    condition_specs(source_id, Map.get(item, "condition")) ++
      (item
       |> Map.get("instruction")
       |> collection_assignments()
       |> Enum.flat_map(&assignment_specs(source_id, &1)))
  end

  defp collection_item_specs(_source_id, _item), do: []

  defp collection_assignments(%{} = instruction) do
    instruction |> Map.get("assignments", []) |> list_value()
  end

  defp collection_assignments(_instruction), do: []

  defp ambient_flow_reference_specs(%SceneAmbientFlowRecord{
         id: id,
         trigger_type: "on_event",
         trigger_config: %{"variable_ref" => variable_ref}
       }) do
    qualified_specs(id, "read", variable_ref)
  end

  defp ambient_flow_reference_specs(%SceneAmbientFlowRecord{}), do: []

  defp condition_specs(source_id, condition) when is_binary(condition) do
    condition
    |> serialized_condition_rules()
    |> Enum.flat_map(&condition_rule_specs(source_id, &1))
  end

  defp condition_specs(source_id, %{"blocks" => blocks}) when is_list(blocks) do
    blocks
    |> Enum.flat_map(&condition_block_rules/1)
    |> Enum.flat_map(&condition_rule_specs(source_id, &1))
  end

  defp condition_specs(_source_id, _condition), do: []

  defp condition_block_rules(%{"type" => "block", "rules" => rules}) when is_list(rules), do: rules

  defp condition_block_rules(%{"type" => "group", "blocks" => blocks}) when is_list(blocks) do
    Enum.flat_map(blocks, &condition_block_rules/1)
  end

  defp condition_block_rules(_block), do: []

  # Serialized dialogue conditions keep the historical Flow parser contract:
  # the root logic must be valid and groups may contain only one level of
  # direct rule blocks. Map-backed Flow/Scene conditions are already normalized
  # by their writers and continue through condition_block_rules/1 above.
  defp serialized_condition_rules(condition) do
    case Jason.decode(condition) do
      {:ok, %{"logic" => logic, "blocks" => blocks}}
      when logic in @condition_logic_types and is_list(blocks) ->
        Enum.flat_map(blocks, &serialized_condition_block_rules/1)

      _invalid ->
        []
    end
  end

  defp serialized_condition_block_rules(%{"type" => "block", "rules" => rules}) when is_list(rules),
    do: Enum.filter(rules, &is_map/1)

  defp serialized_condition_block_rules(%{"type" => "group", "blocks" => blocks}) when is_list(blocks) do
    blocks
    |> Enum.filter(&(is_map(&1) and &1["type"] == "block"))
    |> Enum.flat_map(&serialized_condition_block_rules/1)
  end

  defp serialized_condition_block_rules(_block), do: []

  defp condition_rule_specs(source_id, %{} = rule) do
    variable_specs(source_id, "read", rule["sheet"], rule["variable"])
  end

  defp condition_rule_specs(_source_id, _rule), do: []

  defp assignment_specs(source_id, %{} = assignment) do
    writes =
      variable_specs(
        source_id,
        "write",
        assignment["sheet"],
        assignment["variable"]
      )

    reads =
      if assignment["value_type"] == "variable_ref" do
        variable_specs(
          source_id,
          "read",
          assignment["value_sheet"],
          assignment["value"]
        )
      else
        []
      end

    writes ++ reads
  end

  defp assignment_specs(_source_id, _assignment), do: []

  defp variable_specs(source_id, kind, namespace, variable)
       when is_binary(namespace) and namespace != "" and is_binary(variable) and variable != "" do
    [
      %{
        source_id: source_id,
        kind: kind,
        source_sheet: namespace,
        source_variable: variable,
        resolution_key: resolution_key(namespace, variable)
      }
    ]
  end

  defp variable_specs(_source_id, _kind, _namespace, _variable), do: []

  defp qualified_specs(source_id, kind, qualified) when is_binary(qualified) and qualified != "" do
    case List.pop_at(String.split(qualified, "."), -1) do
      {variable, namespace_parts} when namespace_parts != [] ->
        [
          %{
            source_id: source_id,
            kind: kind,
            source_sheet: Enum.join(namespace_parts, "."),
            source_variable: variable,
            resolution_key: {:qualified, qualified}
          }
        ]

      _invalid ->
        []
    end
  end

  defp qualified_specs(_source_id, _kind, _qualified), do: []

  defp resolution_key(namespace, variable) do
    case String.split(variable, ".", parts: 3) do
      [table, row, column] -> {:table, namespace, table, row, column}
      _regular -> {:regular, namespace, variable}
    end
  end

  defp resolve_references([], _project_id), do: []

  defp resolve_references(specs, project_id) do
    resolved = resolve_reference_targets(project_id, specs)
    Enum.flat_map(specs, &resolved_reference(&1, resolved))
  end

  defp resolve_reference_targets(project_id, specs) do
    keys = MapSet.new(specs, & &1.resolution_key)
    regular = for {:regular, _, _} = key <- keys, do: key
    tables = for {:table, _, _, _, _} = key <- keys, do: key
    qualified = for {:qualified, value} <- keys, do: value

    project_id
    |> resolve_regular(regular)
    |> Map.merge(resolve_tables(project_id, tables))
    |> Map.merge(resolve_qualified(project_id, qualified))
  end

  defp resolve_regular(_project_id, []), do: %{}

  defp resolve_regular(project_id, keys) do
    regular_variable_types = Logic.regular_variable_types()
    namespaces = keys |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    namespace_ids = Logic.resolve_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    sheet_ids = Map.keys(namespace_by_id)
    variables = keys |> Enum.map(&elem(&1, 2)) |> Enum.uniq()

    from(block in Block,
      join: sheet in Sheet,
      on: sheet.id == block.sheet_id,
      where:
        sheet.project_id == ^project_id and sheet.id in ^sheet_ids and
          block.variable_name in ^variables and block.type in ^regular_variable_types and
          block.is_constant == false and is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
      select: {sheet.id, block.variable_name, block.id}
    )
    |> Repo.all()
    |> Map.new(fn {sheet_id, variable, block_id} ->
      {{:regular, Map.fetch!(namespace_by_id, sheet_id), variable}, block_id}
    end)
  end

  defp resolve_tables(_project_id, []), do: %{}

  defp resolve_tables(project_id, keys) do
    table_variable_types = Logic.table_variable_types()
    constant_table_variable_types = Logic.constant_table_variable_types()
    namespaces = keys |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    namespace_ids = Logic.resolve_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    sheet_ids = Map.keys(namespace_by_id)
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
    |> where_resolvable_table_reference(
      project_id,
      sheet_ids,
      table_names,
      row_slugs,
      column_slugs
    )
    |> where_referenceable_table_column(table_variable_types, constant_table_variable_types)
    |> select([block: block, sheet: sheet, row: row, column: column], {
      sheet.id,
      block.variable_name,
      row.slug,
      column.slug,
      block.id
    })
    |> Repo.all()
    |> Map.new(fn {sheet_id, table, row, column, block_id} ->
      {{:table, Map.fetch!(namespace_by_id, sheet_id), table, row, column}, block_id}
    end)
  end

  defp where_resolvable_table_reference(query, project_id, sheet_ids, table_names, row_slugs, column_slugs) do
    where(
      query,
      [block: block, sheet: sheet, row: row, column: column],
      sheet.project_id == ^project_id and sheet.id in ^sheet_ids and
        block.variable_name in ^table_names and row.slug in ^row_slugs and
        column.slug in ^column_slugs and is_nil(sheet.deleted_at) and
        is_nil(block.deleted_at) and block.type == "table"
    )
  end

  defp where_referenceable_table_column(query, table_variable_types, constant_table_variable_types) do
    where(
      query,
      [column: column],
      column.type in ^table_variable_types and
        (column.is_constant == false or column.type in ^constant_table_variable_types)
    )
  end

  defp resolve_qualified(_project_id, []), do: %{}

  defp resolve_qualified(project_id, qualified_refs) do
    regular = qualified_regular_rows(project_id, qualified_refs)
    tables = qualified_table_rows(project_id, qualified_refs)

    Map.new(regular ++ tables, fn {qualified, namespace, variable, block_id} ->
      {{:qualified, qualified}, %{block_id: block_id, source_sheet: namespace, source_variable: variable}}
    end)
  end

  defp qualified_regular_rows(project_id, qualified_refs) do
    regular_variable_types = Logic.regular_variable_types()

    Repo.all(
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
            is_nil(block.deleted_at) and block.type in ^regular_variable_types and
            block.is_constant == false and not is_nil(block.variable_name) and
            block.variable_name != "" and
            Logic.authoritative_namespace_owner?(sheet) and
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

  defp qualified_table_rows(project_id, qualified_refs) do
    table_variable_types = Logic.table_variable_types()
    constant_table_variable_types = Logic.constant_table_variable_types()

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
    |> where_qualified_table_source(project_id)
    |> where_referenceable_table_column(table_variable_types, constant_table_variable_types)
    |> where_authoritative_qualified_table_reference(qualified_refs)
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

  defp where_qualified_table_source(query, project_id) do
    where(
      query,
      [block: block, sheet: sheet],
      sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
        is_nil(block.deleted_at) and not is_nil(block.variable_name) and
        block.variable_name != "" and block.type == "table"
    )
  end

  defp where_authoritative_qualified_table_reference(query, qualified_refs) do
    where(
      query,
      [column: column, block: block, sheet: sheet, row: row],
      Logic.authoritative_namespace_owner?(sheet) and
        fragment(
          "COALESCE(?, CAST(? AS TEXT)) || '.' || ? || '.' || ? || '.' || ?",
          sheet.shortcut,
          sheet.id,
          block.variable_name,
          row.slug,
          column.slug
        ) in ^qualified_refs
    )
  end

  defp resolved_reference(spec, resolved) do
    case Map.fetch(resolved, spec.resolution_key) do
      {:ok, %{block_id: block_id, source_sheet: namespace, source_variable: variable}} ->
        [%{block_id: block_id, kind: spec.kind, source_sheet: namespace, source_variable: variable}]

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

  defp active_flow_nodes_query(project_id) do
    from(node in FlowNodeRecord,
      join: flow in FlowRecord,
      on: flow.id == node.flow_id,
      where:
        flow.project_id == ^project_id and is_nil(flow.deleted_at) and
          is_nil(node.deleted_at)
    )
  end

  defp active_scene_pins_query(project_id) do
    from(pin in ScenePinRecord,
      join: scene in SceneRecord,
      on: scene.id == pin.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at)
    )
  end

  defp active_scene_zones_query(project_id) do
    from(zone in SceneZoneRecord,
      join: scene in SceneRecord,
      on: scene.id == zone.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at)
    )
  end

  defp active_scene_ambient_flows_query(project_id) do
    from(ambient_flow in SceneAmbientFlowRecord,
      join: scene in SceneRecord,
      on: scene.id == ambient_flow.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at)
    )
  end

  defp list_value(value) when is_list(value), do: value
  defp list_value(_value), do: []
end
