defmodule Storyarn.Flows.NodeEditor do
  @moduledoc """
  Flow-owned transitions for node data authored through the editor.

  These functions keep LiveView as an adapter: Web extracts event parameters,
  while Flows decides how persisted node data changes.
  """

  alias Storyarn.Flows.EditorCatalog
  alias Storyarn.Flows.Expressions
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowCrud
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.HubColors
  alias Storyarn.Flows.NodeCreate
  alias Storyarn.Flows.NodeCrud
  alias Storyarn.Flows.NodeTypes
  alias Storyarn.Flows.RuntimeKey

  @annotation_font_sizes ~w(sm md lg)
  @default_exit_color "#22c55e"
  @hex_color_regex ~r/\A#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\z/

  @editable_fields %{
    "annotation" => ~w(text color font_size),
    "condition" => ~w(condition switch_mode),
    "dialogue" =>
      ~w(speaker_sheet_id text stage_directions menu_text audio_asset_id technical_id localization_id avatar_id),
    "entry" => [],
    "exit" => ~w(label technical_id outcome_tags outcome_color exit_mode referenced_flow_id target_type target_id),
    "hub" => ~w(hub_id label color),
    "instruction" => ~w(assignments description),
    "jump" => ~w(target_hub_id),
    "subflow" => ~w(referenced_flow_id)
  }
  @restorable_fields @editable_fields
                     |> Map.update!("dialogue", &["responses" | &1])
                     |> Map.update!("dialogue", &List.delete(&1, "localization_id"))

  @type operation ::
          :add_exit_outcome_tag
          | :append_dialogue_response
          | :generate_technical_id
          | :merge_form
          | :put_annotation_color
          | :put_annotation_font_size
          | :put_condition
          | :put_exit_color
          | :put_exit_flow_reference
          | :put_exit_mode
          | :put_exit_target
          | :put_field
          | :put_hub_color
          | :put_instruction_assignments
          | :put_response_assignments
          | :put_response_condition
          | :put_response_condition_builder
          | :put_response_instruction
          | :put_response_text
          | :put_subflow_reference
          | :remove_dialogue_response
          | :remove_exit_outcome_tag
          | :restore_data
          | :toggle_condition_switch_mode

  @doc """
  Applies one closed editor operation to the data of a locked Flow node.

  The caller is responsible for acquiring the row lock before invoking this
  function. Keeping the operation vocabulary here prevents Web from sending
  arbitrary update callbacks or unrestricted JSON fields into persistence.
  """
  @spec apply_operation(FlowNode.t(), Flow.t(), pos_integer(), operation(), map()) ::
          {:ok, map()} | {:error, term()}
  def apply_operation(%FlowNode{} = node, %Flow{} = flow, project_id, operation, payload)
      when is_integer(project_id) and project_id > 0 and is_map(payload) do
    do_apply_operation(node, flow, project_id, operation, payload, node.data || %{})
  end

  defp do_apply_operation(node, _flow, _project_id, :merge_form, payload, data) do
    with {:ok, params} <- require_payload_map(payload, :params) do
      {:ok, merge_editable_fields(node.type, data, params)}
    end
  end

  defp do_apply_operation(node, _flow, _project_id, :restore_data, payload, data) do
    with {:ok, restored_data} <- require_payload_map(payload, :data) do
      defaults = NodeTypes.default_data(node.type)
      extension_fields = Map.keys(data) -- Map.keys(defaults)
      snapshot_data = stringify_keys(restored_data)

      restored_data =
        Map.take(snapshot_data, Map.get(@restorable_fields, node.type, []) ++ extension_fields)

      base_data =
        defaults
        |> Map.merge(Map.take(data, extension_fields))
        |> preserve_runtime_identity(node.type, data, snapshot_data)

      {:ok, Map.merge(base_data, restored_data)}
    end
  end

  defp do_apply_operation(node, _flow, _project_id, :put_field, payload, data) do
    field = payload_value(payload, :field)

    if is_binary(field) and field in editable_fields(node.type) do
      {:ok, Map.put(data, field, normalize_field_value(field, payload_value(payload, :value)))}
    else
      {:error, :field_not_editable}
    end
  end

  defp do_apply_operation(%FlowNode{type: "condition"}, _flow, _project_id, :put_condition, payload, data) do
    {:ok, put_condition(data, payload_value(payload, :condition) || %{})}
  end

  defp do_apply_operation(%FlowNode{type: "dialogue"}, _flow, _project_id, :put_response_condition_builder, payload, data) do
    {:ok,
     put_response_condition(
       data,
       payload_value(payload, :response_id),
       payload_value(payload, :condition) || %{}
     )}
  end

  defp do_apply_operation(%FlowNode{type: "condition"}, _flow, _project_id, :toggle_condition_switch_mode, _payload, data) do
    {:ok, toggle_condition_switch_mode(data)}
  end

  defp do_apply_operation(%FlowNode{type: "dialogue"}, _flow, _project_id, :append_dialogue_response, _payload, data) do
    {:ok, append_dialogue_response(data)}
  end

  defp do_apply_operation(%FlowNode{type: "dialogue"}, _flow, _project_id, :remove_dialogue_response, payload, data) do
    {:ok, remove_dialogue_response(data, payload_value(payload, :response_id))}
  end

  defp do_apply_operation(%FlowNode{type: "dialogue"}, _flow, _project_id, operation, payload, data)
       when operation in [
              :put_response_text,
              :put_response_condition,
              :put_response_instruction,
              :put_response_assignments
            ] do
    response_id = payload_value(payload, :response_id)
    value = payload_value(payload, :value)

    updated_data =
      case operation do
        :put_response_text -> put_dialogue_response_text(data, response_id, value)
        :put_response_condition -> put_dialogue_response_condition(data, response_id, value)
        :put_response_instruction -> put_dialogue_response_instruction(data, response_id, value)
        :put_response_assignments -> put_dialogue_response_assignments(data, response_id, value || [])
      end

    {:ok, updated_data}
  end

  defp do_apply_operation(%FlowNode{type: "exit"}, _flow, _project_id, :put_exit_mode, payload, data) do
    {:ok, put_exit_mode(data, payload_value(payload, :value))}
  end

  defp do_apply_operation(%FlowNode{type: "exit"}, %Flow{} = flow, project_id, :put_exit_flow_reference, payload, data) do
    with {:ok, flow_id} <-
           validate_exit_flow_reference(project_id, flow.id, payload_value(payload, :value)) do
      {:ok, put_exit_flow_reference(data, flow_id)}
    end
  end

  defp do_apply_operation(%FlowNode{type: "exit"}, _flow, _project_id, :add_exit_outcome_tag, payload, data) do
    {:ok, add_exit_outcome_tag(data, payload_value(payload, :value))}
  end

  defp do_apply_operation(%FlowNode{type: "exit"}, _flow, _project_id, :remove_exit_outcome_tag, payload, data) do
    {:ok, remove_exit_outcome_tag(data, payload_value(payload, :value))}
  end

  defp do_apply_operation(%FlowNode{type: "exit"}, _flow, _project_id, :put_exit_color, payload, data) do
    {:ok, put_exit_color(data, payload_value(payload, :value))}
  end

  defp do_apply_operation(%FlowNode{type: "exit"}, _flow, _project_id, :put_exit_target, payload, data) do
    {:ok, put_exit_target(data, payload_value(payload, :target_type), payload_value(payload, :target_id))}
  end

  defp do_apply_operation(%FlowNode{type: "subflow"}, %Flow{} = flow, _project_id, :put_subflow_reference, payload, data) do
    with {:ok, flow_id} <- validate_subflow_reference(payload_value(payload, :value), flow.id) do
      {:ok, put_subflow_reference(data, flow_id)}
    end
  end

  defp do_apply_operation(%FlowNode{type: "instruction"}, _flow, _project_id, :put_instruction_assignments, payload, data) do
    {:ok, put_instruction_assignments(data, payload_value(payload, :assignments) || [])}
  end

  defp do_apply_operation(%FlowNode{type: "annotation"}, _flow, _project_id, :put_annotation_color, payload, data) do
    {:ok, put_annotation_color(data, payload_value(payload, :value))}
  end

  defp do_apply_operation(%FlowNode{type: "annotation"}, _flow, _project_id, :put_annotation_font_size, payload, data) do
    {:ok, put_annotation_font_size(data, payload_value(payload, :value))}
  end

  defp do_apply_operation(%FlowNode{type: "hub"}, _flow, _project_id, :put_hub_color, payload, data) do
    {:ok, put_hub_color(data, payload_value(payload, :value))}
  end

  defp do_apply_operation(%FlowNode{} = node, %Flow{} = flow, project_id, :generate_technical_id, _payload, data)
       when node.type in ["dialogue", "exit"] do
    technical_id =
      case node.type do
        "dialogue" -> dialogue_technical_id(flow, node, speaker_name(project_id, data))
        "exit" -> exit_technical_id(flow, node)
      end

    {:ok, Map.put(data, "technical_id", technical_id)}
  end

  defp do_apply_operation(_node, _flow, _project_id, _operation, _payload, _data) do
    {:error, :invalid_node_operation}
  end

  @spec put_condition(map(), map()) :: map()
  def put_condition(data, condition) when is_map(data) do
    Map.put(data, "condition", Expressions.condition_sanitize(condition))
  end

  @spec put_response_condition(map(), term(), map()) :: map()
  def put_response_condition(data, response_id, condition) when is_map(data) do
    update_response(data, response_id, fn response ->
      Map.put(response, "condition", Expressions.condition_sanitize(condition))
    end)
  end

  @spec toggle_condition_switch_mode(map()) :: map()
  def toggle_condition_switch_mode(data) when is_map(data) do
    enabled? = not (data["switch_mode"] || false)
    condition = maybe_add_switch_labels(data["condition"], enabled?)

    data
    |> Map.put("switch_mode", enabled?)
    |> Map.put("condition", condition)
  end

  @spec append_dialogue_response(map(), String.t()) :: map()
  def append_dialogue_response(data, default_text) when is_map(data) and is_binary(default_text) do
    response = %{
      "id" => RuntimeKey.new_response_id(),
      "text" => default_text,
      "condition" => nil,
      "instruction" => nil,
      "instruction_assignments" => []
    }

    Map.update(data, "responses", [response], &(&1 ++ [response]))
  end

  @spec append_dialogue_response(map()) :: map()
  def append_dialogue_response(data) when is_map(data) do
    default_text =
      Gettext.dgettext(
        Storyarn.Gettext,
        "flows",
        "Response %{n}",
        n: next_dialogue_response_number(data)
      )

    append_dialogue_response(data, default_text)
  end

  @spec next_dialogue_response_number(map()) :: pos_integer()
  def next_dialogue_response_number(data) when is_map(data) do
    length(data["responses"] || []) + 1
  end

  @spec remove_dialogue_response(map(), term()) :: map()
  def remove_dialogue_response(data, response_id) when is_map(data) do
    Map.update(data, "responses", [], fn responses ->
      Enum.reject(responses, &(&1["id"] == response_id))
    end)
  end

  @spec put_dialogue_response_text(map(), term(), term()) :: map()
  def put_dialogue_response_text(data, response_id, text) do
    put_response_field(data, response_id, "text", text)
  end

  @spec put_dialogue_response_condition(map(), term(), term()) :: map()
  def put_dialogue_response_condition(data, response_id, condition) do
    put_response_field(data, response_id, "condition", blank_to_nil(condition))
  end

  @spec put_dialogue_response_instruction(map(), term(), term()) :: map()
  def put_dialogue_response_instruction(data, response_id, instruction) do
    put_response_field(data, response_id, "instruction", blank_to_nil(instruction))
  end

  @spec put_dialogue_response_assignments(map(), term(), list()) :: map()
  def put_dialogue_response_assignments(data, response_id, assignments) do
    put_response_field(
      data,
      response_id,
      "instruction_assignments",
      Expressions.instruction_sanitize(assignments)
    )
  end

  @spec dialogue_technical_id(map(), map(), String.t() | nil) :: String.t()
  def dialogue_technical_id(flow, node, speaker_name) do
    count =
      flow
      |> flow_nodes()
      |> Enum.filter(fn candidate ->
        candidate.type == "dialogue" and
          to_string(candidate.data["speaker_sheet_id"]) ==
            to_string(node.data["speaker_sheet_id"])
      end)
      |> occurrence_number(node.id)

    flow_part = normalize_for_id(flow.shortcut || "")
    speaker_part = normalize_for_id(speaker_name || "")
    flow_part = if flow_part == "", do: "dlg", else: flow_part
    speaker_part = if speaker_part == "", do: "narrator", else: speaker_part
    "#{flow_part}_#{speaker_part}_#{count}"
  end

  defp speaker_name(project_id, data) do
    case parse_positive_id(data["speaker_sheet_id"]) do
      {:ok, speaker_id} -> EditorCatalog.speaker_name(project_id, speaker_id)
      {:error, _reason} -> nil
    end
  end

  @spec put_exit_mode(map(), term()) :: map()
  def put_exit_mode(data, mode) when is_map(data) do
    mode = normalize_exit_mode(mode)
    data = Map.put(data, "exit_mode", mode)
    data = if mode == "flow_reference", do: data, else: Map.put(data, "referenced_flow_id", nil)

    if mode == "terminal" do
      data
    else
      data |> Map.put("target_type", nil) |> Map.put("target_id", nil)
    end
  end

  @spec exit_mode(term()) :: String.t()
  def exit_mode(mode), do: normalize_exit_mode(mode)

  @spec validate_exit_flow_reference(pos_integer(), pos_integer(), term()) ::
          {:ok, pos_integer() | nil}
          | {:error, :invalid_flow_reference | :self_reference | :circular_reference | :flow_not_found}
  def validate_exit_flow_reference(_project_id, _current_flow_id, value) when value in [nil, ""], do: {:ok, nil}

  def validate_exit_flow_reference(project_id, current_flow_id, value) do
    case parse_positive_id(value) do
      {:ok, flow_id} ->
        with :ok <- reject_self_reference(current_flow_id, flow_id),
             :ok <- reject_circular_reference(current_flow_id, flow_id),
             :ok <- require_flow(project_id, flow_id) do
          {:ok, flow_id}
        end

      {:error, :invalid_flow_reference} ->
        {:ok, nil}
    end
  end

  @spec put_exit_flow_reference(map(), pos_integer() | nil) :: map()
  def put_exit_flow_reference(data, flow_id) when is_map(data) do
    Map.put(data, "referenced_flow_id", flow_id)
  end

  @spec add_exit_outcome_tag(map(), term()) :: map()
  def add_exit_outcome_tag(data, tag) when is_map(data) do
    case normalize_outcome_tag(tag) do
      "" ->
        data

      normalized ->
        Map.update(data, "outcome_tags", [normalized], &append_unique(&1, normalized))
    end
  end

  defp append_unique(values, value) do
    if value in values, do: values, else: values ++ [value]
  end

  @spec remove_exit_outcome_tag(map(), term()) :: map()
  def remove_exit_outcome_tag(data, tag) when is_map(data) do
    Map.update(data, "outcome_tags", [], &Enum.reject(&1, fn current -> current == tag end))
  end

  @spec put_exit_color(map(), term()) :: map()
  def put_exit_color(data, color) when is_map(data) do
    Map.put(data, "outcome_color", normalize_hex_color(color, @default_exit_color))
  end

  @spec put_exit_target(map(), term(), term()) :: map()
  def put_exit_target(data, type, id) when is_map(data) do
    with type when type in ~w(scene flow) <- type,
         {:ok, id} <- parse_positive_id(id) do
      data |> Map.put("target_type", type) |> Map.put("target_id", id)
    else
      _invalid -> data |> Map.put("target_type", nil) |> Map.put("target_id", nil)
    end
  end

  @spec exit_technical_id(map(), map()) :: String.t()
  def exit_technical_id(flow, node) do
    count =
      flow
      |> flow_nodes()
      |> Enum.filter(&(&1.type == "exit"))
      |> occurrence_number(node.id)

    flow_part = normalize_for_id(flow.shortcut || "")
    label_part = normalize_for_id(node.data["label"] || "")
    flow_part = if flow_part == "", do: "flow", else: flow_part
    label_part = if label_part == "", do: "exit", else: label_part
    "#{flow_part}_#{label_part}_#{count}"
  end

  @spec validate_subflow_reference(term(), pos_integer()) ::
          {:ok, pos_integer() | nil}
          | {:error, :invalid_flow_reference | :self_reference | :circular_reference}
  def validate_subflow_reference(value, _current_flow_id) when value in [nil, ""], do: {:ok, nil}

  def validate_subflow_reference(value, current_flow_id) do
    with {:ok, flow_id} <- parse_positive_id(value),
         :ok <- reject_self_reference(current_flow_id, flow_id),
         :ok <- reject_circular_reference(current_flow_id, flow_id) do
      {:ok, flow_id}
    end
  end

  @spec put_subflow_reference(map(), pos_integer() | nil) :: map()
  def put_subflow_reference(data, flow_id) when is_map(data) do
    Map.put(data, "referenced_flow_id", flow_id)
  end

  @spec put_instruction_assignments(map(), list()) :: map()
  def put_instruction_assignments(data, assignments) when is_map(data) do
    Map.put(data, "assignments", Expressions.instruction_sanitize(assignments))
  end

  @spec put_annotation_color(map(), term()) :: map()
  def put_annotation_color(data, color) when is_map(data) and is_binary(color) do
    Map.put(data, "color", color)
  end

  def put_annotation_color(data, _color), do: data

  @spec put_annotation_font_size(map(), term()) :: map()
  def put_annotation_font_size(data, size) when is_map(data) and size in @annotation_font_sizes do
    Map.put(data, "font_size", size)
  end

  def put_annotation_font_size(data, _size), do: data

  @spec put_hub_color(map(), term()) :: map()
  def put_hub_color(data, color) when is_map(data) do
    Map.put(data, "color", HubColors.resolve(color))
  end

  defp editable_fields(type), do: Map.get(@editable_fields, type, [])

  defp preserve_runtime_identity(defaults, "dialogue", data, restored_data) do
    cond do
      RuntimeKey.valid_dialogue_id?(data["localization_id"]) ->
        Map.put(defaults, "localization_id", data["localization_id"])

      RuntimeKey.valid_dialogue_id?(restored_data["localization_id"]) ->
        Map.put(defaults, "localization_id", restored_data["localization_id"])

      true ->
        defaults
    end
  end

  defp preserve_runtime_identity(defaults, _type, _data, _restored_data), do: defaults

  defp merge_editable_fields(type, data, params) do
    params =
      params
      |> stringify_keys()
      |> Map.take(editable_fields(type))
      |> Map.new(fn {field, value} -> {field, normalize_field_value(field, value)} end)

    Map.merge(data, params)
  end

  defp normalize_field_value(field, "")
       when field in ~w(speaker_sheet_id audio_asset_id avatar_id referenced_flow_id target_id), do: nil

  defp normalize_field_value(_field, value), do: value

  defp require_payload_map(payload, key) do
    case payload_value(payload, key) do
      value when is_map(value) -> {:ok, value}
      _invalid -> {:error, :invalid_node_operation_payload}
    end
  end

  defp payload_value(payload, key) do
    Map.get(payload, key, Map.get(payload, Atom.to_string(key)))
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp put_response_field(data, response_id, field, value) when is_map(data) do
    update_response(data, response_id, &Map.put(&1, field, value))
  end

  defp update_response(data, response_id, update) do
    Map.update(data, "responses", [], fn responses ->
      Enum.map(responses, fn
        %{"id" => ^response_id} = response -> update.(response)
        response -> response
      end)
    end)
  end

  defp maybe_add_switch_labels(condition, false), do: condition

  defp maybe_add_switch_labels(condition, true) do
    condition = condition || Expressions.condition_new()

    if condition["blocks"] do
      Map.update(condition, "blocks", [], fn blocks ->
        Enum.map(blocks, &Map.put_new(&1, "label", ""))
      end)
    else
      Map.update(condition, "rules", [], fn rules ->
        Enum.map(rules, &Map.put_new(&1, "label", ""))
      end)
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp flow_nodes(%{nodes: nodes} = flow) do
    if Ecto.assoc_loaded?(nodes), do: nodes, else: NodeCrud.list_nodes(flow.id)
  end

  defp occurrence_number(nodes, current_node_id) do
    nodes = Enum.sort_by(nodes, & &1.inserted_at)

    case Enum.find_index(nodes, &(&1.id == current_node_id)) do
      nil -> length(nodes) + 1
      index -> index + 1
    end
  end

  defp normalize_for_id(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  defp normalize_outcome_tag(tag) when is_binary(tag) do
    tag
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/, "_")
  end

  defp normalize_outcome_tag(_tag), do: ""

  defp normalize_hex_color(color, default) when is_binary(color) do
    if Regex.match?(@hex_color_regex, color), do: color, else: default
  end

  defp normalize_hex_color(_color, default), do: default

  defp normalize_exit_mode(mode) when mode in ~w(terminal flow_reference caller_return), do: mode
  defp normalize_exit_mode(_mode), do: "terminal"

  defp parse_positive_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp parse_positive_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _invalid -> {:error, :invalid_flow_reference}
    end
  end

  defp parse_positive_id(_id), do: {:error, :invalid_flow_reference}

  defp reject_self_reference(id, id), do: {:error, :self_reference}
  defp reject_self_reference(_current_flow_id, _flow_id), do: :ok

  defp reject_circular_reference(current_flow_id, flow_id) do
    if NodeCreate.has_circular_reference?(current_flow_id, flow_id),
      do: {:error, :circular_reference},
      else: :ok
  end

  defp require_flow(project_id, flow_id) do
    if FlowCrud.get_flow_brief(project_id, flow_id), do: :ok, else: {:error, :flow_not_found}
  end
end
