defmodule Storyarn.Exports.ArtifactValidator do
  @moduledoc """
  Validates whether selected project data can be represented safely in the
  target export format.

  This deliberately does not duplicate authoring-health rules. It checks the
  runtime identifiers, live references, and generated expressions that form
  the exported artifact's contract.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Exports.ExpressionTranspiler
  alias Storyarn.Exports.Serializers.Helpers, as: SerializerHelpers
  alias Storyarn.Flows
  alias Storyarn.Localization.RuntimeKey
  alias Storyarn.References
  alias Storyarn.Shared.Validations

  @blocking_stale_reference_formats [:ink, :yarn]

  @spec findings(pos_integer(), ExportOptions.t(), [map()], [map()]) :: [map()]
  def findings(project_id, %ExportOptions{} = options, flows, sheets) do
    runtime_identifier_findings(options, flows, sheets) ++
      dialogue_runtime_id_findings(flows) ++
      stale_variable_reference_findings(project_id, options.format, flows) ++
      expression_findings(options.format, flows)
  end

  defp runtime_identifier_findings(options, flows, sheets) do
    flow_findings =
      Enum.flat_map(flows, fn flow ->
        if valid_identifier?(flow.shortcut, options.format) do
          []
        else
          [
            %{
              level: :error,
              rule: :invalid_flow_identifier,
              format: options.format,
              flow_id: flow.id,
              flow_name: flow.name,
              entity_type: "flow",
              entity_id: flow.id,
              entity_label: flow.name,
              message:
                dgettext(
                  "projects",
                  "Flow \"%{name}\" needs a valid shortcut for the %{format} export",
                  name: flow.name,
                  format: format_label(options.format)
                )
            }
          ]
        end
      end)

    sheet_findings =
      Enum.flat_map(sheets, fn sheet ->
        if valid_identifier?(sheet.shortcut, options.format) do
          []
        else
          [
            %{
              level: :error,
              rule: :invalid_sheet_identifier,
              format: options.format,
              sheet_id: sheet.id,
              sheet_name: sheet.name,
              entity_type: "sheet",
              entity_id: sheet.id,
              entity_label: sheet.name,
              message:
                dgettext(
                  "projects",
                  "Sheet \"%{name}\" needs a valid shortcut for the %{format} export",
                  name: sheet.name,
                  format: format_label(options.format)
                )
            }
          ]
        end
      end)

    flow_findings ++ sheet_findings
  end

  defp valid_identifier?(value, _format) when not is_binary(value) or value == "", do: false

  defp valid_identifier?(value, format) do
    Regex.match?(Validations.shortcut_format(), value) and
      format_identifier_valid?(SerializerHelpers.shortcut_to_identifier(value), format)
  end

  defp format_identifier_valid?(identifier, format) when format in [:ink, :yarn, :godot] do
    Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, identifier)
  end

  defp format_identifier_valid?(identifier, _format), do: identifier != ""

  defp dialogue_runtime_id_findings(flows) do
    dialogue_nodes =
      for flow <- flows,
          node <- flow.nodes || [],
          node.type == "dialogue",
          do: {flow, node}

    invalid =
      Enum.flat_map(dialogue_nodes, fn {flow, node} ->
        invalid_dialogue_id_findings(flow, node) ++ invalid_response_id_findings(flow, node)
      end)

    invalid ++ duplicate_dialogue_id_findings(dialogue_nodes)
  end

  defp invalid_dialogue_id_findings(flow, node) do
    if RuntimeKey.valid_dialogue_id?(node.data["localization_id"]) do
      []
    else
      [
        node_finding(
          :error,
          :invalid_dialogue_runtime_id,
          flow,
          node,
          dgettext(
            "projects",
            ~s(Dialogue "%{node}" in flow "%{flow}" needs a valid localization ID),
            node: Flows.node_label(node),
            flow: flow.name
          )
        )
      ]
    end
  end

  defp invalid_response_id_findings(flow, node) do
    responses = Map.get(node.data, "responses", [])

    if is_list(responses) do
      response_ids =
        Enum.map(responses, fn
          response when is_map(response) -> response["id"]
          _response -> nil
        end)

      invalid_count = Enum.count(response_ids, &(not RuntimeKey.valid_response_id?(&1)))

      duplicate_count =
        response_ids
        |> Enum.filter(&RuntimeKey.valid_response_id?/1)
        |> Enum.frequencies()
        |> Enum.count(fn {_id, count} -> count > 1 end)

      []
      |> maybe_add_response_finding(flow, node, :invalid_response_runtime_id, invalid_count)
      |> maybe_add_response_finding(flow, node, :duplicate_response_runtime_id, duplicate_count)
    else
      [
        node_finding(
          :error,
          :invalid_response_runtime_id,
          flow,
          node,
          dgettext(
            "projects",
            ~s(Dialogue "%{node}" in flow "%{flow}" has invalid response data),
            node: Flows.node_label(node),
            flow: flow.name
          )
        )
      ]
    end
  end

  defp maybe_add_response_finding(findings, _flow, _node, _rule, 0), do: findings

  defp maybe_add_response_finding(findings, flow, node, rule, count) do
    message =
      case rule do
        :invalid_response_runtime_id ->
          dngettext(
            "projects",
            ~s(Dialogue "%{node}" in flow "%{flow}" has one response without a valid ID),
            ~s(Dialogue "%{node}" in flow "%{flow}" has %{count} responses without valid IDs),
            count,
            node: Flows.node_label(node),
            flow: flow.name,
            count: count
          )

        :duplicate_response_runtime_id ->
          dngettext(
            "projects",
            ~s(Dialogue "%{node}" in flow "%{flow}" repeats one response ID),
            ~s(Dialogue "%{node}" in flow "%{flow}" repeats %{count} response IDs),
            count,
            node: Flows.node_label(node),
            flow: flow.name,
            count: count
          )
      end

    [node_finding(:error, rule, flow, node, message, count: count) | findings]
  end

  defp duplicate_dialogue_id_findings(dialogue_nodes) do
    dialogue_nodes
    |> Enum.group_by(fn {_flow, node} -> node.data["localization_id"] end)
    |> Enum.flat_map(fn
      {_id, [_single]} ->
        []

      {id, duplicates} ->
        if RuntimeKey.valid_dialogue_id?(id) do
          [{flow, node} | _rest] = duplicates

          [
            node_finding(
              :error,
              :duplicate_dialogue_runtime_id,
              flow,
              node,
              dngettext(
                "projects",
                "Localization ID \"%{id}\" is used by one dialogue more than once",
                "Localization ID \"%{id}\" is used by %{count} dialogues",
                length(duplicates),
                id: id,
                count: length(duplicates)
              ),
              count: length(duplicates)
            )
          ]
        else
          []
        end
    end)
  end

  defp stale_variable_reference_findings(_project_id, _format, []), do: []

  defp stale_variable_reference_findings(_project_id, format, flows) do
    stale_by_flow =
      flows
      |> Enum.map(& &1.id)
      |> References.list_stale_node_ids_by_flow()

    level = if format in @blocking_stale_reference_formats, do: :error, else: :warning

    Enum.flat_map(flows, fn flow ->
      stale_ids = Map.get(stale_by_flow, flow.id, MapSet.new())

      flow.nodes
      |> Enum.filter(&MapSet.member?(stale_ids, &1.id))
      |> Enum.map(fn node ->
        node_finding(
          level,
          :stale_variable_reference,
          flow,
          node,
          dgettext(
            "projects",
            ~s("%{node}" in flow "%{flow}" references a variable that no longer exists; %{format} cannot preserve it safely),
            node: Flows.node_label(node),
            flow: flow.name,
            format: format_label(format)
          ),
          format: format
        )
      end)
    end)
  end

  defp expression_findings(format, flows) do
    Enum.flat_map(flows, fn flow ->
      Enum.flat_map(flow.nodes || [], &node_expression_findings(format, flow, &1))
    end)
  end

  defp node_expression_findings(format, flow, node) do
    condition_sources =
      case node.type do
        "condition" -> [{:condition, node.data["condition"]}]
        "dialogue" -> [{:condition, node.data["condition"]}] ++ response_conditions(node.data)
        _type -> []
      end

    instruction_sources =
      case node.type do
        "instruction" -> [{:instruction, node.data["assignments"]}]
        "dialogue" -> response_instructions(node.data)
        _type -> []
      end

    Enum.flat_map(condition_sources, fn {source, condition} ->
      transpile_condition_findings(format, flow, node, source, condition)
    end) ++
      Enum.flat_map(instruction_sources, fn {source, assignments} ->
        transpile_instruction_findings(format, flow, node, source, assignments)
      end)
  end

  defp response_conditions(data) do
    data
    |> Map.get("responses", [])
    |> list_or_empty()
    |> Enum.with_index(1)
    |> Enum.map(fn
      {response, index} when is_map(response) -> {{:response_condition, index}, response["condition"]}
      {_response, index} -> {{:response_condition, index}, :invalid}
    end)
  end

  defp response_instructions(data) do
    data
    |> Map.get("responses", [])
    |> list_or_empty()
    |> Enum.with_index(1)
    |> Enum.map(fn
      {response, index} when is_map(response) ->
        assignments = response["instruction_assignments"] || parse_instruction(response["instruction"])
        {{:response_instruction, index}, assignments}

      {_response, index} ->
        {{:response_instruction, index}, :invalid}
    end)
  end

  defp transpile_condition_findings(_format, _flow, _node, _source, condition) when condition in [nil, ""], do: []

  defp transpile_condition_findings(format, flow, node, source, condition) do
    case ExpressionTranspiler.transpile_condition(condition, format) do
      {:ok, expression, warnings} ->
        empty_expression_finding(expression, flow, node, source, format) ++
          transpiler_warning_findings(warnings, flow, node, source, format)

      {:error, reason} ->
        [expression_error_finding(flow, node, source, format, reason)]
    end
  end

  defp transpile_instruction_findings(_format, _flow, _node, _source, assignments) when assignments in [nil, []], do: []

  defp transpile_instruction_findings(format, flow, node, source, assignments) do
    case ExpressionTranspiler.transpile_instruction(assignments, format) do
      {:ok, expression, warnings} ->
        empty_expression_finding(expression, flow, node, source, format) ++
          transpiler_warning_findings(warnings, flow, node, source, format)

      {:error, reason} ->
        [expression_error_finding(flow, node, source, format, reason)]
    end
  end

  defp empty_expression_finding(expression, _flow, _node, _source, _format)
       when is_binary(expression) and expression != "", do: []

  defp empty_expression_finding(_expression, flow, node, source, format) do
    [
      expression_error_finding(
        flow,
        node,
        source,
        format,
        :empty_generated_expression
      )
    ]
  end

  defp expression_error_finding(flow, node, source, format, reason) do
    node_finding(
      :error,
      :invalid_export_expression,
      flow,
      node,
      dgettext(
        "projects",
        ~s("%{node}" in flow "%{flow}" contains an expression that cannot be exported to %{format}),
        node: Flows.node_label(node),
        flow: flow.name,
        format: format_label(format)
      ),
      expression_source: source,
      reason: reason,
      format: format
    )
  end

  defp transpiler_warning_findings(warnings, flow, node, source, format) do
    Enum.map(warnings, fn warning ->
      node_finding(
        :warning,
        warning.type,
        flow,
        node,
        dgettext(
          "projects",
          ~s("%{node}" in flow "%{flow}": %{warning}),
          node: Flows.node_label(node),
          flow: flow.name,
          warning: warning.message
        ),
        expression_source: source,
        format: format,
        details: Map.get(warning, :details, %{})
      )
    end)
  end

  defp node_finding(level, rule, flow, node, message, extra \\ []) do
    Map.merge(
      %{
        level: level,
        rule: rule,
        message: message,
        flow_id: flow.id,
        flow_name: flow.name,
        node_id: node.id,
        node_type: node.type,
        entity_type: node.type,
        entity_id: node.id,
        entity_label: Flows.node_label(node)
      },
      Map.new(extra)
    )
  end

  defp parse_instruction(nil), do: []
  defp parse_instruction(""), do: []

  defp parse_instruction(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, assignments} when is_list(assignments) -> assignments
      _result -> :invalid
    end
  end

  defp parse_instruction(value), do: value

  defp list_or_empty(value) when is_list(value), do: value
  defp list_or_empty(_value), do: []

  defp format_label(format) do
    format
    |> to_string()
    |> String.capitalize()
  end
end
