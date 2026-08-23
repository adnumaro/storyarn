defmodule Storyarn.Projects.FlowHealthChecker do
  @moduledoc """
  Produces structured authoring findings for a serialized flow graph.

  The checker distinguishes invalid configuration (`:error`), incomplete or
  risky authoring (`:warning`), and valid but noteworthy no-op/default
  behavior (`:info`). It operates on serialized Flow graph output so
  resolved references and graph-derived flags share one contract.

  Same result shape as the other tool-owned health checkers:
  severity is declared once in `@severity_by_code` rather than at each detection
  site, and `finding/2` is the only constructor, so a bulk adapter (the dashboard)
  cannot invent its own vocabulary. `entity_type` is `"flow"` for flow-level
  findings and the node's type for node-level ones, exactly as Scenes uses
  `"scene"` for its container and the element kind for everything else.
  """

  alias Storyarn.Projects.FlowCondition
  alias Storyarn.Projects.FlowInstruction
  alias Storyarn.Shared.HtmlUtils
  alias Storyarn.Shared.StringUtils

  @type severity :: :error | :warning | :info
  @type finding :: %{
          required(:severity) => severity(),
          required(:code) => atom(),
          required(:flow_id) => integer() | nil,
          required(:entity_type) => String.t(),
          required(:entity_id) => integer() | nil,
          required(:details) => map()
        }

  # ONE catalog for flow health, exactly like sheets and scenes. Detection is
  # split by what it needs — editorial checks read a node in isolation and live
  # in this module; structural checks need the whole graph and live in
  # `StructuralAnalysis`, which emits through `finding/2` — but the vocabulary,
  # the severities and the shape are owned here and nowhere else. That is what
  # stops the editor and the dashboard from disagreeing.
  @severity_by_code %{
    # Structural — detected by `StructuralAnalysis` from the graph.
    invalid_input_pins: :error,
    invalid_output_pins: :error,
    missing_entry: :error,
    missing_exit_flow_reference: :error,
    missing_jump_target: :error,
    missing_subflow_reference: :error,
    multiple_entries: :error,
    stale_exit_flow_reference: :error,
    stale_jump_target: :error,
    stale_subflow_reference: :error,
    isolated_node: :warning,
    missing_output_connections: :warning,
    no_outgoing_connection: :warning,
    orphan_hub: :warning,
    unreachable_node: :warning,
    # Editorial — detected here, from one node's own data.
    stale_variable_reference: :error,
    empty_dialogue_response: :warning,
    incomplete_condition: :warning,
    incomplete_instruction_assignment: :warning,
    incomplete_response_assignment: :warning,
    incomplete_response_condition: :warning,
    missing_dialogue_speaker: :warning,
    missing_dialogue_text: :warning,
    response_type_mismatch: :warning,
    variable_type_mismatch: :warning,
    empty_condition: :info,
    empty_instruction: :info
  }

  @doc "Returns the canonical severity for a flow health finding code."
  @spec severity_for(atom()) :: severity()
  def severity_for(code), do: Map.fetch!(@severity_by_code, code)

  @doc "Every code this checker can emit, for adapters that need the catalog."
  @spec codes() :: [atom()]
  def codes, do: Map.keys(@severity_by_code)

  @doc "Builds a canonical finding for adapters that detect health in bulk."
  @spec finding(atom(), map()) :: finding()
  def finding(code, attrs \\ %{}) when is_atom(code) and is_map(attrs) do
    %{
      severity: severity_for(code),
      code: code,
      flow_id: Map.get(attrs, :flow_id),
      entity_type: Map.get(attrs, :entity_type, "flow"),
      entity_id: Map.get(attrs, :entity_id),
      details: Map.get(attrs, :details, %{})
    }
  end

  @doc """
  Editorial findings for a flow snapshot: `%{flow_id: id, nodes: nodes}`.

  Structure and reference integrity are NOT checked here — they need the whole
  graph and live in `StructuralAnalysis`, which emits through `finding/2`, so
  both halves share this module's vocabulary and severities.

  The snapshot carries the flow, exactly as the sheets and scenes checkers take
  theirs, so a project-wide sweep can group by `flow_id` without the caller
  patching every finding afterwards.
  """
  @spec check(map()) :: [finding()]
  def check(%{nodes: nodes} = snapshot) when is_list(nodes) do
    flow_id = Map.get(snapshot, :flow_id)

    Enum.flat_map(nodes, &node_findings(&1, flow_id))
  end

  def check(_flow_data), do: []

  # Detection yields CODES; construction happens once, where the flow is known.
  # That is what keeps `flow_id` out of every detection site.
  defp node_findings(%{type: type} = node, flow_id) do
    codes = error_codes(node) ++ warning_codes(node) ++ info_codes(node, type)

    Enum.map(codes, &node_finding(&1, node, flow_id))
  end

  defp error_codes(%{data: data}) do
    maybe_add([], data["has_stale_refs"] == true, :stale_variable_reference)
  end

  defp warning_codes(%{data: data, type: type}) do
    []
    |> maybe_add(data["has_type_warnings"] == true, :variable_type_mismatch)
    |> maybe_add(
      type == "dialogue" and response_type_warning?(data["responses"]),
      :response_type_mismatch
    )
    |> maybe_add(type == "dialogue" and dialogue_text_empty?(data), :missing_dialogue_text)
    |> maybe_add(type == "dialogue" and StringUtils.blank?(data["speaker_sheet_id"]), :missing_dialogue_speaker)
    |> maybe_add(
      type == "dialogue" and empty_response_text?(data["responses"]),
      :empty_dialogue_response
    )
    |> maybe_add(
      type == "dialogue" and incomplete_response_condition?(data["responses"]),
      :incomplete_response_condition
    )
    |> maybe_add(
      type == "dialogue" and incomplete_response_assignment?(data["responses"]),
      :incomplete_response_assignment
    )
    |> maybe_add(type == "condition" and condition_incomplete?(data["condition"]), :incomplete_condition)
    |> maybe_add(
      type == "instruction" and assignments_incomplete?(data["assignments"]),
      :incomplete_instruction_assignment
    )
  end

  defp info_codes(%{data: data}, type) do
    []
    |> maybe_add(type == "instruction" and empty_list?(data["assignments"]), :empty_instruction)
    |> maybe_add(type == "condition" and condition_empty?(data["condition"]), :empty_condition)
  end

  defp maybe_add(codes, true, code), do: [code | codes]
  defp maybe_add(codes, false, _code), do: codes

  # The node's own type is the `entity_type`, exactly as Scenes uses the element
  # kind — it is what the label helper and the popover render.
  defp node_finding(code, node, flow_id) do
    finding(code, %{flow_id: flow_id, entity_type: node.type, entity_id: node.id})
  end

  defp response_type_warning?(responses) when is_list(responses) do
    Enum.any?(responses, &(&1["has_type_warnings"] == true))
  end

  defp response_type_warning?(_responses), do: false

  # A dialogue that presents responses is a choice menu, and a menu needs no line
  # of its own: whatever leads into it already spoke. Only a node with neither
  # text nor responses is genuinely incomplete.
  defp dialogue_text_empty?(data) do
    responses = Map.get(data, "responses")

    (not is_list(responses) or responses == []) and
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
      !StringUtils.blank?(condition) and condition_incomplete?(condition)
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
      (!FlowCondition.operator_requires_value?(operator) or present?(rule["value"]))
  end

  defp condition_rule_complete?(_rule), do: false

  defp assignments_incomplete?(assignments) when is_list(assignments) and assignments != [] do
    Enum.any?(assignments, &(not FlowInstruction.complete_assignment?(&1)))
  end

  defp assignments_incomplete?(_assignments), do: false

  defp empty_list?(value), do: !is_list(value) or value == []

  defp present?(value), do: not StringUtils.blank?(value)
end
