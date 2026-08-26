defmodule Storyarn.Scenes.References.Commands.VariableProjection do
  @moduledoc """
  Scene-owned variable-reference projection for pins, zones and ambient flows.

  The SQL table is shared intentionally. Extraction, validation and writes are
  local so a change in another tool cannot alter Scene runtime semantics.
  """

  import Ecto.Query

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Scenes.Condition
  alias Storyarn.Scenes.References.Data.BlockRecord
  alias Storyarn.Scenes.References.Data.SheetRecord
  alias Storyarn.Scenes.References.Data.TableColumnRecord
  alias Storyarn.Scenes.References.Data.TableRowRecord
  alias Storyarn.Scenes.References.Data.VariableReferenceRecord
  alias Storyarn.Scenes.References.Queries.VariableNamespaces

  require VariableNamespaces

  @regular_variable_types ~w(text rich_text number select multi_select boolean date)
  @table_variable_types ~w(number text boolean select multi_select date reference formula)
  @constant_table_variable_types ~w(formula)

  def update_pin_references(pin, opts \\ [])

  def update_pin_references(%{id: pin_id, scene_id: scene_id} = pin, opts) when is_integer(pin_id) do
    project_id = resolve_project_id(scene_id, opts)
    references = if project_id, do: element_references(pin, project_id), else: []
    replace_references("scene_pin", pin_id, references)
  end

  def update_pin_references(_pin, _opts), do: :ok

  def delete_pin_references(pin_id), do: delete_references("scene_pin", pin_id)

  def update_zone_references(zone, opts \\ [])

  def update_zone_references(%{id: zone_id, scene_id: scene_id} = zone, opts) when is_integer(zone_id) do
    project_id = resolve_project_id(scene_id, opts)
    references = if project_id, do: element_references(zone, project_id), else: []
    replace_references("scene_zone", zone_id, references)
  end

  def update_zone_references(_zone, _opts), do: :ok

  def delete_zone_references(zone_id), do: delete_references("scene_zone", zone_id)

  def update_ambient_flow_references(ambient_flow, opts \\ [])

  def update_ambient_flow_references(%{id: id, scene_id: scene_id} = ambient_flow, opts) when is_integer(id) do
    project_id = resolve_project_id(scene_id, opts)

    references =
      if project_id, do: ambient_flow_references(ambient_flow, project_id), else: []

    replace_references("scene_ambient_flow", id, references)
  end

  def update_ambient_flow_references(_ambient_flow, _opts), do: :ok

  def delete_ambient_flow_references(id), do: delete_references("scene_ambient_flow", id)

  @doc "Validates every variable-reference surface encoded in a Scene snapshot."
  def validate_snapshot_variable_references(project_id, sources)
      when is_integer(project_id) and project_id > 0 and is_list(sources) do
    sources
    |> Enum.reduce_while({:ok, []}, fn source, {:ok, accumulated} ->
      case strict_source_specs(source) do
        {:ok, specs} -> {:cont, {:ok, accumulated ++ specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, specs} -> validate_resolvable_specs(project_id, specs)
      {:error, _reason} = error -> error
    end
  end

  def validate_snapshot_variable_references(project_id, sources),
    do: {:error, {:invalid_variable_reference_validation_scope, :scene, project_id, sources}}

  # A missing scene resolves to nil and the caller wipes the projection rows
  # while returning :ok, matching the pre-migration tracker.
  defp resolve_project_id(scene_id, opts) do
    opts[:project_id] ||
      Repo.one(
        from scene in Storyarn.Scenes.Scene,
          where: scene.id == ^scene_id,
          select: scene.project_id
      )
  end

  defp delete_references(source_type, source_id) do
    Repo.delete_all(
      from reference in VariableReferenceRecord,
        where:
          reference.source_type == ^source_type and
            reference.source_id == ^source_id
    )

    :ok
  end

  defp replace_references(source_type, source_id, references) do
    operation = fn ->
      delete_references(source_type, source_id)
      insert_references(source_type, source_id, references)
    end

    if Repo.in_transaction?() do
      operation.()
    else
      case Repo.transaction(operation) do
        {:ok, :ok} -> :ok
        {:error, reason} -> {:error, {:variable_reference_write_failed, source_type, source_id, reason}}
      end
    end
  end

  defp insert_references(_source_type, _source_id, []), do: :ok

  defp insert_references(source_type, source_id, references) do
    now = TimeHelpers.now()

    entries =
      references
      |> Enum.uniq_by(&{&1.block_id, &1.kind, &1.source_variable})
      |> Enum.map(fn reference ->
        %{
          source_type: source_type,
          source_id: source_id,
          flow_node_id: nil,
          block_id: reference.block_id,
          kind: reference.kind,
          source_sheet: reference.source_sheet,
          source_variable: reference.source_variable,
          inserted_at: now,
          updated_at: now
        }
      end)

    case Repo.insert_all(VariableReferenceRecord, entries, on_conflict: :nothing) do
      {count, _rows} when count == length(entries) -> :ok
      result -> Repo.rollback({:variable_reference_insert_count_mismatch, length(entries), result})
    end
  end

  defp element_references(element, project_id) do
    specs = element_specs(element)
    resolved = resolve_specs(project_id, specs)
    Enum.flat_map(specs, &resolved_reference(&1, resolved))
  end

  defp ambient_flow_references(%{trigger_type: "on_event", trigger_config: %{"variable_ref" => variable_ref}}, project_id) do
    specs = qualified_specs(0, "read", variable_ref)
    resolved = resolve_specs(project_id, specs)
    Enum.flat_map(specs, &resolved_reference(&1, resolved))
  end

  defp ambient_flow_references(_ambient_flow, _project_id), do: []

  defp element_specs(element) do
    source_id = Map.get(element, :id)
    action_specs(element, source_id) ++ condition_specs(Map.get(element, :condition), source_id)
  end

  defp action_specs(element, source_id) do
    action_data = Map.get(element, :action_data) || %{}

    case Map.get(element, :action_type) do
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
    instruction_specs =
      case Map.get(item, "instruction") do
        %{} = instruction ->
          instruction
          |> Map.get("assignments", [])
          |> list_value()
          |> Enum.flat_map(&assignment_specs(source_id, &1))

        _instruction ->
          []
      end

    condition_specs(Map.get(item, "condition"), source_id) ++ instruction_specs
  end

  defp collection_item_specs(_source_id, _item), do: []

  defp condition_specs(condition, source_id) do
    condition
    |> Condition.extract_all_rules()
    |> Enum.flat_map(fn
      %{} = rule -> reference_specs(source_id, "read", rule["sheet"], rule["variable"])
      _rule -> []
    end)
  end

  defp assignment_specs(source_id, %{} = assignment) do
    write_specs =
      reference_specs(
        source_id,
        "write",
        assignment["sheet"],
        assignment["variable"]
      )

    read_specs =
      if assignment["value_type"] == "variable_ref" do
        reference_specs(
          source_id,
          "read",
          assignment["value_sheet"],
          assignment["value"]
        )
      else
        []
      end

    write_specs ++ read_specs
  end

  defp assignment_specs(_source_id, _assignment), do: []

  defp reference_specs(source_id, kind, namespace, variable)
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

  defp reference_specs(_source_id, _kind, _namespace, _variable), do: []

  defp qualified_specs(source_id, kind, qualified) when is_binary(qualified) and qualified != "" do
    if String.trim(qualified) == "" do
      []
    else
      {namespace, variable} = qualified_error_parts(qualified)

      [
        %{
          source_id: source_id,
          kind: kind,
          source_sheet: namespace,
          source_variable: variable,
          resolution_key: {:qualified, qualified}
        }
      ]
    end
  end

  defp qualified_specs(_source_id, _kind, _qualified), do: []

  defp qualified_error_parts(qualified) do
    case List.pop_at(String.split(qualified, "."), -1) do
      {variable, namespace_parts} when namespace_parts != [] ->
        {Enum.join(namespace_parts, "."), variable}

      _invalid ->
        {qualified, qualified}
    end
  end

  defp resolution_key(namespace, variable) do
    case String.split(variable, ".", parts: 3) do
      [table, row, column] -> {:table, namespace, table, row, column}
      _regular -> {:regular, namespace, variable}
    end
  end

  defp validate_resolvable_specs(_project_id, []), do: :ok

  defp validate_resolvable_specs(project_id, specs) do
    resolved = resolve_specs(project_id, specs)

    case Enum.find(specs, &(not Map.has_key?(resolved, &1.resolution_key))) do
      nil ->
        :ok

      spec ->
        {:error,
         {:unresolved_variable_reference, source_type(spec), spec.source_id, spec.kind, spec.source_sheet,
          spec.source_variable}}
    end
  end

  defp source_type(%{source_type: source_type}), do: source_type
  defp source_type(_spec), do: "scene"

  defp resolve_specs(project_id, specs) do
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
    namespaces = keys |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    namespace_ids = VariableNamespaces.resolve_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    sheet_ids = Map.keys(namespace_by_id)
    variable_names = keys |> Enum.map(&elem(&1, 2)) |> Enum.uniq()

    from(block in BlockRecord,
      join: sheet in SheetRecord,
      on: sheet.id == block.sheet_id,
      where:
        sheet.project_id == ^project_id and sheet.id in ^sheet_ids and
          block.variable_name in ^variable_names and block.type in ^@regular_variable_types and
          block.is_constant == false and is_nil(sheet.deleted_at) and
          is_nil(block.deleted_at),
      select: {sheet.id, block.variable_name, block.id}
    )
    |> Repo.all()
    |> Map.new(fn {sheet_id, variable_name, block_id} ->
      {{:regular, Map.fetch!(namespace_by_id, sheet_id), variable_name}, block_id}
    end)
  end

  defp resolve_tables(_project_id, []), do: %{}

  # Ecto's boolean query AST is intentionally counted as branching by Credo.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp resolve_tables(project_id, keys) do
    namespaces = keys |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    namespace_ids = VariableNamespaces.resolve_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    sheet_ids = Map.keys(namespace_by_id)
    table_names = keys |> Enum.map(&elem(&1, 2)) |> Enum.uniq()
    row_slugs = keys |> Enum.map(&elem(&1, 3)) |> Enum.uniq()
    column_slugs = keys |> Enum.map(&elem(&1, 4)) |> Enum.uniq()

    from(block in BlockRecord, as: :block)
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
    |> where(
      [block: block, sheet: sheet, row: row, column: column],
      sheet.project_id == ^project_id and sheet.id in ^sheet_ids and
        block.variable_name in ^table_names and row.slug in ^row_slugs and
        column.slug in ^column_slugs and is_nil(sheet.deleted_at) and
        is_nil(block.deleted_at) and block.type == "table" and
        column.type in ^@table_variable_types and
        (column.is_constant == false or column.type in ^@constant_table_variable_types)
    )
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

  defp resolve_qualified(_project_id, []), do: %{}

  defp resolve_qualified(project_id, qualified_refs) do
    regular =
      Repo.all(
        from block in BlockRecord,
          join: sheet in SheetRecord,
          on: sheet.id == block.sheet_id,
          where:
            sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
              is_nil(block.deleted_at) and block.type in ^@regular_variable_types and
              block.is_constant == false and not is_nil(block.variable_name) and
              block.variable_name != "" and
              VariableNamespaces.authoritative_namespace_owner?(sheet) and
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

    tables = qualified_table_rows(project_id, qualified_refs)

    Map.new(regular ++ tables, fn {qualified, namespace, variable, block_id} ->
      {{:qualified, qualified}, %{block_id: block_id, source_sheet: namespace, source_variable: variable}}
    end)
  end

  # Ecto's boolean query AST is intentionally counted as branching by Credo.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp qualified_table_rows(project_id, qualified_refs) do
    from(column in TableColumnRecord, as: :column)
    |> join(:inner, [column: column], block in BlockRecord,
      as: :block,
      on: block.id == column.block_id
    )
    |> join(:inner, [block: block], sheet in SheetRecord,
      as: :sheet,
      on: sheet.id == block.sheet_id
    )
    |> join(:inner, [block: block], row in TableRowRecord,
      as: :row,
      on: row.block_id == block.id
    )
    |> where(
      [column: column, block: block, sheet: sheet, row: row],
      sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
        is_nil(block.deleted_at) and not is_nil(block.variable_name) and
        block.variable_name != "" and block.type == "table" and
        column.type in ^@table_variable_types and
        (column.is_constant == false or column.type in ^@constant_table_variable_types) and
        VariableNamespaces.authoritative_namespace_owner?(sheet) and
        fragment(
          "COALESCE(?, CAST(? AS TEXT)) || '.' || ? || '.' || ? || '.' || ?",
          sheet.shortcut,
          sheet.id,
          block.variable_name,
          row.slug,
          column.slug
        ) in ^qualified_refs
    )
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

  defp strict_source_specs(%{} = source) do
    source_type = Map.get(source, :source_type) || Map.get(source, "source_type")
    source_id = Map.get(source, :source_id) || Map.get(source, "source_id")

    result =
      case source_type do
        type when type in ["scene_pin", "scene_zone"] ->
          strict_scene_element_reference_specs(source, type, source_id)

        "scene_ambient_flow" ->
          strict_scene_ambient_flow_reference_specs(source, source_id)

        invalid_type ->
          {:error, {:invalid_variable_reference_source_type, invalid_type, source_id}}
      end

    tag_source_type(result, source_type)
  end

  defp strict_source_specs(source), do: {:error, {:invalid_variable_reference_source, :scene, source}}

  defp strict_scene_element_reference_specs(source, source_type, source_id) do
    action_data = scene_element_action_data(source)

    if is_integer(source_id) and is_map(action_data) do
      element = %{
        id: source_id,
        action_type: Map.get(source, :action_type) || Map.get(source, "action_type"),
        action_data: action_data,
        condition: Map.get(source, :condition) || Map.get(source, "condition")
      }

      with {:ok, action_specs} <- strict_scene_action_reference_specs(element, source_type),
           {:ok, condition_specs} <- strict_condition_reference_specs(source_type, source_id, element.condition) do
        {:ok, action_specs ++ condition_specs}
      end
    else
      {:error, {:invalid_variable_reference_source, source_type, source_id}}
    end
  end

  defp scene_element_action_data(source) do
    case Map.get(source, :action_data, Map.get(source, "action_data")) do
      nil -> %{}
      value -> value
    end
  end

  defp strict_scene_action_reference_specs(element, source_type) do
    case element.action_type do
      "action" ->
        strict_assignment_list_specs(
          source_type,
          element.id,
          Map.get(element.action_data, "assignments", [])
        )

      "display" ->
        strict_draftable_qualified_reference_specs(
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

  defp strict_scene_ambient_flow_reference_specs(source, source_id) when is_integer(source_id) do
    trigger_type = Map.get(source, :trigger_type) || Map.get(source, "trigger_type")
    trigger_config = Map.get(source, :trigger_config) || Map.get(source, "trigger_config") || %{}

    case {trigger_type, trigger_config} do
      {"on_event", config} when is_map(config) ->
        strict_ambient_event_reference_specs(config["variable_ref"], source_id)

      {type, _config} when is_binary(type) ->
        {:ok, []}

      _invalid ->
        invalid_ambient_flow_source(source_id)
    end
  end

  defp strict_scene_ambient_flow_reference_specs(_source, source_id), do: invalid_ambient_flow_source(source_id)

  defp strict_ambient_event_reference_specs(value, _source_id) when value in [nil, ""], do: {:ok, []}

  defp strict_ambient_event_reference_specs(value, source_id) do
    strict_qualified_variable_reference_specs(
      "scene_ambient_flow",
      source_id,
      value,
      :ambient_event_variable_ref
    )
  end

  defp invalid_ambient_flow_source(source_id),
    do: {:error, {:invalid_variable_reference_source, "scene_ambient_flow", source_id}}

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

  defp strict_collection_item_reference_specs(source_type, source_id, items),
    do: malformed(source_type, source_id, :collection_items, items)

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

  defp strict_collection_item_reference_specs(source_type, source_id, item, index),
    do: malformed(source_type, source_id, {:collection_item, index}, item)

  defp strict_collection_item_condition_specs(_source_type, _source_id, nil, _index), do: {:ok, []}

  defp strict_collection_item_condition_specs(_source_type, _source_id, condition, _index)
       when is_map(condition) and map_size(condition) == 0, do: {:ok, []}

  defp strict_collection_item_condition_specs(source_type, source_id, condition, index) do
    case strict_condition_reference_specs(source_type, source_id, condition) do
      {:error, {:malformed_variable_reference, ^source_type, ^source_id, :condition, _value}} ->
        malformed(source_type, source_id, {:collection_item_condition, index}, condition)

      result ->
        result
    end
  end

  defp strict_collection_item_instruction_specs(_source_type, _source_id, nil, _index), do: {:ok, []}

  defp strict_collection_item_instruction_specs(source_type, source_id, %{} = instruction, index) do
    case strict_assignment_list_specs(source_type, source_id, Map.get(instruction, "assignments", [])) do
      {:error, {:malformed_variable_reference, ^source_type, ^source_id, :assignments, _value}} ->
        malformed(
          source_type,
          source_id,
          {:collection_item_assignments, index},
          Map.get(instruction, "assignments")
        )

      result ->
        result
    end
  end

  defp strict_collection_item_instruction_specs(source_type, source_id, instruction, index),
    do: malformed(source_type, source_id, {:collection_item_instruction, index}, instruction)

  defp strict_assignment_list_specs(_source_type, _source_id, []), do: {:ok, []}

  defp strict_assignment_list_specs(source_type, source_id, assignments) when is_list(assignments) do
    Enum.reduce_while(assignments, {:ok, []}, fn assignment, {:ok, specs} ->
      case strict_assignment_reference_specs(source_type, source_id, assignment) do
        {:ok, assignment_specs} -> {:cont, {:ok, specs ++ assignment_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp strict_assignment_list_specs(source_type, source_id, assignments),
    do: malformed(source_type, source_id, :assignments, assignments)

  defp strict_assignment_reference_specs(source_type, source_id, %{} = assignment) do
    with {:ok, write_specs} <-
           strict_draftable_reference_specs(
             source_type,
             source_id,
             "write",
             assignment["sheet"],
             assignment["variable"],
             :assignment_target
           ),
         {:ok, read_specs} <- strict_assignment_read_specs(source_type, source_id, assignment) do
      {:ok, write_specs ++ read_specs}
    end
  end

  defp strict_assignment_reference_specs(source_type, source_id, assignment),
    do: malformed(source_type, source_id, :assignment, assignment)

  defp strict_assignment_read_specs(source_type, source_id, %{"value_type" => "variable_ref"} = assignment) do
    strict_draftable_reference_specs(
      source_type,
      source_id,
      "read",
      assignment["value_sheet"],
      assignment["value"],
      :assignment_value
    )
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
        malformed(source_type, source_id, :condition, condition)
    end
  end

  defp strict_condition_reference_specs(source_type, source_id, condition),
    do: malformed(source_type, source_id, :condition, condition)

  defp strict_condition_rule_specs(rules, source_type, source_id) do
    Enum.reduce_while(rules, {:ok, []}, fn rule, {:ok, specs} ->
      case strict_draftable_reference_specs(
             source_type,
             source_id,
             "read",
             rule["sheet"],
             rule["variable"],
             :condition_rule
           ) do
        {:ok, rule_specs} -> {:cont, {:ok, specs ++ rule_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp strict_draftable_reference_specs(source_type, source_id, kind, sheet_shortcut, variable_name, context) do
    cond do
      nonempty_reference_part?(sheet_shortcut) and nonempty_reference_part?(variable_name) ->
        case reference_specs(source_id, kind, sheet_shortcut, variable_name) do
          [spec] -> {:ok, [spec]}
          [] -> malformed(source_type, source_id, context, {sheet_shortcut, variable_name})
        end

      draft_reference_pair?(sheet_shortcut, variable_name) ->
        {:ok, []}

      true ->
        malformed(source_type, source_id, context, {sheet_shortcut, variable_name})
    end
  end

  defp nonempty_reference_part?(value), do: is_binary(value) and String.trim(value) != ""

  defp draft_reference_pair?(sheet_shortcut, variable_name) do
    (sheet_shortcut in [nil, ""] and variable_name in [nil, ""]) or
      (nonempty_reference_part?(sheet_shortcut) and variable_name in [nil, ""])
  end

  defp strict_qualified_variable_reference_specs(source_type, source_id, value, context) when is_binary(value) do
    case qualified_specs(source_id, "read", value) do
      [spec] -> {:ok, [spec]}
      [] -> malformed(source_type, source_id, context, value)
    end
  end

  defp strict_qualified_variable_reference_specs(source_type, source_id, value, context),
    do: malformed(source_type, source_id, context, value)

  defp strict_draftable_qualified_reference_specs(_source_type, _source_id, value, _context) when value in [nil, ""],
    do: {:ok, []}

  defp strict_draftable_qualified_reference_specs(source_type, source_id, value, context),
    do: strict_qualified_variable_reference_specs(source_type, source_id, value, context)

  defp tag_source_type({:ok, specs}, source_type), do: {:ok, Enum.map(specs, &Map.put(&1, :source_type, source_type))}

  defp tag_source_type({:error, _reason} = error, _source_type), do: error

  defp malformed(source_type, source_id, context, value),
    do: {:error, {:malformed_variable_reference, source_type, source_id, context, value}}

  defp list_value(value) when is_list(value), do: value
  defp list_value(_value), do: []
end
