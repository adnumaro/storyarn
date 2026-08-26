defmodule Storyarn.Flows.NodeTypesTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows

  @editor_types ~w(annotation condition dialogue entry exit hub instruction jump subflow)

  test "the editor catalog and direct-creation catalog are Flow-owned" do
    assert Flows.editor_node_types() == @editor_types
    assert Flows.user_addable_node_types() == @editor_types -- ~w(annotation entry)
  end

  test "every editor type owns defaults and an editor form projection" do
    for type <- @editor_types do
      defaults = Flows.default_node_data(type)

      assert is_map(defaults)
      assert is_map(Flows.node_form_data(type, defaults))
    end
  end

  test "dialogue defaults and duplication create independent runtime identities" do
    original = Flows.default_node_data("dialogue")
    duplicate = Flows.duplicate_node_data("dialogue", Map.put(original, "technical_id", "intro"))

    assert original["localization_id"] =~ "dialogue_"
    assert duplicate["localization_id"] =~ "dialogue_"
    assert duplicate["localization_id"] != original["localization_id"]
    assert duplicate["technical_id"] == ""
  end

  test "exit form data normalizes the persisted editor contract" do
    form =
      Flows.node_form_data("exit", %{
        "outcome_tags" => " Main Ending,secret ending,main ending ",
        "outcome_color" => "invalid",
        "exit_mode" => "invalid",
        "referenced_flow_id" => "42",
        "target_type" => "scene",
        "target_id" => "7"
      })

    assert form["outcome_tags"] == ["main_ending", "secret_ending"]
    assert form["outcome_color"] == "#22c55e"
    assert form["exit_mode"] == "terminal"
    assert form["referenced_flow_id"] == 42
    assert form["target_type"] == "scene"
    assert form["target_id"] == 7
  end

  test "unknown editor types are inert" do
    data = %{"custom" => true}

    assert Flows.default_node_data("unknown") == %{}
    assert Flows.node_form_data("unknown", data) == %{}
    assert Flows.duplicate_node_data("unknown", data) == data
  end
end
