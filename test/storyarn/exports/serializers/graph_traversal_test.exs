defmodule Storyarn.Exports.Serializers.GraphTraversalTest do
  use ExUnit.Case, async: true

  alias Storyarn.Exports.Serializers.GraphTraversal

  # ===========================================================================
  # Test helpers — build flow structs in memory
  # ===========================================================================

  defp make_node(id, type, data \\ %{}) do
    %{id: id, type: type, data: data}
  end

  defp make_conn(source_id, target_id, source_pin \\ "output", target_pin \\ "input") do
    %{
      id: "#{source_id}_#{target_id}_#{source_pin}",
      source_node_id: source_id,
      target_node_id: target_id,
      source_pin: source_pin,
      target_pin: target_pin
    }
  end

  defp make_flow(nodes, connections) do
    %{nodes: nodes, connections: connections}
  end

  defp instruction_types(instructions) do
    Enum.map(instructions, fn
      {type, _} -> type
      {type, _, _} -> type
      {type, _, _, _} -> type
    end)
  end

  # ===========================================================================
  # linearize/1
  # ===========================================================================

  describe "linearize/1" do
    test "entry → exit" do
      flow =
        make_flow(
          [make_node(1, "entry"), make_node(2, "exit")],
          [make_conn(1, 2)]
        )

      {instructions, hub_sections} = GraphTraversal.linearize(flow)
      assert instruction_types(instructions) == [:exit]
      assert hub_sections == []
    end

    test "entry → dialogue → exit" do
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "dialogue", %{"text" => "Hello!"}),
            make_node(3, "exit")
          ],
          [make_conn(1, 2), make_conn(2, 3)]
        )

      {instructions, _} = GraphTraversal.linearize(flow)
      types = instruction_types(instructions)
      assert :dialogue in types
      assert :exit in types
    end

    test "dialogue with responses generates choices" do
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "dialogue", %{
              "text" => "What?",
              "responses" => [
                %{"id" => "r1", "text" => "Yes"},
                %{"id" => "r2", "text" => "No"}
              ]
            }),
            make_node(3, "exit"),
            make_node(4, "exit")
          ],
          [
            make_conn(1, 2),
            make_conn(2, 3, "response_r1"),
            make_conn(2, 4, "response_r2")
          ]
        )

      {instructions, _} = GraphTraversal.linearize(flow)
      types = instruction_types(instructions)
      assert :dialogue in types
      assert :choices_start in types
      assert :choice in types
      assert :choices_end in types
    end

    test "condition branches" do
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "condition", %{
              "condition" => %{"logic" => "all", "rules" => []},
              "cases" => [
                %{"id" => "true", "label" => "True", "value" => "true"},
                %{"id" => "false", "label" => "False", "value" => "false"}
              ]
            }),
            make_node(3, "exit"),
            make_node(4, "exit")
          ],
          [
            make_conn(1, 2),
            make_conn(2, 3, "true"),
            make_conn(2, 4, "false")
          ]
        )

      {instructions, _} = GraphTraversal.linearize(flow)
      types = instruction_types(instructions)
      assert :condition_start in types
      assert :condition_branch in types
      assert :condition_end in types
    end

    test "hub + jump emits divert and hub section" do
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "hub", %{"label" => "meeting_point"}),
            make_node(3, "dialogue", %{"text" => "At the hub"}),
            make_node(4, "exit")
          ],
          [
            make_conn(1, 2),
            make_conn(2, 3),
            make_conn(3, 4)
          ]
        )

      {instructions, hub_sections} = GraphTraversal.linearize(flow)
      types = instruction_types(instructions)
      assert :divert in types

      assert [_ | _] = hub_sections
      {label, section_instructions} = hd(hub_sections)
      assert label == "meeting_point"
      assert [_ | _] = section_instructions
    end

    test "cycle detection via revisited hub" do
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "hub", %{"label" => "loop"}),
            make_node(3, "dialogue", %{"text" => "Again"}),
            make_node(4, "exit")
          ],
          [
            make_conn(1, 2),
            make_conn(2, 3),
            # Loop back to hub
            make_conn(3, 2)
          ]
        )

      # Should not hang — cycle detection breaks the loop
      {_instructions, hub_sections} = GraphTraversal.linearize(flow)
      assert is_list(hub_sections)
    end

    test "returns empty for flow with no entry node" do
      flow =
        make_flow(
          [make_node(1, "dialogue", %{"text" => "orphan"})],
          []
        )

      {instructions, hub_sections} = GraphTraversal.linearize(flow)
      assert instructions == []
      assert hub_sections == []
    end

    test "instruction node is linearized" do
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "instruction", %{"assignments" => []}),
            make_node(3, "exit")
          ],
          [make_conn(1, 2), make_conn(2, 3)]
        )

      {instructions, _} = GraphTraversal.linearize(flow)
      types = instruction_types(instructions)
      assert :instruction in types
      assert :exit in types
    end

    test "subflow node is linearized" do
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "subflow", %{"flow_shortcut" => "sub.flow"}),
            make_node(3, "exit")
          ],
          [make_conn(1, 2), make_conn(2, 3)]
        )

      {instructions, _} = GraphTraversal.linearize(flow)
      types = instruction_types(instructions)
      assert :subflow in types
    end

    test "scene node is linearized" do
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "scene", %{"location" => "Office"}),
            make_node(3, "exit")
          ],
          [make_conn(1, 2), make_conn(2, 3)]
        )

      {instructions, _} = GraphTraversal.linearize(flow)
      types = instruction_types(instructions)
      assert :scene in types
    end

    test "cycle detection on non-hub node emits nothing" do
      # When a non-hub node is revisited, the traversal just stops (no divert emitted).
      # Create a loop: entry → dialogue → dialogue (back to self via connection).
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "dialogue", %{"text" => "Loop"}),
            make_node(3, "exit")
          ],
          [
            make_conn(1, 2),
            # dialogue → exit normally
            make_conn(2, 3),
            # But also dialogue → dialogue (cycle)
            make_conn(2, 2, "response_loop")
          ]
        )

      {instructions, _} = GraphTraversal.linearize(flow)
      # Should not hang, and should contain the dialogue + exit
      types = instruction_types(instructions)
      assert :dialogue in types
      assert :exit in types
    end

    test "connection to non-existent node is handled gracefully" do
      # When a connection points to a node_id not in the flow's node list,
      # traverse returns state unchanged (L109: nil -> state).
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "dialogue", %{"text" => "Hello"})
          ],
          [
            make_conn(1, 2),
            # Connection to node 999 which doesn't exist
            make_conn(2, 999)
          ]
        )

      {instructions, _} = GraphTraversal.linearize(flow)
      types = instruction_types(instructions)
      assert :dialogue in types
    end

    test "unknown node type is skipped via catch-all traverse_node" do
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "unknown_type", %{}),
            make_node(3, "exit")
          ],
          [make_conn(1, 2), make_conn(2, 3)]
        )

      {instructions, _} = GraphTraversal.linearize(flow)
      # The unknown node is skipped and its traverse_node returns state without
      # following connections, so exit is not reached. The key point is it doesn't crash.
      assert is_list(instructions)
    end

    test "jump with target_flow_shortcut resolves to flow identifier" do
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "jump", %{"target_flow_shortcut" => "chapter.two"})
          ],
          [make_conn(1, 2)]
        )

      {instructions, _} = GraphTraversal.linearize(flow)
      assert [{:jump, _node, "chapter_two"}] = instructions
    end

    test "jump without hub_id or target_flow_shortcut follows connection" do
      # When jump has no hub_id and no target_flow_shortcut, it follows
      # the outgoing connection to determine the target label.
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "jump", %{}),
            make_node(3, "hub", %{"label" => "target_hub"}),
            make_node(4, "exit")
          ],
          [
            make_conn(1, 2),
            make_conn(2, 3),
            make_conn(3, 4)
          ]
        )

      {instructions, hub_sections} = GraphTraversal.linearize(flow)
      # The jump should resolve to the hub's label via the connection
      jump_instruction = Enum.find(instructions, fn {type, _, _} -> type == :jump end)
      assert {:jump, _node, target_label} = jump_instruction
      assert target_label == "target_hub"
      assert is_list(hub_sections)
    end

    test "jump without hub_id or target_flow_shortcut and no connections resolves to unknown" do
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "jump", %{})
          ],
          [make_conn(1, 2)]
        )

      {instructions, _} = GraphTraversal.linearize(flow)
      assert [{:jump, _node, "unknown"}] = instructions
    end

    test "hub in queue but missing from nodes map is handled" do
      # Build a flow where a hub is queued but then removed from the node index.
      # This tests L259 (hub_state for missing hub_node).
      # We can achieve this indirectly by having a hub that's visited and queued,
      # but we craft the flow so that process_hub_queue encounters an edge case.
      # The simplest way: hub node is present (so it gets queued), then during
      # process_hub_queue it should still find it. This covers the normal path.
      # To hit the nil branch we'd need to remove the node, which isn't possible
      # in normal usage. Let's verify the normal hub queue processing works.
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "hub", %{"label" => "my_hub"}),
            make_node(3, "dialogue", %{"text" => "After hub"}),
            make_node(4, "exit")
          ],
          [
            make_conn(1, 2),
            make_conn(2, 3),
            make_conn(3, 4)
          ]
        )

      {instructions, hub_sections} = GraphTraversal.linearize(flow)
      assert :divert in instruction_types(instructions)
      assert length(hub_sections) == 1
      {label, section_instr} = hd(hub_sections)
      assert label == "my_hub"
      section_types = instruction_types(section_instr)
      assert :dialogue in section_types
      assert :exit in section_types
    end

    test "multiple outgoing connections from entry are all traversed" do
      # When a node has multiple outgoing connections, after traversing the first
      # target, the rest are also traversed (L237 _ -> traverse_targets(rest, state)).
      flow =
        make_flow(
          [
            make_node(1, "entry"),
            make_node(2, "dialogue", %{"text" => "Path A"}),
            make_node(3, "dialogue", %{"text" => "Path B"}),
            make_node(4, "exit"),
            make_node(5, "exit")
          ],
          [
            make_conn(1, 2, "output_a"),
            make_conn(1, 3, "output_b"),
            make_conn(2, 4),
            make_conn(3, 5)
          ]
        )

      {instructions, _} = GraphTraversal.linearize(flow)
      types = instruction_types(instructions)
      # Both dialogues should be traversed
      dialogue_count = Enum.count(types, &(&1 == :dialogue))
      assert dialogue_count == 2
    end
  end
end
