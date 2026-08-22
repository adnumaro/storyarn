defmodule Storyarn.Flows.NodeEditorTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows

  test "condition switch transitions own labels and missing-condition defaults" do
    legacy = %{
      "switch_mode" => false,
      "condition" => %{"logic" => "all", "rules" => [%{"variable" => "health"}]}
    }

    enabled = Flows.toggle_condition_switch_mode(legacy)
    assert enabled["switch_mode"]
    assert enabled["condition"]["rules"] == [%{"variable" => "health", "label" => ""}]

    disabled = Flows.toggle_condition_switch_mode(enabled)
    refute disabled["switch_mode"]

    from_empty = Flows.toggle_condition_switch_mode(%{})
    assert from_empty["condition"] == %{"logic" => "all", "blocks" => []}
  end

  test "dialogue response transitions own identity, shape and field clearing" do
    data = Flows.append_dialogue_response(%{"responses" => []}, "Response 1")
    [response] = data["responses"]

    assert response["id"] =~ "response_"
    assert response["text"] == "Response 1"
    assert response["condition"] == nil
    assert response["instruction_assignments"] == []

    data = Flows.put_dialogue_response_condition(data, response["id"], "condition")
    data = Flows.put_dialogue_response_instruction(data, response["id"], "instruction")
    data = Flows.put_dialogue_response_condition(data, response["id"], "")
    data = Flows.put_dialogue_response_instruction(data, response["id"], "")
    [updated] = data["responses"]

    assert updated["condition"] == nil
    assert updated["instruction"] == nil
    assert Flows.remove_dialogue_response(data, response["id"])["responses"] == []
  end

  test "exit mode, target, tag and color transitions are Flow-owned" do
    data = %{
      "exit_mode" => "terminal",
      "referenced_flow_id" => 8,
      "target_type" => "scene",
      "target_id" => 9,
      "outcome_tags" => []
    }

    data = Flows.put_exit_mode(data, "flow_reference")
    assert data["referenced_flow_id"] == 8
    assert data["target_type"] == nil
    assert data["target_id"] == nil

    data = Flows.add_exit_outcome_tag(data, " Main Ending ")
    data = Flows.add_exit_outcome_tag(data, "main ending")
    assert data["outcome_tags"] == ["main_ending"]

    data = Flows.put_exit_color(data, "invalid")
    assert data["outcome_color"] == "#22c55e"

    data = Flows.put_exit_target(data, "scene", "12")
    assert data["target_type"] == "scene"
    assert data["target_id"] == 12

    data = Flows.put_exit_target(data, "invalid", "12")
    assert data["target_type"] == nil
    assert data["target_id"] == nil
  end

  test "reference validation rejects malformed and self-referential subflows without Web rules" do
    assert Flows.validate_subflow_reference("bad", 10) == {:error, :invalid_flow_reference}
    assert Flows.validate_subflow_reference("10", 10) == {:error, :self_reference}
    assert Flows.validate_subflow_reference("", 10) == {:ok, nil}
  end

  test "annotation transitions enforce the Flow font-size vocabulary" do
    data = %{"font_size" => "md", "color" => "#ffffff"}

    assert Flows.put_annotation_font_size(data, "lg")["font_size"] == "lg"
    assert Flows.put_annotation_font_size(data, "huge") == data
    assert Flows.put_annotation_color(data, "#111111")["color"] == "#111111"
  end

  test "technical IDs use Flow-owned occurrence and normalization rules" do
    first = %{id: 1, type: "dialogue", data: %{"speaker_sheet_id" => 7}, inserted_at: ~U[2026-01-01 00:00:00Z]}
    second = %{id: 2, type: "dialogue", data: %{"speaker_sheet_id" => 7}, inserted_at: ~U[2026-01-02 00:00:00Z]}
    exit = %{id: 3, type: "exit", data: %{"label" => "Good Ending"}, inserted_at: ~U[2026-01-03 00:00:00Z]}
    flow = %{id: 4, shortcut: "Act One", nodes: [first, second, exit]}

    assert Flows.dialogue_technical_id(flow, second, "Lady Ada") == "act_one_lady_ada_2"
    assert Flows.exit_technical_id(flow, exit) == "act_one_good_ending_1"
  end
end
