defmodule StoryarnWeb.FlowLive.Handlers.DebugHandlersTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Evaluator.Engine
  alias StoryarnWeb.FlowLive.Handlers.DebugHandlers

  # ===========================================================================
  # Test helpers
  # ===========================================================================

  defp node(id, type, data \\ %{}) do
    %{id: id, type: type, data: data}
  end

  defp conn(source_id, source_pin, target_id, target_pin \\ "input") do
    %{
      source_node_id: source_id,
      source_pin: source_pin,
      target_node_id: target_id,
      target_pin: target_pin
    }
  end

  defp build_socket(overrides) do
    defaults = %{
      debug_state: nil,
      debug_nodes: %{},
      debug_connections: [],
      debug_speed: 800,
      debug_auto_playing: false,
      debug_auto_timer: nil,
      debug_active_tab: "console",
      debug_panel_open: true,
      debug_editing_var: nil,
      debug_var_filter: "",
      debug_var_changed_only: false,
      current_scope: %{user: %{id: 1}},
      project: %{id: 1, slug: "test-project"},
      workspace: %{slug: "test-workspace"},
      flow: %{id: 1, name: "Test Flow"}
    }

    assigns = Map.merge(defaults, overrides)

    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns)
    }
  end

  # ===========================================================================
  # handle_debug_play/1
  # ===========================================================================

  describe "handle_debug_play/1" do
    test "sets debug_auto_playing to true" do
      socket = build_socket(%{debug_speed: 500})

      {:noreply, result} = DebugHandlers.handle_debug_play(socket)

      assert result.assigns.debug_auto_playing == true
    end

    test "schedules :debug_auto_step message" do
      socket = build_socket(%{debug_speed: 200})

      {:noreply, _result} = DebugHandlers.handle_debug_play(socket)

      assert_receive :debug_auto_step, 500
    end
  end

  # ===========================================================================
  # handle_debug_pause/1
  # ===========================================================================

  describe "handle_debug_pause/1" do
    test "sets debug_auto_playing to false" do
      socket = build_socket(%{debug_auto_playing: true})

      {:noreply, result} = DebugHandlers.handle_debug_pause(socket)

      assert result.assigns.debug_auto_playing == false
    end
  end

  # ===========================================================================
  # handle_debug_auto_step/1
  # ===========================================================================

  describe "handle_debug_auto_step/1" do
    test "stops when debug_auto_playing is false" do
      state = Engine.init(%{}, 1)
      socket = build_socket(%{debug_state: state, debug_auto_playing: false})

      {:noreply, result} = DebugHandlers.handle_debug_auto_step(socket)

      assert result.assigns.debug_auto_playing == false
    end

    test "stops when state is nil" do
      socket = build_socket(%{debug_state: nil, debug_auto_playing: true})

      {:noreply, result} = DebugHandlers.handle_debug_auto_step(socket)

      assert result.assigns.debug_auto_playing == false
    end

    test "stops when status is :finished" do
      state = %{Engine.init(%{}, 1) | status: :finished}
      socket = build_socket(%{debug_state: state, debug_auto_playing: true})

      {:noreply, result} = DebugHandlers.handle_debug_auto_step(socket)

      assert result.assigns.debug_auto_playing == false
    end

    test "keeps auto-play active when status is :waiting_input" do
      state = %{Engine.init(%{}, 1) | status: :waiting_input}
      socket = build_socket(%{debug_state: state, debug_auto_playing: true})

      {:noreply, result} = DebugHandlers.handle_debug_auto_step(socket)

      # Auto-play stays active, waiting for user to choose a response
      assert result.assigns.debug_auto_playing == true
    end

    test "steps and continues when engine returns :ok" do
      # entry(1) -> hub(2) -> exit(3)
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub"),
        3 => node(3, "exit")
      }

      connections = [
        conn(1, "output", 2),
        conn(2, "output", 3)
      ]

      state = Engine.init(%{}, 1)

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections,
          debug_auto_playing: true,
          debug_speed: 200
        })

      {:noreply, result} = DebugHandlers.handle_debug_auto_step(socket)

      # Should have advanced one step and still be playing
      assert result.assigns.debug_state.step_count >= 1
    end

    test "stops auto-play when step results in :finished" do
      # entry(1) -> exit(2) — stepping from entry reaches exit which finishes
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "exit")
      }

      connections = [conn(1, "output", 2)]

      # Step once to reach a state where next step finishes
      state = Engine.init(%{}, 1)
      {:ok, state} = Engine.step(state, nodes, connections)
      # Now at exit node, next step will finish
      {:finished, state} = Engine.step(state, nodes, connections)

      socket =
        build_socket(%{
          debug_state: %{state | status: :paused},
          debug_nodes: nodes,
          debug_connections: connections,
          debug_auto_playing: true,
          debug_speed: 200
        })

      # The node at exit has status :finished after step, auto_step should stop
      {:noreply, result} = DebugHandlers.handle_debug_auto_step(socket)

      # Either stops because status or error, auto_playing should be false
      assert result.assigns.debug_auto_playing == false
    end
  end

  # ===========================================================================
  # handle_debug_choose_response/2 — resumes auto-play
  # ===========================================================================

  describe "handle_debug_choose_response/2 resumes auto-play" do
    test "schedules next step when auto-play is active" do
      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "dialogue", %{
            "text" => "Hello",
            "responses" => [
              %{"id" => "r1", "text" => "Option A", "condition" => "", "instruction" => ""},
              %{"id" => "r2", "text" => "Option B", "condition" => "", "instruction" => ""}
            ]
          }),
        3 => node(3, "exit")
      }

      connections = [
        conn(1, "output", 2),
        conn(2, "r1", 3)
      ]

      # Step through entry -> dialogue to get to waiting_input state
      state = Engine.init(%{}, 1)
      {:ok, state} = Engine.step(state, nodes, connections)
      {:waiting_input, state} = Engine.step(state, nodes, connections)

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections,
          debug_auto_playing: true,
          debug_speed: 200
        })

      {:noreply, result} = DebugHandlers.handle_debug_choose_response(%{"id" => "r1"}, socket)

      # Auto-play should still be active and a timer scheduled
      assert result.assigns.debug_auto_playing == true
      assert_receive :debug_auto_step, 500
    end

    test "does not schedule next step when auto-play is inactive" do
      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "dialogue", %{
            "text" => "Hello",
            "responses" => [
              %{"id" => "r1", "text" => "Option A", "condition" => "", "instruction" => ""},
              %{"id" => "r2", "text" => "Option B", "condition" => "", "instruction" => ""}
            ]
          }),
        3 => node(3, "exit")
      }

      connections = [
        conn(1, "output", 2),
        conn(2, "r1", 3)
      ]

      state = Engine.init(%{}, 1)
      {:ok, state} = Engine.step(state, nodes, connections)
      {:waiting_input, state} = Engine.step(state, nodes, connections)

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections,
          debug_auto_playing: false,
          debug_speed: 200
        })

      {:noreply, _result} = DebugHandlers.handle_debug_choose_response(%{"id" => "r1"}, socket)

      refute_receive :debug_auto_step, 300
    end
  end

  # ===========================================================================
  # auto_step pauses at breakpoint
  # ===========================================================================

  describe "auto_step pauses at breakpoint" do
    test "auto_step pauses at breakpoint" do
      # entry(1) -> hub(2) -> hub(3) -> exit(4)
      # Set breakpoint on node 3
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub"),
        3 => node(3, "hub"),
        4 => node(4, "exit")
      }

      connections = [
        conn(1, "default", 2),
        conn(2, "default", 3),
        conn(3, "default", 4)
      ]

      # Start at entry, step once to reach hub(2)
      state = Engine.init(%{}, 1)
      {:ok, state} = Engine.step(state, nodes, connections)
      assert state.current_node_id == 2

      # Set breakpoint on node 3
      state = Engine.toggle_breakpoint(state, 3)

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections,
          debug_auto_playing: true,
          debug_speed: 200
        })

      # Auto-step from hub(2) should land on hub(3) and pause due to breakpoint
      {:noreply, result} = DebugHandlers.handle_debug_auto_step(socket)

      assert result.assigns.debug_state.current_node_id == 3
      assert result.assigns.debug_auto_playing == false

      assert Enum.any?(
               result.assigns.debug_state.console,
               &(&1.message =~ "Paused at breakpoint")
             )
    end
  end

  # ===========================================================================
  # Cross-flow: flow_return via handle_debug_step
  # ===========================================================================

  describe "handle_debug_step with flow_return" do
    test "stores debug state and navigates on caller_return" do
      # Parent flow: entry(1) -> subflow(2) -> exit(3)
      parent_nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "subflow", %{"referenced_flow_id" => 42}),
        3 => node(3, "exit")
      }

      parent_conns = [conn(1, "default", 2), conn(2, "default", 3)]

      # Sub-flow: entry(10) -> exit(11, caller_return)
      sub_nodes = %{
        10 => node(10, "entry"),
        11 => node(11, "exit", %{"exit_mode" => "caller_return"})
      }

      sub_conns = [conn(10, "default", 11)]

      # State is at exit node 11 (caller_return) in the sub-flow, with parent on call stack
      state = Engine.init(%{}, 10)
      state = %{state | current_flow_id: 1}
      state = Engine.push_flow_context(state, 2, parent_nodes, parent_conns)
      state = %{state | current_flow_id: 42}

      # Step through entry to get to exit
      {:ok, state} = Engine.step(state, sub_nodes, sub_conns)
      assert state.current_node_id == 11

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: sub_nodes,
          debug_connections: sub_conns
        })

      # Step at exit(caller_return) → flow_return → stores and navigates
      {:noreply, result} = DebugHandlers.handle_debug_step(socket)

      # Socket should have a navigation redirect set
      assert result.redirected

      # Stored debug state should have parent flow data restored
      stored = Storyarn.Flows.DebugSessionStore.take({1, 1})
      assert stored.debug_nodes == parent_nodes
      assert stored.debug_connections == parent_conns
      assert stored.debug_state.current_node_id == 3
      assert stored.debug_state.call_stack == []
    end

    test "advances to correct next node after return" do
      # Parent: entry(1) -> subflow(2) -> hub(3) -> exit(4)
      parent_nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "subflow", %{"referenced_flow_id" => 42}),
        3 => node(3, "hub"),
        4 => node(4, "exit")
      }

      parent_conns = [conn(1, "default", 2), conn(2, "default", 3), conn(3, "default", 4)]

      # Sub-flow at exit node with caller_return
      sub_nodes = %{
        10 => node(10, "exit", %{"exit_mode" => "caller_return"})
      }

      state = Engine.init(%{}, 10)
      state = %{state | current_flow_id: 1}
      state = Engine.push_flow_context(state, 2, parent_nodes, parent_conns)
      state = %{state | current_flow_id: 42}

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: sub_nodes,
          debug_connections: []
        })

      {:noreply, _result} = DebugHandlers.handle_debug_step(socket)

      # Verify stored state has correct next node
      stored = Storyarn.Flows.DebugSessionStore.take({1, 1})
      assert stored.debug_state.current_node_id == 3
      assert stored.debug_state.current_flow_id == 1
    end

    test "finishes when return node has no outgoing connection" do
      # Parent flow: entry(1) -> subflow(2) (no connection from subflow)
      parent_nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "subflow", %{"referenced_flow_id" => 42})
      }

      parent_conns = [conn(1, "default", 2)]

      sub_nodes = %{
        10 => node(10, "exit", %{"exit_mode" => "caller_return"})
      }

      state = Engine.init(%{}, 10)
      state = %{state | current_flow_id: 1}
      state = Engine.push_flow_context(state, 2, parent_nodes, parent_conns)
      state = %{state | current_flow_id: 42}

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: sub_nodes,
          debug_connections: []
        })

      {:noreply, _result} = DebugHandlers.handle_debug_step(socket)

      stored = Storyarn.Flows.DebugSessionStore.take({1, 1})
      assert stored.debug_state.status == :finished
    end

    test "nested return restores correct parent context" do
      # Grandparent flow: entry(1) -> subflow_A(2) -> exit(3)
      gp_nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "subflow", %{"referenced_flow_id" => 10}),
        3 => node(3, "exit")
      }

      gp_conns = [conn(1, "default", 2), conn(2, "default", 3)]

      # Parent flow: entry(10) -> subflow_B(11) -> exit(12)
      parent_nodes = %{
        10 => node(10, "entry"),
        11 => node(11, "subflow", %{"referenced_flow_id" => 20}),
        12 => node(12, "exit")
      }

      parent_conns = [conn(10, "default", 11), conn(11, "default", 12)]

      # Current (child) flow at exit with caller_return
      child_nodes = %{
        20 => node(20, "exit", %{"exit_mode" => "caller_return"})
      }

      # Build state: grandparent pushed first, then parent
      state = Engine.init(%{}, 20)
      state = %{state | current_flow_id: 1}
      state = Engine.push_flow_context(state, 2, gp_nodes, gp_conns)
      state = %{state | current_flow_id: 10}
      state = Engine.push_flow_context(state, 11, parent_nodes, parent_conns)
      state = %{state | current_flow_id: 20}

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: child_nodes,
          debug_connections: []
        })

      # First return: back to parent flow
      {:noreply, _result} = DebugHandlers.handle_debug_step(socket)

      stored = Storyarn.Flows.DebugSessionStore.take({1, 1})
      assert stored.debug_nodes == parent_nodes
      assert stored.debug_connections == parent_conns
      assert stored.debug_state.current_node_id == 12
      # Still has grandparent on stack
      assert length(stored.debug_state.call_stack) == 1
    end
  end
end
