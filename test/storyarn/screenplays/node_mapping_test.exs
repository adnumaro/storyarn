defmodule Storyarn.Screenplays.NodeMappingTest do
  use ExUnit.Case, async: true

  alias Storyarn.Screenplays.NodeMapping

  # Helper to build element structs for testing
  defp el(attrs) do
    defaults = %{id: 1, type: "action", content: "", data: %{}, position: 0, depth: 0, branch: nil}
    struct(Storyarn.Screenplays.ScreenplayElement, Map.merge(defaults, attrs))
  end

  describe "group_to_node_attrs/2 dialogue group" do
    test "maps character + dialogue to dialogue node" do
      group = %{
        type: :dialogue_group,
        elements: [
          el(%{id: 1, type: "character", content: "JAIME"}),
          el(%{id: 2, type: "dialogue", content: "Hello there."})
        ],
        group_id: "g1"
      }

      result = NodeMapping.group_to_node_attrs(group)

      assert result.type == "dialogue"
      assert result.source == "screenplay_sync"
      assert result.element_ids == [1, 2]
      assert result.data["text"] == "Hello there."
      assert result.data["menu_text"] == "JAIME"
      assert result.data["stage_directions"] == ""
      assert result.data["responses"] == []
    end

    test "maps character + parenthetical + dialogue with stage directions" do
      group = %{
        type: :dialogue_group,
        elements: [
          el(%{id: 1, type: "character", content: "MARIA"}),
          el(%{id: 2, type: "parenthetical", content: "whispering"}),
          el(%{id: 3, type: "dialogue", content: "Come here."})
        ],
        group_id: "g2"
      }

      result = NodeMapping.group_to_node_attrs(group)

      assert result.data["text"] == "Come here."
      assert result.data["stage_directions"] == "whispering"
      assert result.data["menu_text"] == "MARIA"
      assert result.element_ids == [1, 2, 3]
    end

    test "maps dialogue group with attached response" do
      group = %{
        type: :dialogue_group,
        elements: [
          el(%{id: 1, type: "character", content: "NPC"}),
          el(%{id: 2, type: "dialogue", content: "What do you want?"}),
          el(%{
            id: 3,
            type: "response",
            data: %{
              "choices" => [
                %{"id" => "c1", "text" => "Help me", "condition" => nil, "instruction" => nil},
                %{"id" => "c2", "text" => "Nothing", "condition" => nil, "instruction" => nil}
              ]
            }
          })
        ],
        group_id: "g3"
      }

      result = NodeMapping.group_to_node_attrs(group)

      assert length(result.data["responses"]) == 2
      assert Enum.at(result.data["responses"], 0)["text"] == "Help me"
      assert Enum.at(result.data["responses"], 1)["text"] == "Nothing"
      assert result.element_ids == [1, 2, 3]
    end
  end

  describe "group_to_node_attrs/2 scene heading" do
    test "maps first scene heading to entry node" do
      group = %{
        type: :scene_heading,
        elements: [el(%{id: 1, type: "scene_heading", content: "INT. TAVERN - NIGHT"})],
        group_id: nil
      }

      result = NodeMapping.group_to_node_attrs(group, 0)

      assert result.type == "entry"
      assert result.data == %{}
      assert result.element_ids == [1]
      assert result.source == "screenplay_sync"
    end

    test "maps subsequent scene heading to scene node with parsed INT/EXT" do
      group = %{
        type: :scene_heading,
        elements: [el(%{id: 2, type: "scene_heading", content: "EXT. FOREST - DAY"})],
        group_id: nil
      }

      result = NodeMapping.group_to_node_attrs(group, 1)

      assert result.type == "scene"
      assert result.data["int_ext"] == "ext"
      assert result.data["description"] == "FOREST"
      assert result.data["time_of_day"] == "DAY"
      assert result.element_ids == [2]
    end

    test "parses INT./EXT. prefix" do
      group = %{
        type: :scene_heading,
        elements: [el(%{id: 3, type: "scene_heading", content: "INT./EXT. CAR - DAWN"})],
        group_id: nil
      }

      result = NodeMapping.group_to_node_attrs(group, 2)

      assert result.data["int_ext"] == "int"
      assert result.data["description"] == "CAR"
      assert result.data["time_of_day"] == "DAWN"
    end
  end

  describe "group_to_node_attrs/2 action" do
    test "maps action to dialogue node with stage_directions" do
      group = %{
        type: :action,
        elements: [el(%{id: 1, type: "action", content: "The door creaks open."})],
        group_id: nil
      }

      result = NodeMapping.group_to_node_attrs(group)

      assert result.type == "dialogue"
      assert result.data["text"] == ""
      assert result.data["stage_directions"] == "The door creaks open."
      assert result.element_ids == [1]
    end
  end

  describe "group_to_node_attrs/2 conditional" do
    test "maps conditional to condition node" do
      condition = %{"logic" => "all", "rules" => [%{"id" => "r1", "sheet" => "mc", "variable" => "health", "operator" => "greater_than", "value" => "50"}]}

      group = %{
        type: :conditional,
        elements: [el(%{id: 1, type: "conditional", data: %{"condition" => condition}})],
        group_id: nil
      }

      result = NodeMapping.group_to_node_attrs(group)

      assert result.type == "condition"
      assert result.data["condition"] == condition
      assert result.data["switch_mode"] == false
      assert result.element_ids == [1]
    end
  end

  describe "group_to_node_attrs/2 instruction" do
    test "maps instruction to instruction node" do
      assignments = [%{"id" => "a1", "sheet" => "mc", "variable" => "gold", "operator" => "add", "value" => "10"}]

      group = %{
        type: :instruction,
        elements: [el(%{id: 1, type: "instruction", data: %{"assignments" => assignments}})],
        group_id: nil
      }

      result = NodeMapping.group_to_node_attrs(group)

      assert result.type == "instruction"
      assert result.data["assignments"] == assignments
      assert result.data["description"] == ""
      assert result.element_ids == [1]
    end
  end

  describe "group_to_node_attrs/2 transition" do
    test "maps transition to exit node" do
      group = %{
        type: :transition,
        elements: [el(%{id: 1, type: "transition", content: "FADE OUT."})],
        group_id: nil
      }

      result = NodeMapping.group_to_node_attrs(group)

      assert result.type == "exit"
      assert result.data["label"] == "FADE OUT."
      assert result.data["exit_mode"] == "terminal"
      assert result.element_ids == [1]
    end
  end

  describe "group_to_node_attrs/2 non-mappeable" do
    test "returns nil for non-mappeable groups" do
      group = %{type: :non_mappeable, elements: [el(%{id: 1, type: "note", content: "A note"})], group_id: nil}
      assert NodeMapping.group_to_node_attrs(group) == nil
    end

    test "returns nil for dual_dialogue" do
      group = %{type: :dual_dialogue, elements: [el(%{id: 1, type: "dual_dialogue"})], group_id: nil}
      assert NodeMapping.group_to_node_attrs(group) == nil
    end
  end

  describe "groups_to_node_attrs/1" do
    test "converts full group list, skipping non-mappeable" do
      groups = [
        %{type: :scene_heading, elements: [el(%{id: 1, type: "scene_heading", content: "INT. OFFICE - DAY"})], group_id: nil},
        %{type: :action, elements: [el(%{id: 2, type: "action", content: "A desk."})], group_id: nil},
        %{type: :non_mappeable, elements: [el(%{id: 3, type: "note", content: "Remember to revise"})], group_id: nil},
        %{type: :dialogue_group, elements: [el(%{id: 4, type: "character", content: "BOB"}), el(%{id: 5, type: "dialogue", content: "Hi."})], group_id: "g1"},
        %{type: :transition, elements: [el(%{id: 6, type: "transition", content: "CUT TO:"})], group_id: nil}
      ]

      result = NodeMapping.groups_to_node_attrs(groups)

      assert length(result) == 4
      assert Enum.at(result, 0).type == "entry"
      assert Enum.at(result, 1).type == "dialogue"
      assert Enum.at(result, 2).type == "dialogue"
      assert Enum.at(result, 3).type == "exit"
    end
  end
end
