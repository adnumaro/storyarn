defmodule Storyarn.Screenplays.PageTreeBuilderTest do
  use ExUnit.Case, async: true

  alias Storyarn.Screenplays.PageTreeBuilder
  alias Storyarn.Screenplays.ScreenplayElement

  defp make_element(id, type, content, data \\ %{}) do
    %ScreenplayElement{
      id: id,
      type: type,
      content: content,
      data: data,
      position: id - 1,
      depth: 0,
      branch: nil
    }
  end

  describe "build/1" do
    test "single page with no children produces node attrs without branches" do
      page_data = %{
        screenplay_id: 1,
        elements: [
          make_element(1, "scene_heading", "INT. OFFICE - DAY"),
          make_element(2, "action", "A desk.")
        ],
        children: []
      }

      tree = PageTreeBuilder.build(page_data)

      assert tree.screenplay_id == 1
      assert length(tree.node_attrs_list) == 2
      assert Enum.at(tree.node_attrs_list, 0).type == "entry"
      assert Enum.at(tree.node_attrs_list, 1).type == "dialogue"
      assert tree.branches == []
    end

    test "child page maps first scene_heading to scene (not entry)" do
      page_data = %{
        screenplay_id: 2,
        elements: [
          make_element(10, "scene_heading", "INT. CAVE - NIGHT"),
          make_element(11, "action", "Dark.")
        ],
        children: []
      }

      tree = PageTreeBuilder.build(page_data, child_page: true)

      assert Enum.at(tree.node_attrs_list, 0).type == "scene"
      assert Enum.at(tree.node_attrs_list, 1).type == "dialogue"
    end

    test "builds branch for linked response choice" do
      page_data = %{
        screenplay_id: 1,
        elements: [
          make_element(1, "scene_heading", "INT. OFFICE - DAY"),
          make_element(2, "character", "NPC"),
          make_element(3, "dialogue", "Pick one."),
          make_element(4, "response", "", %{
            "choices" => [
              %{"id" => "c1", "text" => "Go left", "linked_screenplay_id" => 2},
              %{"id" => "c2", "text" => "Go right"}
            ]
          })
        ],
        children: [
          %{
            screenplay_id: 2,
            elements: [
              make_element(20, "scene_heading", "INT. LEFT PATH"),
              make_element(21, "action", "You go left.")
            ],
            children: []
          }
        ]
      }

      tree = PageTreeBuilder.build(page_data)

      assert length(tree.branches) == 1

      branch = hd(tree.branches)
      assert branch.choice_id == "c1"
      assert branch.source_node_index == 1
      assert branch.child.screenplay_id == 2
      assert hd(branch.child.node_attrs_list).type == "scene"
    end

    test "empty child page produces no branch" do
      page_data = %{
        screenplay_id: 1,
        elements: [
          make_element(1, "scene_heading", "INT. OFFICE"),
          make_element(2, "character", "NPC"),
          make_element(3, "dialogue", "Pick."),
          make_element(4, "response", "", %{
            "choices" => [%{"id" => "c1", "text" => "Go", "linked_screenplay_id" => 2}]
          })
        ],
        children: [
          %{screenplay_id: 2, elements: [], children: []}
        ]
      }

      tree = PageTreeBuilder.build(page_data)

      assert tree.branches == []
    end
  end

  describe "flatten/1" do
    test "single page produces sequential connections" do
      page_data = %{
        screenplay_id: 1,
        elements: [
          make_element(1, "scene_heading", "INT. OFFICE - DAY"),
          make_element(2, "action", "A desk."),
          make_element(3, "action", "A chair.")
        ],
        children: []
      }

      tree = PageTreeBuilder.build(page_data)
      flat = PageTreeBuilder.flatten(tree)

      assert length(flat.all_node_attrs) == 3
      assert length(flat.connections) == 2
      assert flat.screenplay_ids == [1]

      assert Enum.all?(flat.connections, &(&1.source_pin == "output"))
    end

    test "branch produces response pin connection and skips sequential" do
      page_data = %{
        screenplay_id: 1,
        elements: [
          make_element(1, "scene_heading", "INT. OFFICE"),
          make_element(2, "character", "NPC"),
          make_element(3, "dialogue", "Pick."),
          make_element(4, "response", "", %{
            "choices" => [%{"id" => "c1", "text" => "Go", "linked_screenplay_id" => 2}]
          })
        ],
        children: [
          %{
            screenplay_id: 2,
            elements: [
              make_element(20, "scene_heading", "INT. PATH"),
              make_element(21, "action", "Walking.")
            ],
            children: []
          }
        ]
      }

      tree = PageTreeBuilder.build(page_data)
      flat = PageTreeBuilder.flatten(tree)

      # Root: entry (0) + dialogue (1), Child: scene (2) + dialogue (3)
      assert length(flat.all_node_attrs) == 4

      # entry→dialogue (output), dialogue→scene (c1), scene→dialogue (output) = 3
      assert length(flat.connections) == 3

      branch_conn = Enum.find(flat.connections, &(&1.source_pin == "c1"))
      assert branch_conn.source_index == 1
      assert branch_conn.target_index == 2
      assert flat.screenplay_ids == [1, 2]
    end

    test "branching dialogue does not connect sequentially to next element" do
      page_data = %{
        screenplay_id: 1,
        elements: [
          make_element(1, "scene_heading", "INT. OFFICE"),
          make_element(2, "character", "NPC"),
          make_element(3, "dialogue", "Pick."),
          make_element(4, "response", "", %{
            "choices" => [%{"id" => "c1", "text" => "Go", "linked_screenplay_id" => 2}]
          }),
          make_element(5, "action", "After dialogue.")
        ],
        children: [
          %{
            screenplay_id: 2,
            elements: [make_element(20, "scene_heading", "INT. PATH")],
            children: []
          }
        ]
      }

      tree = PageTreeBuilder.build(page_data)
      flat = PageTreeBuilder.flatten(tree)

      # Root: entry (0), dialogue (1), dialogue_action (2). Child: scene (3).
      assert length(flat.all_node_attrs) == 4

      # Only entry→dialogue is sequential (dialogue is branching → skip to action)
      sequential_conns = Enum.filter(flat.connections, &(&1.source_pin == "output"))
      assert length(sequential_conns) == 1
      assert hd(sequential_conns).source_index == 0
    end

    test "nested branches produce recursive connections" do
      page_data = %{
        screenplay_id: 1,
        elements: [
          make_element(1, "scene_heading", "INT. OFFICE"),
          make_element(2, "character", "NPC"),
          make_element(3, "dialogue", "Pick."),
          make_element(4, "response", "", %{
            "choices" => [%{"id" => "c1", "text" => "Go", "linked_screenplay_id" => 2}]
          })
        ],
        children: [
          %{
            screenplay_id: 2,
            elements: [
              make_element(20, "scene_heading", "INT. PATH"),
              make_element(21, "character", "NPC2"),
              make_element(22, "dialogue", "Next?"),
              make_element(23, "response", "", %{
                "choices" => [%{"id" => "c2", "text" => "Deeper", "linked_screenplay_id" => 3}]
              })
            ],
            children: [
              %{
                screenplay_id: 3,
                elements: [
                  make_element(30, "scene_heading", "INT. DEEP"),
                  make_element(31, "action", "Very deep.")
                ],
                children: []
              }
            ]
          }
        ]
      }

      tree = PageTreeBuilder.build(page_data)
      flat = PageTreeBuilder.flatten(tree)

      # Root: 2 + Child: 2 + Grandchild: 2 = 6 nodes
      assert length(flat.all_node_attrs) == 6
      assert Enum.sort(flat.screenplay_ids) == [1, 2, 3]

      branch_conns = Enum.filter(flat.connections, &(&1.source_pin in ["c1", "c2"]))
      assert length(branch_conns) == 2
    end

    test "condition node gets true+false connections" do
      page_data = %{
        screenplay_id: 1,
        elements: [
          make_element(1, "scene_heading", "INT. OFFICE"),
          make_element(2, "conditional", "", %{"condition" => %{"logic" => "all", "rules" => []}}),
          make_element(3, "action", "After condition.")
        ],
        children: []
      }

      tree = PageTreeBuilder.build(page_data)
      flat = PageTreeBuilder.flatten(tree)

      assert length(flat.connections) == 3

      condition_conns = Enum.filter(flat.connections, &(&1.source_index == 1))
      pins = Enum.map(condition_conns, & &1.source_pin) |> Enum.sort()
      assert pins == ["false", "true"]
    end

    test "exit node is terminal (no outgoing connection)" do
      page_data = %{
        screenplay_id: 1,
        elements: [
          make_element(1, "scene_heading", "INT. OFFICE"),
          make_element(2, "transition", "FADE OUT."),
          make_element(3, "action", "After transition.")
        ],
        children: []
      }

      tree = PageTreeBuilder.build(page_data)
      flat = PageTreeBuilder.flatten(tree)

      # entry→exit (output) only — exit is terminal
      assert length(flat.connections) == 1
      assert hd(flat.connections).source_pin == "output"
      assert hd(flat.connections).source_index == 0
    end
  end
end
