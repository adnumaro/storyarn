defmodule Storyarn.Flows.HealthChecker do
  @moduledoc """
  Produces structured authoring findings for a serialized flow graph.

  The checker distinguishes invalid configuration (`:error`), incomplete or
  risky authoring (`:warning`), and valid but noteworthy no-op/default
  behavior (`:info`). It operates on `Flows.serialize_for_canvas/2` output so
  resolved references and graph-derived flags share one contract.
  """

  alias Storyarn.Flows.Condition
  alias Storyarn.Flows.Instruction
  alias Storyarn.Shared.HtmlUtils

  @type severity :: :error | :warning | :info
  @type finding :: %{
          required(:severity) => severity(),
          required(:code) => atom(),
          required(:node_id) => integer() | nil,
          required(:node_type) => String.t() | nil,
          optional(:details) => map()
        }

  @spec check(map()) :: [finding()]
  def check(%{nodes: nodes} = flow_data) when is_list(nodes) do
    context = %{
      hub_ids:
        nodes
        |> Enum.filter(&(&1.type == "hub"))
        |> MapSet.new(& &1.data["hub_id"])
    }

    entry_findings(nodes) ++ Enum.flat_map(nodes, &node_findings(&1, context, flow_data))
  end

  def check(_flow_data), do: []

  defp entry_findings(nodes) do
    case Enum.count(nodes, &(&1.type == "entry")) do
      0 -> [finding(:error, :missing_entry, nil, nil)]
      1 -> []
      count -> [finding(:error, :multiple_entries, nil, nil, %{count: count})]
    end
  end

  defp node_findings(%{type: type} = node, context, _flow_data) do
    error_findings(node, context) ++
      warning_findings(node) ++
      info_findings(node, type)
  end

  defp error_findings(%{data: data, type: type} = node, context) do
    []
    |> maybe_add(data["has_stale_refs"] == true, node, :error, :stale_variable_reference)
    |> add_reference_errors(node, type, context)
    |> add_connection_pin_errors(node, data)
  end

  defp add_reference_errors(findings, %{data: data} = node, "subflow", _context) do
    findings
    |> maybe_add(
      blank?(data["referenced_flow_id"]),
      node,
      :error,
      :missing_subflow_reference
    )
    |> maybe_add(
      data["stale_reference"] == true,
      node,
      :error,
      :stale_subflow_reference
    )
  end

  defp add_reference_errors(findings, %{data: data} = node, "jump", context) do
    findings
    |> maybe_add(
      blank?(data["target_hub_id"]),
      node,
      :error,
      :missing_jump_target
    )
    |> maybe_add(
      !blank?(data["target_hub_id"]) and
        !MapSet.member?(context.hub_ids, data["target_hub_id"]),
      node,
      :error,
      :stale_jump_target
    )
  end

  defp add_reference_errors(findings, %{data: %{"exit_mode" => "flow_reference"} = data} = node, "exit", _context) do
    findings
    |> maybe_add(
      blank?(data["referenced_flow_id"]),
      node,
      :error,
      :missing_exit_flow_reference
    )
    |> maybe_add(
      data["stale_reference"] == true,
      node,
      :error,
      :stale_exit_flow_reference
    )
  end

  defp add_reference_errors(findings, _node, _type, _context), do: findings

  defp add_connection_pin_errors(findings, node, data) do
    findings
    |> maybe_add_with_details(
      non_empty_list?(data["invalid_output_pins"]),
      node,
      :error,
      :invalid_output_pins,
      %{pins: data["invalid_output_pins"] || []}
    )
    |> maybe_add_with_details(
      non_empty_list?(data["invalid_input_pins"]),
      node,
      :error,
      :invalid_input_pins,
      %{pins: data["invalid_input_pins"] || []}
    )
  end

  defp warning_findings(%{data: data, type: type} = node) do
    []
    |> maybe_add(data["has_type_warnings"] == true, node, :warning, :variable_type_mismatch)
    |> maybe_add(
      type == "dialogue" and response_type_warning?(data["responses"]),
      node,
      :warning,
      :response_type_mismatch
    )
    |> maybe_add(
      type == "dialogue" and dialogue_text_empty?(data),
      node,
      :warning,
      :missing_dialogue_text
    )
    |> maybe_add(
      type == "dialogue" and blank?(data["speaker_sheet_id"]),
      node,
      :warning,
      :missing_dialogue_speaker
    )
    |> maybe_add(
      type == "dialogue" and empty_response_text?(data["responses"]),
      node,
      :warning,
      :empty_dialogue_response
    )
    |> maybe_add(
      type == "dialogue" and incomplete_response_condition?(data["responses"]),
      node,
      :warning,
      :incomplete_response_condition
    )
    |> maybe_add(
      type == "dialogue" and incomplete_response_assignment?(data["responses"]),
      node,
      :warning,
      :incomplete_response_assignment
    )
    |> maybe_add(
      type == "condition" and condition_incomplete?(data["condition"]),
      node,
      :warning,
      :incomplete_condition
    )
    |> maybe_add(
      type == "instruction" and assignments_incomplete?(data["assignments"]),
      node,
      :warning,
      :incomplete_instruction_assignment
    )
    |> maybe_add(data["unreachable"] == true, node, :warning, :unreachable_node)
    |> add_output_findings(node)
  end

  defp info_findings(%{data: data} = node, type) do
    []
    |> maybe_add(
      type == "instruction" and empty_list?(data["assignments"]),
      node,
      :info,
      :empty_instruction
    )
    |> maybe_add(
      type == "condition" and condition_empty?(data["condition"]),
      node,
      :info,
      :empty_condition
    )
  end

  defp add_output_findings(findings, %{data: %{"dead_end" => true}} = node) do
    [finding(:warning, :no_outgoing_connection, node.id, node.type) | findings]
  end

  defp add_output_findings(findings, %{data: data} = node) do
    if non_empty_list?(data["missing_output_pins"]) do
      [
        finding(
          :warning,
          :missing_output_connections,
          node.id,
          node.type,
          %{pins: data["missing_output_pins"]}
        )
        | findings
      ]
    else
      findings
    end
  end

  defp maybe_add(findings, true, node, severity, code) do
    [finding(severity, code, node.id, node.type) | findings]
  end

  defp maybe_add(findings, false, _node, _severity, _code), do: findings

  defp maybe_add_with_details(findings, true, node, severity, code, details) do
    [finding(severity, code, node.id, node.type, details) | findings]
  end

  defp maybe_add_with_details(findings, false, _node, _severity, _code, _details), do: findings

  defp finding(severity, code, node_id, node_type, details \\ %{}) do
    %{
      severity: severity,
      code: code,
      node_id: node_id,
      node_type: node_type,
      details: details
    }
  end

  defp response_type_warning?(responses) when is_list(responses) do
    Enum.any?(responses, &(&1["has_type_warnings"] == true))
  end

  defp response_type_warning?(_responses), do: false

  defp dialogue_text_empty?(data) do
    data |> Map.get("text") |> HtmlUtils.strip_html() |> String.trim() == ""
  end

  defp empty_response_text?(responses) when is_list(responses) do
    Enum.any?(responses, fn response ->
      response |> Map.get("text") |> HtmlUtils.strip_html() |> String.trim() == ""
    end)
  end

  defp empty_response_text?(_responses), do: false

  defp incomplete_response_condition?(responses) when is_list(responses) do
    Enum.any?(responses, fn response ->
      condition = response["condition"]
      !blank?(condition) and condition_incomplete?(condition)
    end)
  end

  defp incomplete_response_condition?(_responses), do: false

  defp incomplete_response_assignment?(responses) when is_list(responses) do
    Enum.any?(responses, &assignments_incomplete?(&1["instruction_assignments"]))
  end

  defp incomplete_response_assignment?(_responses), do: false

  defp condition_empty?(nil), do: true

  defp condition_empty?(%{"blocks" => blocks}) when is_list(blocks), do: blocks == []
  defp condition_empty?(%{"rules" => rules}) when is_list(rules), do: rules == []
  defp condition_empty?(_condition), do: true

  defp condition_incomplete?(%{"blocks" => blocks}) when is_list(blocks) and blocks != [] do
    Enum.any?(blocks, &condition_block_incomplete?/1)
  end

  defp condition_incomplete?(%{"rules" => rules}) when is_list(rules) and rules != [] do
    Enum.any?(rules, &(not condition_rule_complete?(&1)))
  end

  defp condition_incomplete?(_condition), do: false

  defp condition_block_incomplete?(%{"type" => "block", "rules" => rules}) when is_list(rules) do
    rules == [] or Enum.any?(rules, &(not condition_rule_complete?(&1)))
  end

  defp condition_block_incomplete?(%{"type" => "group", "blocks" => blocks}) when is_list(blocks) do
    blocks == [] or Enum.any?(blocks, &condition_block_incomplete?/1)
  end

  defp condition_block_incomplete?(_block), do: true

  defp condition_rule_complete?(rule) when is_map(rule) do
    operator = rule["operator"]

    present?(rule["sheet"]) and
      present?(rule["variable"]) and
      present?(operator) and
      (!Condition.operator_requires_value?(operator) or present?(rule["value"]))
  end

  defp condition_rule_complete?(_rule), do: false

  defp assignments_incomplete?(assignments) when is_list(assignments) and assignments != [] do
    Enum.any?(assignments, &(not Instruction.complete_assignment?(&1)))
  end

  defp assignments_incomplete?(_assignments), do: false

  defp empty_list?(value), do: !is_list(value) or value == []
  defp non_empty_list?(value), do: is_list(value) and value != []

  defp blank?(value), do: value in [nil, ""]
  defp present?(value), do: not blank?(value)
end
