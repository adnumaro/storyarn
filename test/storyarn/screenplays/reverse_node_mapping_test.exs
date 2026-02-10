defmodule Storyarn.Screenplays.ReverseNodeMappingTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Screenplays.ReverseNodeMapping

  defp build_node(attrs) do
    struct!(
      %FlowNode{id: 1, type: "dialogue", data: %{}, position_x: 0.0, position_y: 0.0, source: "manual"},
      attrs
    )
  end

  describe "node_to_element_attrs/1 — entry" do
    test "produces scene_heading with default content" do
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 10, type: "entry", data: %{}))

      assert [%{type: "scene_heading", content: "INT. - DAY", source_node_id: 10}] = result
    end
  end

  describe "node_to_element_attrs/1 — scene" do
    test "reconstructs INT. heading with description and time" do
      data = %{"int_ext" => "int", "description" => "OFFICE", "time_of_day" => "DAY"}
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 20, type: "scene", data: data))

      assert [%{type: "scene_heading", content: "INT. OFFICE - DAY", source_node_id: 20}] = result
    end

    test "reconstructs EXT. heading" do
      data = %{"int_ext" => "ext", "description" => "PARK", "time_of_day" => "NIGHT"}
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 21, type: "scene", data: data))

      assert [%{type: "scene_heading", content: "EXT. PARK - NIGHT", source_node_id: 21}] = result
    end

    test "omits time suffix when time_of_day is empty" do
      data = %{"int_ext" => "int", "description" => "OFFICE", "time_of_day" => ""}
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 22, type: "scene", data: data))

      assert [%{type: "scene_heading", content: "INT. OFFICE", source_node_id: 22}] = result
    end

    test "omits time suffix when time_of_day is nil" do
      data = %{"int_ext" => "int", "description" => "OFFICE"}
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 23, type: "scene", data: data))

      assert [%{type: "scene_heading", content: "INT. OFFICE", source_node_id: 23}] = result
    end
  end

  describe "node_to_element_attrs/1 — dialogue (action-style)" do
    test "empty text with stage_directions produces single action" do
      data = %{"text" => "", "stage_directions" => "A desk sits in the corner.", "menu_text" => "", "responses" => []}
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 30, type: "dialogue", data: data))

      assert [%{type: "action", content: "A desk sits in the corner.", source_node_id: 30}] = result
    end
  end

  describe "node_to_element_attrs/1 — dialogue (standard)" do
    test "produces character + dialogue (2 elements)" do
      data = %{"text" => "Hello.", "stage_directions" => "", "menu_text" => "JOHN", "responses" => []}
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 40, type: "dialogue", data: data))

      assert [
               %{type: "character", content: "JOHN", source_node_id: 40},
               %{type: "dialogue", content: "Hello.", source_node_id: 40}
             ] = result
    end

    test "uses CHARACTER as default when menu_text is empty" do
      data = %{"text" => "Hello.", "stage_directions" => "", "menu_text" => "", "responses" => []}
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 41, type: "dialogue", data: data))

      assert [%{type: "character", content: "CHARACTER"}, %{type: "dialogue", content: "Hello."}] = result
    end

    test "with stage_directions produces character + parenthetical + dialogue (3 elements)" do
      data = %{"text" => "Hello.", "stage_directions" => "whispering", "menu_text" => "JOHN", "responses" => []}
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 42, type: "dialogue", data: data))

      assert [
               %{type: "character", content: "JOHN"},
               %{type: "parenthetical", content: "whispering"},
               %{type: "dialogue", content: "Hello."}
             ] = result
    end
  end

  describe "node_to_element_attrs/1 — dialogue (with responses)" do
    test "produces character + dialogue + response" do
      data = %{
        "text" => "What do you want?",
        "stage_directions" => "",
        "menu_text" => "NPC",
        "responses" => [
          %{"id" => "c1", "text" => "Help", "condition" => nil, "instruction" => nil},
          %{"id" => "c2", "text" => "Nothing", "condition" => nil, "instruction" => nil}
        ]
      }

      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 50, type: "dialogue", data: data))

      assert [
               %{type: "character", content: "NPC"},
               %{type: "dialogue", content: "What do you want?"},
               %{type: "response", data: %{"choices" => choices}}
             ] = result

      assert length(choices) == 2
      assert Enum.at(choices, 0)["text"] == "Help"
      assert Enum.at(choices, 1)["text"] == "Nothing"
    end

    test "deserializes string condition via Condition.parse" do
      condition_json = Jason.encode!(%{"logic" => "all", "rules" => [%{"sheet" => "mc", "variable" => "hp", "operator" => "greater_than", "value" => "50"}]})

      data = %{
        "text" => "Hi",
        "stage_directions" => "",
        "menu_text" => "NPC",
        "responses" => [
          %{"id" => "c1", "text" => "Option", "condition" => condition_json, "instruction" => nil}
        ]
      }

      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 51, type: "dialogue", data: data))
      [_, _, %{data: %{"choices" => [choice]}}] = result

      assert choice["condition"]["logic"] == "all"
      assert length(choice["condition"]["rules"]) == 1
    end

    test "deserializes string instruction via Jason.decode" do
      instruction_json = Jason.encode!([%{"sheet" => "mc", "variable" => "hp", "operator" => "set", "value" => "100"}])

      data = %{
        "text" => "Hi",
        "stage_directions" => "",
        "menu_text" => "NPC",
        "responses" => [
          %{"id" => "c1", "text" => "Option", "condition" => nil, "instruction" => instruction_json}
        ]
      }

      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 52, type: "dialogue", data: data))
      [_, _, %{data: %{"choices" => [choice]}}] = result

      assert is_list(choice["instruction"])
      assert hd(choice["instruction"])["operator"] == "set"
    end

    test "passes through map condition and list instruction unchanged" do
      condition = %{"logic" => "any", "rules" => []}
      instruction = [%{"sheet" => "x", "variable" => "y", "operator" => "add", "value" => "1"}]

      data = %{
        "text" => "Hi",
        "stage_directions" => "",
        "menu_text" => "NPC",
        "responses" => [
          %{"id" => "c1", "text" => "Option", "condition" => condition, "instruction" => instruction}
        ]
      }

      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 53, type: "dialogue", data: data))
      [_, _, %{data: %{"choices" => [choice]}}] = result

      assert choice["condition"] == condition
      assert choice["instruction"] == instruction
    end
  end

  describe "node_to_element_attrs/1 — condition" do
    test "produces conditional with condition data" do
      condition = %{"logic" => "all", "rules" => [%{"sheet" => "mc", "variable" => "hp", "operator" => "greater_than", "value" => "50"}]}
      data = %{"condition" => condition, "switch_mode" => false}
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 60, type: "condition", data: data))

      assert [%{type: "conditional", data: %{"condition" => ^condition}, source_node_id: 60}] = result
    end

    test "defaults to empty condition when data is missing" do
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 61, type: "condition", data: %{}))

      assert [%{type: "conditional", data: %{"condition" => %{"logic" => "all", "rules" => []}}}] = result
    end
  end

  describe "node_to_element_attrs/1 — instruction" do
    test "produces instruction with assignments" do
      assignments = [%{"sheet" => "mc", "variable" => "hp", "operator" => "set", "value" => "100"}]
      data = %{"assignments" => assignments, "description" => "Heal"}
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 70, type: "instruction", data: data))

      assert [%{type: "instruction", data: %{"assignments" => ^assignments}, source_node_id: 70}] = result
    end
  end

  describe "node_to_element_attrs/1 — exit" do
    test "produces transition with label" do
      data = %{"label" => "FADE OUT", "exit_mode" => "terminal"}
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 80, type: "exit", data: data))

      assert [%{type: "transition", content: "FADE OUT", source_node_id: 80}] = result
    end

    test "defaults to empty label" do
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 81, type: "exit", data: %{}))

      assert [%{type: "transition", content: "", source_node_id: 81}] = result
    end
  end

  describe "node_to_element_attrs/1 — hub" do
    test "produces hub_marker preserving data" do
      data = %{"hub_id" => "hub-abc", "label" => "Main Hub", "color" => "#ff0000"}
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 90, type: "hub", data: data))

      assert [
               %{
                 type: "hub_marker",
                 content: "Main Hub",
                 data: %{"hub_node_id" => "hub-abc", "color" => "#ff0000"},
                 source_node_id: 90
               }
             ] = result
    end
  end

  describe "node_to_element_attrs/1 — jump" do
    test "produces jump_marker preserving target_hub_id" do
      data = %{"target_hub_id" => "hub-xyz"}
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 100, type: "jump", data: data))

      assert [%{type: "jump_marker", data: %{"target_hub_id" => "hub-xyz"}, source_node_id: 100}] = result
    end
  end

  describe "node_to_element_attrs/1 — subflow" do
    test "returns empty list" do
      result = ReverseNodeMapping.node_to_element_attrs(build_node(id: 110, type: "subflow", data: %{}))

      assert result == []
    end
  end

  describe "nodes_to_element_attrs/1" do
    test "expands multiple nodes into flat element list" do
      nodes = [
        build_node(id: 1, type: "entry", data: %{}),
        build_node(id: 2, type: "dialogue", data: %{"text" => "Hello.", "stage_directions" => "", "menu_text" => "JOHN", "responses" => []}),
        build_node(id: 3, type: "exit", data: %{"label" => "END"})
      ]

      result = ReverseNodeMapping.nodes_to_element_attrs(nodes)

      types = Enum.map(result, & &1.type)
      assert types == ["scene_heading", "character", "dialogue", "transition"]
    end

    test "skips subflow nodes in the list" do
      nodes = [
        build_node(id: 1, type: "entry", data: %{}),
        build_node(id: 2, type: "subflow", data: %{}),
        build_node(id: 3, type: "exit", data: %{"label" => ""})
      ]

      result = ReverseNodeMapping.nodes_to_element_attrs(nodes)
      types = Enum.map(result, & &1.type)

      assert types == ["scene_heading", "transition"]
    end
  end
end
