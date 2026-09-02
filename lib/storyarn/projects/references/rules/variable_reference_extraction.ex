defmodule Storyarn.Projects.References.VariableReferenceExtraction do
  @moduledoc """
  Pure extraction and validation-shape rules for variable references authored
  by Flows and Scenes.

  It converts persisted structs and snapshot maps into normalized reference
  specs. Resolution against active Sheets and persistence are deliberately
  owned by separate query and command modules.
  """

  alias Storyarn.Projects.References.FlowCondition
  alias Storyarn.Projects.References.Persistence.FlowNodeRecord

  @spec strict_flow_node_specs(map() | struct()) :: {:ok, [map()]} | {:error, term()}
  def strict_flow_node_specs(node), do: strict_flow_node_reference_specs(node)

  @spec strict_snapshot_source_specs(map()) ::
          {:ok, String.t(), [map()]} | {:error, term()}
  def strict_snapshot_source_specs(source), do: strict_snapshot_source_reference_specs(source)

  @spec strict_scene_element_specs(map(), String.t()) ::
          {:ok, [map()]} | {:error, term()}
  def strict_scene_element_specs(element, source_type), do: strict_scene_element_reference_specs(element, source_type)

  @spec flow_node_specs(map()) :: [map()]
  def flow_node_specs(node), do: flow_node_reference_specs(node)

  @spec qualified_specs(integer(), String.t(), term()) :: [map()]
  def qualified_specs(source_id, kind, qualified_ref), do: qualified_reference_specs(source_id, kind, qualified_ref)

  @spec flow_snapshot_source(map()) :: map()
  def flow_snapshot_source(node), do: flow_snapshot_variable_source(node)

  @spec scene_element_specs(map()) :: [map()]
  def scene_element_specs(element), do: scene_element_reference_specs(element)

  @spec ambient_flow_specs(map()) :: [map()]
  def ambient_flow_specs(%{trigger_type: "on_event", trigger_config: %{"variable_ref" => variable_ref}}),
    do: qualified_reference_specs(0, "read", variable_ref)

  def ambient_flow_specs(_ambient_flow), do: []

  @spec expected_flow_node_reference_sets([map()], map()) :: map()
  def expected_flow_node_reference_sets(specs, resolved_block_ids),
    do: build_expected_flow_node_reference_sets(specs, resolved_block_ids)

  @spec resolve_specs([map()], map()) :: [map()]
  def resolve_specs(specs, resolved_block_ids),
    do: Enum.flat_map(specs, &resolved_flow_node_reference(&1, resolved_block_ids))

  @spec entity_snapshot_sources(String.t(), map()) :: {:ok, [map()]} | {:error, term()}
  def entity_snapshot_sources("flow", %{} = snapshot) do
    with {:ok, nodes} <- snapshot_reference_collection(snapshot, "flow", "nodes") do
      {:ok, Enum.map(nodes, &flow_snapshot_variable_source/1)}
    end
  end

  def entity_snapshot_sources("scene", %{} = snapshot) do
    with {:ok, layers} <- snapshot_reference_collection(snapshot, "scene", "layers"),
         {:ok, layer_pins} <- layer_snapshot_variable_sources(layers, "pins", "scene_pin"),
         {:ok, layer_zones} <- layer_snapshot_variable_sources(layers, "zones", "scene_zone"),
         {:ok, orphan_pins} <- snapshot_reference_collection(snapshot, "scene", "orphan_pins"),
         {:ok, orphan_zones} <- snapshot_reference_collection(snapshot, "scene", "orphan_zones"),
         {:ok, ambient_flows} <- snapshot_reference_collection(snapshot, "scene", "ambient_flows") do
      {:ok,
       layer_pins ++
         layer_zones ++
         scene_snapshot_variable_sources(orphan_pins, "scene_pin") ++
         scene_snapshot_variable_sources(orphan_zones, "scene_zone") ++
         Enum.map(ambient_flows, &scene_ambient_snapshot_variable_source/1)}
    end
  end

  def entity_snapshot_sources("sheet", %{}), do: {:ok, []}

  def entity_snapshot_sources(entity_type, snapshot),
    do: {:error, {:invalid_variable_reference_entity_snapshot, entity_type, snapshot}}

  defp strict_flow_node_reference_specs(%FlowNodeRecord{id: source_id, type: type, data: data})
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
    source_id =
      Map.get(node, "original_id") || Map.get(node, :original_id) ||
        Map.get(node, "id") || Map.get(node, :id)

    type = Map.get(node, "type") || Map.get(node, :type)
    data = Map.get(node, "data") || Map.get(node, :data)

    if is_integer(source_id) and is_binary(type) and is_map(data) do
      strict_flow_node_reference_specs(%FlowNodeRecord{id: source_id, type: type, data: data})
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
      "action_data" => scene_element_action_data(source),
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
    case config["variable_ref"] do
      value when value in [nil, ""] ->
        {:ok, []}

      value ->
        strict_qualified_variable_reference_specs(
          "scene_ambient_flow",
          source_id,
          value,
          :ambient_event_variable_ref
        )
    end
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

    action_data = scene_element_action_data(element)

    if is_integer(source_id) and is_map(action_data) do
      normalized = %{
        id: source_id,
        action_type: Map.get(element, :action_type) || Map.get(element, "action_type"),
        action_data: action_data,
        condition: Map.get(element, :condition) || Map.get(element, "condition")
      }

      strict_scene_element_reference_specs(normalized, source_type)
    else
      {:error, {:invalid_variable_reference_source, source_type, source_id}}
    end
  end

  defp strict_scene_element_reference_specs(element, source_type),
    do: {:error, {:invalid_variable_reference_source, source_type, element}}

  defp scene_element_action_data(element) do
    case Map.get(element, :action_data, Map.get(element, "action_data")) do
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
    with {:ok, write_specs} <-
           strict_draftable_reference_specs(
             source_type,
             source_id,
             "write",
             assignment["sheet"],
             assignment["variable"],
             :assignment_target
           ),
         {:ok, read_specs} <-
           strict_assignment_read_specs(source_type, source_id, assignment) do
      {:ok, write_specs ++ read_specs}
    end
  end

  defp strict_assignment_reference_specs(source_type, source_id, assignment) do
    malformed_variable_reference(source_type, source_id, :assignment, assignment)
  end

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
    case FlowCondition.validate(condition) do
      {:ok, valid_condition} ->
        valid_condition
        |> FlowCondition.extract_all_rules()
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
    case strict_draftable_reference_specs(
           source_type,
           source_id,
           "read",
           rule["sheet"],
           rule["variable"],
           :condition_rule
         ) do
      {:ok, rule_specs} -> {:cont, {:ok, rule_specs ++ specs}}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp strict_draftable_reference_specs(source_type, source_id, kind, sheet_shortcut, variable_name, context) do
    cond do
      nonempty_reference_part?(sheet_shortcut) and nonempty_reference_part?(variable_name) ->
        case strict_required_reference_spec(
               source_type,
               source_id,
               kind,
               sheet_shortcut,
               variable_name,
               context
             ) do
          {:ok, spec} -> {:ok, [spec]}
          {:error, _reason} = error -> error
        end

      draft_reference_pair?(sheet_shortcut, variable_name) ->
        {:ok, []}

      true ->
        malformed_variable_reference(
          source_type,
          source_id,
          context,
          {sheet_shortcut, variable_name}
        )
    end
  end

  defp nonempty_reference_part?(value), do: is_binary(value) and String.trim(value) != ""

  defp draft_reference_pair?(sheet_shortcut, variable_name) do
    (sheet_shortcut in [nil, ""] and variable_name in [nil, ""]) or
      (nonempty_reference_part?(sheet_shortcut) and variable_name in [nil, ""])
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

  defp strict_draftable_qualified_reference_specs(_source_type, _source_id, value, _context) when value in [nil, ""],
    do: {:ok, []}

  defp strict_draftable_qualified_reference_specs(source_type, source_id, value, context),
    do: strict_qualified_variable_reference_specs(source_type, source_id, value, context)

  defp snapshot_reference_collection(snapshot, entity_type, key) do
    case Map.fetch(snapshot, key) do
      {:ok, values} when is_list(values) ->
        if Enum.all?(values, &is_map/1) do
          {:ok, values}
        else
          {:error, {:invalid_variable_reference_snapshot_collection, entity_type, key, values}}
        end

      {:ok, value} ->
        {:error, {:invalid_variable_reference_snapshot_collection, entity_type, key, value}}

      :error ->
        {:error, {:missing_variable_reference_snapshot_collection, entity_type, key}}
    end
  end

  defp layer_snapshot_variable_sources(layers, child_key, source_type) do
    Enum.reduce_while(layers, {:ok, []}, fn layer, {:ok, sources} ->
      case snapshot_reference_collection(layer, "scene_layer", child_key) do
        {:ok, children} ->
          child_sources = scene_snapshot_variable_sources(children, source_type)
          {:cont, {:ok, sources ++ child_sources}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp scene_snapshot_variable_sources(elements, source_type) when is_list(elements) do
    Enum.map(elements, &scene_snapshot_variable_source(source_type, &1))
  end

  defp flow_snapshot_variable_source(node) do
    %{
      source_type: "flow_node",
      source_id: node["original_id"],
      type: node["type"],
      data: node["data"]
    }
  end

  defp scene_snapshot_variable_source(source_type, element) do
    %{
      source_type: source_type,
      source_id: element["original_id"],
      action_type: element["action_type"],
      action_data: element["action_data"],
      condition: element["condition"]
    }
  end

  defp scene_ambient_snapshot_variable_source(ambient_flow) do
    %{
      source_type: "scene_ambient_flow",
      source_id: ambient_flow["original_id"],
      trigger_type: ambient_flow["trigger_type"],
      trigger_config: ambient_flow["trigger_config"]
    }
  end

  defp malformed_variable_reference(source_type, source_id, context, value) do
    {:error, {:malformed_variable_reference, source_type, source_id, context, value}}
  end

  defp flow_node_reference_specs(%{id: node_id, type: "instruction", data: data}) do
    data
    |> Map.get("assignments", [])
    |> list_value()
    |> Enum.flat_map(&assignment_reference_specs(node_id, &1))
  end

  defp flow_node_reference_specs(%{id: node_id, type: "condition", data: data}) do
    data
    |> Map.get("condition")
    |> FlowCondition.extract_all_rules()
    |> Enum.flat_map(&condition_rule_reference_specs(node_id, &1))
  end

  defp flow_node_reference_specs(%{id: node_id, type: "dialogue", data: data}) do
    data
    |> Map.get("responses", [])
    |> list_value()
    |> Enum.flat_map(&dialogue_response_reference_specs(node_id, &1))
  end

  defp flow_node_reference_specs(%{id: _node_id, type: _type, data: _data}), do: []

  defp dialogue_response_reference_specs(node_id, %{} = response) do
    response_condition_reference_specs(node_id, response["condition"]) ++
      response_assignment_reference_specs(node_id, response)
  end

  defp dialogue_response_reference_specs(_node_id, _response), do: []

  defp response_condition_reference_specs(node_id, condition) when is_binary(condition) do
    condition
    |> FlowCondition.parse()
    |> condition_reference_specs(node_id)
  end

  defp response_condition_reference_specs(node_id, condition), do: condition_reference_specs(condition, node_id)

  defp condition_reference_specs(condition, node_id) do
    condition
    |> FlowCondition.extract_all_rules()
    |> Enum.flat_map(&condition_rule_reference_specs(node_id, &1))
  end

  defp condition_rule_reference_specs(node_id, %{} = rule) do
    reference_specs(node_id, "read", rule["sheet"], rule["variable"])
  end

  defp condition_rule_reference_specs(_node_id, _rule), do: []

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

  defp build_expected_flow_node_reference_sets(specs, resolved_block_ids) do
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

  defp list_value(value) when is_list(value), do: value
  defp list_value(_value), do: []

  defp scene_element_reference_specs(element) do
    source_id = Map.get(element, :id)

    scene_action_reference_specs(element, source_id) ++
      condition_reference_specs(Map.get(element, :condition), source_id)
  end

  # Shared extraction for action_type + action_data (zones and pins)
  defp scene_action_reference_specs(element, source_id) do
    action_data = scene_element_action_data(element)

    case Map.get(element, :action_type) do
      "action" ->
        action_data
        |> Map.get("assignments", [])
        |> list_value()
        |> Enum.flat_map(&assignment_reference_specs(source_id, &1))

      "display" ->
        qualified_reference_specs(source_id, "read", Map.get(action_data, "variable_ref"))

      "collection" ->
        action_data
        |> Map.get("items", [])
        |> list_value()
        |> Enum.flat_map(&collection_item_reference_specs(source_id, &1))

      _ ->
        []
    end
  end

  defp collection_item_reference_specs(source_id, %{} = item) do
    condition_specs = condition_reference_specs(Map.get(item, "condition"), source_id)

    assignment_specs =
      item
      |> Map.get("instruction")
      |> collection_instruction_assignments()
      |> Enum.flat_map(&assignment_reference_specs(source_id, &1))

    condition_specs ++ assignment_specs
  end

  defp collection_item_reference_specs(_source_id, _item), do: []

  defp collection_instruction_assignments(%{} = instruction) do
    instruction
    |> Map.get("assignments", [])
    |> list_value()
  end

  defp collection_instruction_assignments(_instruction), do: []
end
