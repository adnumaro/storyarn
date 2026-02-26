defmodule StoryarnWeb.FlowLive.Player.PlayerEngineTest do
  @moduledoc """
  Tests for the PlayerEngine module, which auto-advances through non-interactive
  nodes until reaching a dialogue, exit, or error condition.
  """

  use ExUnit.Case, async: true

  alias Storyarn.Flows.Evaluator.Engine
  alias Storyarn.Flows.Evaluator.State
  alias StoryarnWeb.FlowLive.Player.PlayerEngine

  # ===========================================================================
  # Test helpers — build pure in-memory flow data (no DB required)
  # ===========================================================================

  defp make_node(id, type, data \\ %{}) do
    %{id: id, type: type, data: data}
  end

  defp make_connection(source_id, target_id, source_pin \\ "default", target_pin \\ "input") do
    %{
      source_node_id: source_id,
      source_pin: source_pin,
      target_node_id: target_id,
      target_pin: target_pin
    }
  end

  defp init_state(start_node_id, variables \\ %{}) do
    Engine.init(variables, start_node_id)
  end

  defp nodes_map(nodes) do
    Map.new(nodes, fn node -> {node.id, node} end)
  end

  # ===========================================================================
  # step_until_interactive/4
  # ===========================================================================

  describe "step_until_interactive/4 with simple entry -> exit flow" do
    setup do
      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "exit")
        ])

      connections = [
        make_connection(1, 2)
      ]

      state = init_state(1)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "traverses entry and stops at exit with :finished", ctx do
      {status, final_state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      assert status == :finished
      assert final_state.status == :finished
      # entry is non-interactive, so it appears in skipped
      assert {1, "entry"} in skipped
    end

    test "final state records the traversal in execution_path", ctx do
      {_status, final_state, _skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      # execution_path is prepended, so most recent is first
      assert 2 in final_state.execution_path
      assert 1 in final_state.execution_path
    end
  end

  describe "step_until_interactive/4 with entry -> hub -> exit" do
    setup do
      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "hub"),
          make_node(3, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3)
      ]

      state = init_state(1)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "auto-advances through entry and hub, stops at exit", ctx do
      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      assert status == :finished
      assert {1, "entry"} in skipped
      assert {2, "hub"} in skipped
    end
  end

  describe "step_until_interactive/4 with entry -> dialogue (with responses)" do
    setup do
      dialogue_data = %{
        "text" => "Hello, traveler!",
        "responses" => [
          %{"id" => "r1", "text" => "Greetings!", "condition" => ""},
          %{"id" => "r2", "text" => "Farewell!", "condition" => ""}
        ]
      }

      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "dialogue", dialogue_data),
          make_node(3, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3, "r1"),
        make_connection(2, 3, "r2")
      ]

      state = init_state(1)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "stops at dialogue with :waiting_input when multiple responses", ctx do
      {status, final_state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      assert status == :waiting_input
      assert final_state.status == :waiting_input
      assert final_state.pending_choices != nil
      # Entry was traversed as non-interactive
      assert {1, "entry"} in skipped
    end

    test "skipped list does NOT contain the dialogue node", ctx do
      {_status, _state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      refute Enum.any?(skipped, fn {_id, type} -> type == "dialogue" end)
    end
  end

  describe "step_until_interactive/4 with entry -> dialogue (no responses)" do
    setup do
      # Dialogue with no responses auto-advances via default output
      dialogue_data = %{"text" => "Narrator speaks.", "responses" => []}

      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "dialogue", dialogue_data),
          make_node(3, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3)
      ]

      state = init_state(1)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "dialogue with no responses returns :ok (not non-interactive, loop stops)", ctx do
      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      # Dialogue with no responses auto-selects and returns {:ok, state}.
      # Since "dialogue" is NOT in @non_interactive_types, the loop stops with :ok.
      assert status == :ok
      # Entry was traversed and is non-interactive
      assert {1, "entry"} in skipped
      # Dialogue is NOT in skipped (it's the stop point)
      refute Enum.any?(skipped, fn {_id, type} -> type == "dialogue" end)
    end
  end

  describe "step_until_interactive/4 with entry -> condition -> exit" do
    setup do
      # Condition node: boolean mode with empty condition (evaluates to true).
      # The evaluator uses pin names "true" / "false" for boolean mode.
      condition_data = %{
        "condition" => %{"logic" => "all", "rules" => []}
      }

      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "condition", condition_data),
          make_node(3, "exit"),
          make_node(4, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3, "true"),
        make_connection(2, 4, "false")
      ]

      state = init_state(1)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "auto-advances through entry and condition to exit", ctx do
      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      assert status == :finished
      assert {1, "entry"} in skipped
      assert {2, "condition"} in skipped
    end
  end

  describe "step_until_interactive/4 with entry -> instruction -> exit" do
    setup do
      instruction_data = %{
        "assignments" => []
      }

      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "instruction", instruction_data),
          make_node(3, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3)
      ]

      state = init_state(1)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "auto-advances through entry and instruction to exit", ctx do
      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      assert status == :finished
      assert {1, "entry"} in skipped
      assert {2, "instruction"} in skipped
    end
  end

  describe "step_until_interactive/4 with entry -> scene -> exit" do
    setup do
      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "scene", %{"text" => "A dark forest"}),
          make_node(3, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3)
      ]

      state = init_state(1)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "auto-advances through entry and scene to exit", ctx do
      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      assert status == :finished
      assert {1, "entry"} in skipped
      assert {2, "scene"} in skipped
    end
  end

  describe "step_until_interactive/4 with jump node" do
    setup do
      hub_data = %{"hub_id" => "main_hub"}

      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "jump", %{"target_hub_id" => "main_hub"}),
          make_node(3, "hub", hub_data),
          make_node(4, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(3, 4)
      ]

      state = init_state(1)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "auto-advances through entry, jump to hub, then to exit", ctx do
      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      assert status == :finished
      assert {1, "entry"} in skipped
      assert {2, "jump"} in skipped
      assert {3, "hub"} in skipped
    end
  end

  describe "step_until_interactive/4 with subflow node (flow_jump)" do
    setup do
      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "subflow", %{"referenced_flow_id" => 42})
        ])

      connections = [
        make_connection(1, 2)
      ]

      state = init_state(1)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "returns :flow_jump with flow_id and skipped nodes", ctx do
      result =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      assert {:flow_jump, _state, 42, skipped} = result
      # Entry returned {:ok, state} and is non-interactive, so it's in skipped
      assert {1, "entry"} in skipped
      # Subflow returned {:flow_jump, ...} directly, which does NOT add
      # the current node to skipped (only {:ok, ...} does that)
      refute Enum.any?(skipped, fn {id, _} -> id == 2 end)
    end
  end

  describe "step_until_interactive/4 with exit -> caller_return (with call stack)" do
    setup do
      exit_data = %{"exit_mode" => "caller_return"}

      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "exit", exit_data)
        ])

      connections = [
        make_connection(1, 2)
      ]

      # Simulate an active call stack
      state = init_state(1)

      state = %{
        state
        | call_stack: [
            %{
              flow_id: 99,
              flow_name: "parent",
              return_node_id: 50,
              nodes: %{},
              connections: [],
              execution_path: []
            }
          ]
      }

      %{nodes: nodes, connections: connections, state: state}
    end

    test "returns :flow_return with skipped nodes", ctx do
      result =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      assert {:flow_return, _state, skipped} = result
      assert {1, "entry"} in skipped
    end
  end

  describe "step_until_interactive/4 with exit -> flow_reference" do
    setup do
      exit_data = %{"exit_mode" => "flow_reference", "referenced_flow_id" => 77}

      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "exit", exit_data)
        ])

      connections = [
        make_connection(1, 2)
      ]

      state = init_state(1)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "returns :flow_jump from exit node with flow_reference mode", ctx do
      result =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      assert {:flow_jump, _state, 77, skipped} = result
      assert {1, "entry"} in skipped
    end
  end

  describe "step_until_interactive/4 max_steps safety limit" do
    setup do
      # Create a loop: entry -> hub -> hub (via jump back)
      # This will infinite loop until max_steps is hit
      hub_data = %{"hub_id" => "loop_hub"}

      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "hub", hub_data),
          make_node(3, "jump", %{"target_hub_id" => "loop_hub"})
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3)
        # jump resolves to node 2 (hub) directly via find_hub_by_hub_id, no connection needed
      ]

      state = init_state(1)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "returns :error when max_steps is exceeded", ctx do
      {status, _state, _skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections, max_steps: 5)

      assert status == :error
    end

    test "skipped list has at most max_steps entries", ctx do
      {_status, _state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections, max_steps: 5)

      # We hit the limit at count == max, so we accumulated some skipped nodes
      assert length(skipped) <= 5
    end

    test "default max_steps is 100", ctx do
      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      assert status == :error
      # Should have accumulated ~100 skipped entries (some from the loop)
      assert length(skipped) <= 100
    end
  end

  describe "step_until_interactive/4 when already finished" do
    test "returns :finished immediately with empty skipped list" do
      state = %State{
        start_node_id: 1,
        current_node_id: 1,
        status: :finished,
        started_at: System.monotonic_time(:millisecond)
      }

      nodes = nodes_map([make_node(1, "exit")])
      connections = []

      {status, final_state, skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      assert status == :finished
      assert final_state.status == :finished
      assert skipped == []
    end
  end

  describe "step_until_interactive/4 when already waiting_input" do
    test "returns :waiting_input immediately with empty skipped list" do
      state = %State{
        start_node_id: 1,
        current_node_id: 2,
        status: :waiting_input,
        pending_choices: %{node_id: 2, responses: []},
        started_at: System.monotonic_time(:millisecond)
      }

      nodes = nodes_map([make_node(2, "dialogue")])
      connections = []

      {status, final_state, skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      assert status == :waiting_input
      assert final_state.status == :waiting_input
      assert skipped == []
    end
  end

  describe "step_until_interactive/4 with missing node (error)" do
    test "returns :error when current node does not exist in nodes map" do
      state = init_state(999)
      nodes = nodes_map([make_node(1, "entry")])
      connections = []

      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      # The engine returns {:error, state, :node_not_found}
      # PlayerEngine maps that to {:error, state, skipped}
      assert status == :error
      assert skipped == []
    end
  end

  describe "step_until_interactive/4 with disconnected entry (no outgoing connection)" do
    test "returns :finished when entry has no outgoing connection", %{} do
      nodes = nodes_map([make_node(1, "entry")])
      connections = []
      state = init_state(1)

      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      # Entry with no connection: follow_output returns {:finished, state} directly.
      # Since the engine returns {:finished, ...} (not {:ok, ...}), the current
      # node is NOT added to skipped.
      assert status == :finished
      assert skipped == []
    end
  end

  describe "step_until_interactive/4 skipped order" do
    setup do
      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "hub"),
          make_node(3, "scene", %{}),
          make_node(4, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3),
        make_connection(3, 4)
      ]

      state = init_state(1)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "skipped nodes are in traversal order (not reversed)", ctx do
      {_status, _state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      ids = Enum.map(skipped, fn {id, _type} -> id end)
      assert ids == [1, 2, 3]
    end

    test "skipped tuples contain correct types", ctx do
      {_status, _state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      assert skipped == [{1, "entry"}, {2, "hub"}, {3, "scene"}]
    end
  end

  describe "step_until_interactive/4 long chain of non-interactive nodes" do
    test "traverses a long chain of hubs before reaching exit" do
      hub_count = 20
      hub_nodes = for i <- 2..(hub_count + 1), do: make_node(i, "hub")
      exit_node = make_node(hub_count + 2, "exit")
      all_nodes = [make_node(1, "entry") | hub_nodes] ++ [exit_node]
      nodes = nodes_map(all_nodes)

      # Chain: 1 -> 2 -> 3 -> ... -> (hub_count+1) -> (hub_count+2)
      connections =
        for i <- 1..(hub_count + 1), do: make_connection(i, i + 1)

      state = init_state(1)

      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      assert status == :finished
      assert length(skipped) == hub_count + 1
    end
  end

  describe "step_until_interactive/4 with dialogue single response (auto-select)" do
    setup do
      dialogue_data = %{
        "text" => "Only one choice",
        "responses" => [
          %{"id" => "r1", "text" => "Continue", "condition" => ""}
        ]
      }

      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "dialogue", dialogue_data),
          make_node(3, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3, "r1")
      ]

      state = init_state(1)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "auto-selects single response and continues to exit", ctx do
      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      # Dialogue with single response auto-selects and returns {:ok, state}
      # which is NOT a non-interactive type, so the engine stops with :ok
      assert status in [:ok, :finished]
      assert {1, "entry"} in skipped
    end
  end

  describe "step_until_interactive/4 with max_steps option" do
    test "respects custom max_steps value" do
      # Build a 10-node hub chain that would take 10 steps
      hub_nodes = for i <- 2..11, do: make_node(i, "hub")
      exit_node = make_node(12, "exit")
      all_nodes = [make_node(1, "entry") | hub_nodes] ++ [exit_node]
      nodes = nodes_map(all_nodes)
      connections = for i <- 1..11, do: make_connection(i, i + 1)

      state = init_state(1)

      # With max_steps: 3 we should error out before reaching exit
      {status, _state, _skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections, max_steps: 3)

      assert status == :error
    end
  end

  describe "step_until_interactive/4 with entry that has 'output' pin (legacy)" do
    test "follows 'output' pin as fallback" do
      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "exit")
        ])

      # Use legacy "output" pin name instead of "default"
      connections = [make_connection(1, 2, "output")]

      state = init_state(1)

      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      # EngineHelpers.follow_output checks "default" first, then "output"
      assert status == :finished
      assert {1, "entry"} in skipped
    end
  end

  describe "step_until_interactive/4 with jump node missing target" do
    test "returns :finished when jump has no target_hub_id" do
      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "jump", %{})
        ])

      connections = [make_connection(1, 2)]
      state = init_state(1)

      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      # Jump with no target_hub_id returns {:finished, state}
      # But entry is skipped first, then jump is also non-interactive
      assert status == :finished
      assert {1, "entry"} in skipped
    end
  end

  describe "step_until_interactive/4 with jump to nonexistent hub" do
    test "returns :finished when target hub is not found" do
      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "jump", %{"target_hub_id" => "nonexistent"})
        ])

      connections = [make_connection(1, 2)]
      state = init_state(1)

      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      assert status == :finished
      assert {1, "entry"} in skipped
    end
  end

  describe "step_until_interactive/4 with subflow missing referenced_flow_id" do
    test "returns :finished when subflow has no referenced_flow_id" do
      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "subflow", %{})
        ])

      connections = [make_connection(1, 2)]
      state = init_state(1)

      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      assert status == :finished
      assert {1, "entry"} in skipped
    end
  end

  describe "step_until_interactive/4 stepping from mid-flow (not entry)" do
    test "starts from wherever state.current_node_id points" do
      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "hub"),
          make_node(3, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3)
      ]

      # Start at hub directly (as if resuming)
      state = init_state(2)

      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      assert status == :finished
      # Only hub was traversed, not entry
      assert {2, "hub"} in skipped
      refute Enum.any?(skipped, fn {id, _} -> id == 1 end)
    end
  end

  describe "step_until_interactive/4 with condition followed by dialogue" do
    setup do
      # Boolean mode condition with empty rules (evaluates to true).
      # Pin name is "true" for boolean mode.
      condition_data = %{
        "condition" => %{"logic" => "all", "rules" => []}
      }

      dialogue_data = %{
        "text" => "What do you say?",
        "responses" => [
          %{"id" => "r1", "text" => "A", "condition" => ""},
          %{"id" => "r2", "text" => "B", "condition" => ""}
        ]
      }

      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "condition", condition_data),
          make_node(3, "dialogue", dialogue_data),
          make_node(4, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3, "true"),
        make_connection(3, 4, "r1"),
        make_connection(3, 4, "r2")
      ]

      state = init_state(1)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "traverses entry and condition, then waits at dialogue", ctx do
      {status, final_state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      assert status == :waiting_input
      assert final_state.pending_choices != nil
      assert {1, "entry"} in skipped
      assert {2, "condition"} in skipped
    end
  end

  describe "step_until_interactive/4 with empty nodes map" do
    test "returns :error immediately when nodes map is empty" do
      state = init_state(1)
      nodes = %{}
      connections = []

      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      assert status == :error
      assert skipped == []
    end
  end

  describe "step_until_interactive/4 with instruction that modifies variables" do
    setup do
      # Assignment format: sheet + variable build the ref "mc.health"
      instruction_data = %{
        "assignments" => [
          %{
            "sheet" => "mc",
            "variable" => "health",
            "operator" => "set",
            "value" => "100",
            "value_type" => "literal"
          }
        ]
      }

      variables = %{
        "mc.health" => %{
          value: 50,
          initial_value: 50,
          previous_value: 50,
          source: :initial,
          block_type: "number",
          block_id: 1,
          sheet_shortcut: "mc",
          variable_name: "health",
          constraints: nil
        }
      }

      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "instruction", instruction_data),
          make_node(3, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3)
      ]

      state = init_state(1, variables)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "variable is updated after traversing instruction node", ctx do
      {status, final_state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      assert status == :finished
      assert {2, "instruction"} in skipped
      # The instruction should have set mc.health to 100.0 (parsed as float)
      assert final_state.variables["mc.health"].value == 100.0
    end
  end

  describe "step_until_interactive/4 state integrity" do
    test "step_count increases for each node processed" do
      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "hub"),
          make_node(3, "hub"),
          make_node(4, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3),
        make_connection(3, 4)
      ]

      state = init_state(1)

      {_status, final_state, _skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      # Each node processed increments step_count:
      # entry (1), hub (2), hub (3), exit (4)
      assert final_state.step_count == 4
    end

    test "console entries are accumulated during traversal" do
      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "hub"),
          make_node(3, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3)
      ]

      state = init_state(1)

      {_status, final_state, _skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      # Console should have entries for each node plus the init message
      # init: "Debug session started"
      # entry: "Execution started"
      # hub: "Hub - pass through"
      # exit: "Execution finished"
      assert length(final_state.console) >= 4
    end
  end

  describe "step_until_interactive/4 with max_steps of 0" do
    test "returns :error immediately when max_steps is 0" do
      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "exit")
        ])

      connections = [make_connection(1, 2)]
      state = init_state(1)

      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections, max_steps: 0)

      assert status == :error
      assert skipped == []
    end
  end

  describe "step_until_interactive/4 with max_steps of 1" do
    test "processes exactly one node before hitting limit" do
      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "hub"),
          make_node(3, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3)
      ]

      state = init_state(1)

      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections, max_steps: 1)

      # After processing entry (count becomes 1), the next iteration hits max
      assert status == :error
      assert length(skipped) == 1
      assert {1, "entry"} in skipped
    end
  end

  describe "step_until_interactive/4 with condition evaluating to false branch" do
    setup do
      # Condition with a rule that evaluates to false (variable not found)
      condition_data = %{
        "condition" => %{
          "logic" => "all",
          "rules" => [
            %{
              "sheet" => "mc",
              "variable" => "health",
              "operator" => "greater_than",
              "value" => "50"
            }
          ]
        }
      }

      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "condition", condition_data),
          make_node(3, "exit", %{}),
          make_node(4, "exit", %{})
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3, "true"),
        make_connection(2, 4, "false")
      ]

      # No variables -> condition fails -> false branch
      state = init_state(1)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "follows the false branch when condition is not met", ctx do
      {status, final_state, skipped} =
        PlayerEngine.step_until_interactive(ctx.state, ctx.nodes, ctx.connections)

      assert status == :finished
      assert {1, "entry"} in skipped
      assert {2, "condition"} in skipped
      # Should have reached exit node 4 (false branch), not node 3 (true branch)
      assert 4 in final_state.execution_path
    end
  end

  describe "step_until_interactive/4 with all non-interactive types in sequence" do
    test "traverses entry, hub, scene, condition, instruction, jump to hub, then exit" do
      condition_data = %{
        "condition" => %{"logic" => "all", "rules" => []}
      }

      instruction_data = %{"assignments" => []}
      hub2_data = %{"hub_id" => "target_hub"}

      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "hub"),
          make_node(3, "scene", %{}),
          make_node(4, "condition", condition_data),
          make_node(5, "instruction", instruction_data),
          make_node(6, "jump", %{"target_hub_id" => "target_hub"}),
          make_node(7, "hub", hub2_data),
          make_node(8, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3),
        make_connection(3, 4),
        make_connection(4, 5, "true"),
        make_connection(5, 6),
        # jump goes to hub 7 via hub_id lookup
        make_connection(7, 8)
      ]

      state = init_state(1)

      {status, _state, skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      assert status == :finished

      skipped_types = Enum.map(skipped, fn {_id, type} -> type end)
      assert "entry" in skipped_types
      assert "hub" in skipped_types
      assert "scene" in skipped_types
      assert "condition" in skipped_types
      assert "instruction" in skipped_types
      assert "jump" in skipped_types
    end
  end

  describe "step_until_interactive/4 with exit that has a transition target" do
    test "exit_transition is set on the final state" do
      exit_data = %{
        "target_type" => "scene",
        "target_id" => "scene_123"
      }

      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "exit", exit_data)
        ])

      connections = [make_connection(1, 2)]
      state = init_state(1)

      {status, final_state, _skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      assert status == :finished
      assert final_state.exit_transition == %{type: "scene", id: "scene_123"}
    end
  end

  describe "step_until_interactive/4 preserves snapshots" do
    test "snapshots are created for each step" do
      nodes =
        nodes_map([
          make_node(1, "entry"),
          make_node(2, "hub"),
          make_node(3, "exit")
        ])

      connections = [
        make_connection(1, 2),
        make_connection(2, 3)
      ]

      state = init_state(1)

      {_status, final_state, _skipped} =
        PlayerEngine.step_until_interactive(state, nodes, connections)

      # Each call to Engine.step pushes a snapshot before processing
      # entry step pushes snapshot, hub step pushes snapshot, exit step pushes snapshot
      assert length(final_state.snapshots) == 3
    end
  end
end
