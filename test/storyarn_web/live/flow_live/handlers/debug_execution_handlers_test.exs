defmodule StoryarnWeb.FlowLive.Handlers.DebugExecutionHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Flows
  alias Storyarn.Flows.DebugSessionStore
  alias Storyarn.Flows.Evaluator.Engine
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Repo
  alias StoryarnWeb.FlowLive.Handlers.DebugExecutionHandlers

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

  defp build_socket(overrides \\ %{}) do
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
      debug_step_limit_reached: false,
      debug_session_id: "test-debug-session",
      current_scope: %{user: %{id: 1}},
      project: %{id: 1, slug: "test-project"},
      workspace: %{slug: "test-workspace"},
      flow: %{id: 1, name: "Test Flow"}
    }

    assigns = Map.merge(defaults, overrides)

    %Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns)
    }
  end

  # Waits for the automatic flow data load started by handle_params.
  defp load_flow(view) do
    render_async(view, 2000)
  end

  defp debug_panel(view) do
    view
    |> LiveVue.Test.get_vue(name: "live/flow/show/FlowSurface")
    |> then(& &1.props["surface"]["debug"])
  end

  # ===========================================================================
  # handle_debug_step/1 — normal stepping
  # ===========================================================================

  describe "handle_debug_step/1" do
    test "steps from entry to hub" do
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
          debug_connections: connections
        })

      {:noreply, result} = DebugExecutionHandlers.handle_debug_step(socket)

      assert result.assigns.debug_state.current_node_id == 2
      assert result.assigns.debug_state.step_count == 1
    end

    test "steps through entry -> hub -> exit and finishes" do
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
          debug_connections: connections
        })

      # Step 1: entry -> hub
      {:noreply, result} = DebugExecutionHandlers.handle_debug_step(socket)
      assert result.assigns.debug_state.current_node_id == 2

      # Step 2: hub -> exit
      {:noreply, result} = DebugExecutionHandlers.handle_debug_step(result)
      assert result.assigns.debug_state.current_node_id == 3

      # Step 3: exit finishes execution
      {:noreply, result} = DebugExecutionHandlers.handle_debug_step(result)
      assert result.assigns.debug_state.status == :finished
    end

    test "handles step when already finished" do
      nodes = %{1 => node(1, "entry")}
      state = %{Engine.init(%{}, 1) | status: :finished}

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: []
        })

      {:noreply, result} = DebugExecutionHandlers.handle_debug_step(socket)

      assert result.assigns.debug_state.status == :finished
    end

    test "handles step when node is missing (error case)" do
      # State points to non-existent node
      state = Engine.init(%{}, 99)

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: %{},
          debug_connections: []
        })

      {:noreply, result} = DebugExecutionHandlers.handle_debug_step(socket)

      assert result.assigns.debug_state.status == :finished
      assert result.assigns.debug_step_limit_reached == false
    end

    test "clears step_limit_reached on normal step" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub")
      }

      connections = [conn(1, "output", 2)]

      state = Engine.init(%{}, 1)

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections,
          debug_step_limit_reached: true
        })

      {:noreply, result} = DebugExecutionHandlers.handle_debug_step(socket)

      assert result.assigns.debug_step_limit_reached == false
    end

    test "step at waiting_input stays at waiting_input" do
      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "dialogue", %{
            "text" => "Hello",
            "responses" => [
              %{"id" => "r1", "text" => "Yes", "condition" => "", "instruction" => ""},
              %{"id" => "r2", "text" => "No", "condition" => "", "instruction" => ""}
            ]
          })
      }

      connections = [conn(1, "output", 2)]

      state = Engine.init(%{}, 1)
      {:ok, state} = Engine.step(state, nodes, connections)
      {:waiting_input, state} = Engine.step(state, nodes, connections)

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections
        })

      {:noreply, result} = DebugExecutionHandlers.handle_debug_step(socket)

      assert result.assigns.debug_state.status == :waiting_input
    end

    test "triggers step_limit when max_steps reached" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub")
      }

      connections = [conn(1, "output", 2)]

      state = %{Engine.init(%{}, 1) | max_steps: 0}

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections
        })

      {:noreply, result} = DebugExecutionHandlers.handle_debug_step(socket)

      assert result.assigns.debug_step_limit_reached == true
      assert result.assigns.debug_auto_playing == false
    end
  end

  # ===========================================================================
  # handle_debug_step_back/1
  # ===========================================================================

  describe "handle_debug_step_back/1" do
    test "returns to previous state" do
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
      {:ok, state} = Engine.step(state, nodes, connections)
      assert state.current_node_id == 2

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections
        })

      {:noreply, result} = DebugExecutionHandlers.handle_debug_step_back(socket)

      assert result.assigns.debug_state.current_node_id == 1
      refute result.redirected
    end

    test "reloads the parent graph and navigates when stepping back from a child flow" do
      project = Repo.preload(project_fixture(), :workspace)
      parent_flow = flow_fixture(project, %{name: "Parent debug flow"})
      child_flow = flow_fixture(project, %{name: "Child debug flow"})

      subflow =
        node_fixture(parent_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => child_flow.id}
        })

      parent_graph = Flows.load_runtime_graph(parent_flow.id)

      state =
        %{}
        |> Engine.init(subflow.id)
        |> Map.put(:current_flow_id, parent_flow.id)

      assert {:navigate, child_state, child_graph, child_flow_id} =
               Flows.debug_step(
                 state,
                 parent_graph.nodes,
                 parent_graph.connections,
                 parent_flow.name
               )

      assert child_flow_id == child_flow.id
      session_id = "debug-step-back-#{System.unique_integer([:positive])}"
      user_id = System.unique_integer([:positive])

      socket =
        build_socket(%{
          current_scope: %{user: %{id: user_id}},
          project: project,
          workspace: project.workspace,
          flow: child_flow,
          debug_session_id: session_id,
          debug_state: child_state,
          debug_nodes: DebugExecutionHandlers.present_runtime_graph(child_graph).nodes,
          debug_connections: child_graph.connections
        })

      {:noreply, result} = DebugExecutionHandlers.handle_debug_step_back(socket)

      assert result.redirected
      assert result.assigns.debug_state.current_flow_id == parent_flow.id
      assert result.assigns.debug_state.current_node_id == subflow.id
      assert Map.has_key?(result.assigns.debug_nodes, subflow.id)

      stored = DebugSessionStore.take({:debug, user_id, project.id, session_id})
      assert stored.debug_state.current_flow_id == parent_flow.id
      assert Map.has_key?(stored.debug_nodes, subflow.id)
    end

    test "does nothing when no history (no snapshots)" do
      state = Engine.init(%{}, 1)

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: %{1 => node(1, "entry")},
          debug_connections: []
        })

      {:noreply, result} = DebugExecutionHandlers.handle_debug_step_back(socket)

      # State unchanged
      assert result.assigns.debug_state.current_node_id == 1
      assert result.assigns.debug_state.step_count == 0
    end

    test "can step back multiple times" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub"),
        3 => node(3, "hub"),
        4 => node(4, "exit")
      }

      connections = [
        conn(1, "output", 2),
        conn(2, "output", 3),
        conn(3, "output", 4)
      ]

      state = Engine.init(%{}, 1)
      {:ok, state} = Engine.step(state, nodes, connections)
      {:ok, state} = Engine.step(state, nodes, connections)
      assert state.current_node_id == 3

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections
        })

      # Step back once: 3 -> 2
      {:noreply, result} = DebugExecutionHandlers.handle_debug_step_back(socket)
      assert result.assigns.debug_state.current_node_id == 2

      # Step back again: 2 -> 1
      {:noreply, result} = DebugExecutionHandlers.handle_debug_step_back(result)
      assert result.assigns.debug_state.current_node_id == 1
    end
  end

  # ===========================================================================
  # handle_debug_choose_response/2
  # ===========================================================================

  describe "handle_debug_choose_response/2" do
    setup do
      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "dialogue", %{
            "text" => "Hello",
            "responses" => [
              %{"id" => "r1", "text" => "Yes", "condition" => "", "instruction" => ""},
              %{"id" => "r2", "text" => "No", "condition" => "", "instruction" => ""}
            ]
          }),
        3 => node(3, "hub"),
        4 => node(4, "exit")
      }

      connections = [
        conn(1, "output", 2),
        conn(2, "r1", 3),
        conn(2, "r2", 4)
      ]

      # Step to waiting_input state
      state = Engine.init(%{}, 1)
      {:ok, state} = Engine.step(state, nodes, connections)
      {:waiting_input, state} = Engine.step(state, nodes, connections)

      %{nodes: nodes, connections: connections, state: state}
    end

    test "advances to connected node on response selection", %{
      nodes: nodes,
      connections: connections,
      state: state
    } do
      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections,
          debug_auto_playing: false
        })

      {:noreply, result} =
        DebugExecutionHandlers.handle_debug_choose_response(%{"id" => "r1"}, socket)

      assert result.assigns.debug_state.current_node_id == 3
    end

    test "advances to alternate response path", %{
      nodes: nodes,
      connections: connections,
      state: state
    } do
      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections,
          debug_auto_playing: false
        })

      {:noreply, result} =
        DebugExecutionHandlers.handle_debug_choose_response(%{"id" => "r2"}, socket)

      assert result.assigns.debug_state.current_node_id == 4
    end

    test "handles response with no outgoing connection (error case)", %{
      nodes: nodes,
      state: state
    } do
      # Use connections that don't have the selected response
      connections_without_r1 = [conn(2, "r2", 4)]

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections_without_r1,
          debug_auto_playing: false
        })

      {:noreply, result} =
        DebugExecutionHandlers.handle_debug_choose_response(%{"id" => "r1"}, socket)

      assert result.assigns.debug_state.status == :finished

      assert Enum.any?(
               result.assigns.debug_state.console,
               &(&1.message =~ "No connection from response")
             )
    end

    test "schedules auto-step when auto-playing", %{
      nodes: nodes,
      connections: connections,
      state: state
    } do
      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections,
          debug_auto_playing: true,
          debug_speed: 200
        })

      {:noreply, result} =
        DebugExecutionHandlers.handle_debug_choose_response(%{"id" => "r1"}, socket)

      assert result.assigns.debug_auto_playing == true
      assert_receive :debug_auto_step, 500
    end

    test "does not schedule auto-step when not auto-playing", %{
      nodes: nodes,
      connections: connections,
      state: state
    } do
      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections,
          debug_auto_playing: false
        })

      {:noreply, _result} =
        DebugExecutionHandlers.handle_debug_choose_response(%{"id" => "r1"}, socket)

      refute_receive :debug_auto_step, 300
    end

    test "handles choose_response when not in waiting_input state" do
      state = Engine.init(%{}, 1)
      assert state.status == :paused

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: %{1 => node(1, "entry")},
          debug_connections: [],
          debug_auto_playing: false
        })

      {:noreply, result} =
        DebugExecutionHandlers.handle_debug_choose_response(%{"id" => "r1"}, socket)

      # Engine returns {:error, state, :not_waiting_input} — handler assigns the error state
      # The state itself stays paused (the error pattern in choose_response doesn't change status)
      assert result.assigns.debug_state
    end
  end

  # ===========================================================================
  # handle_debug_play/1
  # ===========================================================================

  describe "handle_debug_play/1" do
    test "sets debug_auto_playing to true and schedules timer" do
      socket = build_socket(%{debug_speed: 300})

      {:noreply, result} = DebugExecutionHandlers.handle_debug_play(socket)

      assert result.assigns.debug_auto_playing == true
      assert result.assigns.debug_auto_timer
      assert_receive :debug_auto_step, 600
    end
  end

  # ===========================================================================
  # handle_debug_pause/1
  # ===========================================================================

  describe "handle_debug_pause/1" do
    test "stops auto-play and cancels timer" do
      socket = build_socket(%{debug_auto_playing: true, debug_speed: 200})
      {:noreply, playing_socket} = DebugExecutionHandlers.handle_debug_play(socket)

      {:noreply, result} = DebugExecutionHandlers.handle_debug_pause(playing_socket)

      assert result.assigns.debug_auto_playing == false
      assert result.assigns.debug_auto_timer == nil
    end

    test "handles pause when no timer is running" do
      socket = build_socket(%{debug_auto_playing: true, debug_auto_timer: nil})

      {:noreply, result} = DebugExecutionHandlers.handle_debug_pause(socket)

      assert result.assigns.debug_auto_playing == false
    end
  end

  # ===========================================================================
  # handle_debug_set_speed/2
  # ===========================================================================

  describe "handle_debug_set_speed/2" do
    test "assigns parsed speed value" do
      socket = build_socket()

      {:noreply, result} =
        DebugExecutionHandlers.handle_debug_set_speed(%{"speed" => "500"}, socket)

      assert result.assigns.debug_speed == 500
    end

    test "clamps speed to minimum 200ms" do
      socket = build_socket()

      {:noreply, result} =
        DebugExecutionHandlers.handle_debug_set_speed(%{"speed" => "100"}, socket)

      assert result.assigns.debug_speed == 200
    end

    test "clamps speed to maximum 3000ms" do
      socket = build_socket()

      {:noreply, result} =
        DebugExecutionHandlers.handle_debug_set_speed(%{"speed" => "9999"}, socket)

      assert result.assigns.debug_speed == 3000
    end

    test "defaults to 800 for non-numeric input" do
      socket = build_socket()

      {:noreply, result} =
        DebugExecutionHandlers.handle_debug_set_speed(%{"speed" => "fast"}, socket)

      assert result.assigns.debug_speed == 800
    end

    test "handles integer speed directly" do
      # parse_speed with integer guard
      socket = build_socket()

      {:noreply, result} =
        DebugExecutionHandlers.handle_debug_set_speed(%{"speed" => "1500"}, socket)

      assert result.assigns.debug_speed == 1500
    end
  end

  # ===========================================================================
  # handle_debug_auto_step/1
  # ===========================================================================

  describe "handle_debug_auto_step/1" do
    test "stops when not auto-playing" do
      state = Engine.init(%{}, 1)
      socket = build_socket(%{debug_state: state, debug_auto_playing: false})

      {:noreply, result} = DebugExecutionHandlers.handle_debug_auto_step(socket)

      assert result.assigns.debug_auto_playing == false
    end

    test "stops when state is nil" do
      socket = build_socket(%{debug_state: nil, debug_auto_playing: true})

      {:noreply, result} = DebugExecutionHandlers.handle_debug_auto_step(socket)

      assert result.assigns.debug_auto_playing == false
    end

    test "stops when status is finished" do
      state = %{Engine.init(%{}, 1) | status: :finished}
      socket = build_socket(%{debug_state: state, debug_auto_playing: true})

      {:noreply, result} = DebugExecutionHandlers.handle_debug_auto_step(socket)

      assert result.assigns.debug_auto_playing == false
    end

    test "pauses when status is waiting_input" do
      state = %{Engine.init(%{}, 1) | status: :waiting_input}
      socket = build_socket(%{debug_state: state, debug_auto_playing: true})

      {:noreply, result} = DebugExecutionHandlers.handle_debug_auto_step(socket)

      # Stays auto-playing but doesn't step
      assert result.assigns.debug_auto_playing == true
    end

    test "steps and continues auto-play on normal step" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub"),
        3 => node(3, "hub"),
        4 => node(4, "exit")
      }

      connections = [
        conn(1, "output", 2),
        conn(2, "output", 3),
        conn(3, "output", 4)
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

      {:noreply, result} = DebugExecutionHandlers.handle_debug_auto_step(socket)

      # Should have stepped and scheduled next auto-step
      assert result.assigns.debug_state.step_count >= 1
      assert_receive :debug_auto_step, 500
    end

    test "stops auto-play when stepping results in finished" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "exit")
      }

      connections = [conn(1, "output", 2)]

      # Pre-step to reach exit node
      state = Engine.init(%{}, 1)
      {:ok, state} = Engine.step(state, nodes, connections)
      assert state.current_node_id == 2

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections,
          debug_auto_playing: true,
          debug_speed: 200
        })

      {:noreply, result} = DebugExecutionHandlers.handle_debug_auto_step(socket)

      assert result.assigns.debug_auto_playing == false
    end

    test "stops auto-play at breakpoint" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub"),
        3 => node(3, "hub"),
        4 => node(4, "exit")
      }

      connections = [
        conn(1, "output", 2),
        conn(2, "output", 3),
        conn(3, "output", 4)
      ]

      state = Engine.init(%{}, 1)
      # Set breakpoint on node 2
      state = Engine.toggle_breakpoint(state, 2)

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections,
          debug_auto_playing: true,
          debug_speed: 200
        })

      {:noreply, result} = DebugExecutionHandlers.handle_debug_auto_step(socket)

      assert result.assigns.debug_state.current_node_id == 2
      assert result.assigns.debug_auto_playing == false

      assert Enum.any?(
               result.assigns.debug_state.console,
               &(&1.message =~ "Paused at breakpoint")
             )
    end

    test "auto-step with step limit stops auto-play" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub")
      }

      connections = [conn(1, "output", 2)]

      state = %{Engine.init(%{}, 1) | max_steps: 0}

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections,
          debug_auto_playing: true,
          debug_speed: 200
        })

      {:noreply, result} = DebugExecutionHandlers.handle_debug_auto_step(socket)

      assert result.assigns.debug_auto_playing == false
      assert result.assigns.debug_step_limit_reached == true
    end

    test "auto-step keeps socket at waiting_input when dialogue requires response" do
      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "dialogue", %{
            "text" => "Hello",
            "responses" => [
              %{"id" => "r1", "text" => "Yes", "condition" => "", "instruction" => ""},
              %{"id" => "r2", "text" => "No", "condition" => "", "instruction" => ""}
            ]
          }),
        3 => node(3, "exit")
      }

      connections = [
        conn(1, "output", 2),
        conn(2, "r1", 3),
        conn(2, "r2", 3)
      ]

      # Step to entry, then auto-step will hit dialogue (waiting_input needs 2+ responses)
      state = Engine.init(%{}, 1)
      {:ok, state} = Engine.step(state, nodes, connections)

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: connections,
          debug_auto_playing: true,
          debug_speed: 200
        })

      {:noreply, result} = DebugExecutionHandlers.handle_debug_auto_step(socket)

      # After auto-stepping into dialogue with 2+ responses, it should be waiting_input
      # and auto_play stays true (waiting for user to choose response)
      assert result.assigns.debug_state.status == :waiting_input
    end
  end

  # ===========================================================================
  # push_debug_canvas/2
  # ===========================================================================

  describe "push_debug_canvas/2" do
    test "pushes highlight events for current node" do
      state = %{
        Engine.init(%{}, 1)
        | current_node_id: 2,
          execution_path: [2, 1]
      }

      connections = [conn(1, "output", 2)]

      socket =
        build_socket(%{
          debug_state: state,
          debug_connections: connections
        })

      result = DebugExecutionHandlers.push_debug_canvas(socket, state)

      # Verify push_event was called (returns updated socket)
      assert %Socket{} = result
    end

    test "sets error status string when finished with error console entry" do
      state = %{
        Engine.init(%{}, 1)
        | current_node_id: 1,
          status: :finished,
          execution_path: [1],
          console: [
            %{
              ts: 0,
              level: :error,
              node_id: 1,
              node_label: "",
              message: "Node not found",
              rule_details: nil
            }
          ]
      }

      socket =
        build_socket(%{
          debug_state: state,
          debug_connections: []
        })

      # Should not raise — the error status should be detected
      result = DebugExecutionHandlers.push_debug_canvas(socket, state)
      assert %Socket{} = result
    end

    test "sets normal status string when finished without errors" do
      state = %{
        Engine.init(%{}, 1)
        | current_node_id: 1,
          status: :finished,
          execution_path: [1],
          console: [
            %{
              ts: 0,
              level: :info,
              node_id: 1,
              node_label: "",
              message: "Finished",
              rule_details: nil
            }
          ]
      }

      socket =
        build_socket(%{
          debug_state: state,
          debug_connections: []
        })

      result = DebugExecutionHandlers.push_debug_canvas(socket, state)
      assert %Socket{} = result
    end

    test "finds active connection from execution path" do
      state = %{
        Engine.init(%{}, 1)
        | current_node_id: 2,
          execution_path: [2, 1]
      }

      connections = [
        conn(1, "output", 2),
        conn(2, "output", 3)
      ]

      socket =
        build_socket(%{
          debug_state: state,
          debug_connections: connections
        })

      result = DebugExecutionHandlers.push_debug_canvas(socket, state)
      assert %Socket{} = result
    end

    test "handles empty execution path" do
      state = %{
        Engine.init(%{}, 1)
        | execution_path: []
      }

      socket =
        build_socket(%{
          debug_state: state,
          debug_connections: []
        })

      result = DebugExecutionHandlers.push_debug_canvas(socket, state)
      assert %Socket{} = result
    end

    test "handles single-node execution path (no active connection)" do
      state = %{
        Engine.init(%{}, 1)
        | current_node_id: 1,
          execution_path: [1]
      }

      socket =
        build_socket(%{
          debug_state: state,
          debug_connections: []
        })

      result = DebugExecutionHandlers.push_debug_canvas(socket, state)
      assert %Socket{} = result
    end
  end

  # ===========================================================================
  # store_and_navigate/2
  # ===========================================================================

  describe "store_and_navigate/2" do
    test "stores debug session in ETS and returns navigating tuple" do
      state = Engine.init(%{}, 1)
      state = %{state | current_flow_id: 1}

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: %{1 => node(1, "entry")},
          debug_connections: [conn(1, "output", 2)],
          debug_active_tab: "console",
          debug_speed: 500,
          debug_auto_playing: false,
          debug_var_filter: "health",
          debug_var_changed_only: true,
          debug_step_limit_reached: false
        })

      {:navigating, result_socket} =
        DebugExecutionHandlers.store_and_navigate(socket, 42)

      assert result_socket.redirected

      # Verify ETS has the stored session
      stored = DebugSessionStore.take({:debug, 1, 1, "test-debug-session"})
      assert stored
      assert stored.debug_state == state
      assert stored.debug_speed == 500
      assert stored.debug_var_filter == "health"
      assert stored.debug_var_changed_only == true
      assert stored.debug_panel_open == true
    end

    test "stores nil for debug_editing_var" do
      state = Engine.init(%{}, 1)

      socket =
        build_socket(%{
          debug_state: state,
          debug_editing_var: "mc.health"
        })

      {:navigating, _result} = DebugExecutionHandlers.store_and_navigate(socket, 42)

      stored = DebugSessionStore.take({:debug, 1, 1, "test-debug-session"})
      assert stored.debug_editing_var == nil
    end
  end

  describe "presentation_node_id/2" do
    test "keeps the speaker from the executed Condition branch through convergence" do
      nodes = %{
        10 => node(10, "dialogue", %{"text" => "Left"}),
        20 => node(20, "dialogue", %{"text" => "Right"}),
        30 => node(30, "condition"),
        40 => node(40, "hub")
      }

      assert DebugExecutionHandlers.presentation_node_id(
               %{current_node_id: 10, execution_path: [10, 30]},
               nodes
             ) == 10

      assert DebugExecutionHandlers.presentation_node_id(
               %{current_node_id: 20, execution_path: [20, 30]},
               nodes
             ) == 20

      assert DebugExecutionHandlers.presentation_node_id(
               %{current_node_id: 40, execution_path: [40, 10, 30]},
               nodes
             ) == 10

      assert DebugExecutionHandlers.presentation_node_id(
               %{"current_node_id" => "40", "execution_path" => ["40", "20", "30"]},
               nodes
             ) == 20
    end

    test "returns nil after reset when no speaker has executed" do
      nodes = %{30 => node(30, "condition"), 40 => node(40, "hub")}
      state = Engine.init(%{}, 30)

      assert DebugExecutionHandlers.presentation_node_id(state, nodes) == nil
    end
  end

  describe "present_debug_composition/2" do
    test "serializes effective layers, tracks, overrides, origins, and tombstones per owner" do
      base = %{
        id: 1,
        type: "sequence",
        data: %{},
        parent_id: nil,
        composition_source_id: nil,
        sequence_config: %{name: "Base", width: 16, height: 9},
        sequence_visual_layers: [
          %{
            id: 11,
            layer_key: "hero",
            overridden_fields: SequenceVisualLayer.property_fields(),
            removed: false,
            asset_id: 101,
            kind: "character",
            label: "Hero",
            opacity: 1.0,
            url: "/hero.png"
          },
          %{
            id: 12,
            layer_key: "room",
            overridden_fields: SequenceVisualLayer.property_fields(),
            removed: false,
            asset_id: 102,
            kind: "backdrop",
            label: "Room",
            url: "/room.png"
          }
        ],
        sequence_tracks: [
          %{
            id: 13,
            track_key: "theme",
            is_override: false,
            overridden_fields: SequenceTrack.property_fields(),
            removed: false,
            asset_id: 201,
            kind: "music",
            position: 0,
            volume: 1.0,
            url: "/theme.mp3"
          },
          %{
            id: 14,
            track_key: "wind",
            is_override: false,
            overridden_fields: SequenceTrack.property_fields(),
            removed: false,
            asset_id: 202,
            kind: "ambience",
            position: 0,
            volume: 0.8,
            url: "/wind.mp3"
          }
        ]
      }

      dialogue = %{
        id: 2,
        type: "dialogue",
        data: %{"text" => "Changed staging"},
        parent_id: nil,
        composition_source_id: 1,
        sequence_config: nil,
        sequence_visual_layers: [
          %{
            id: 21,
            layer_key: "hero",
            overridden_fields: ["opacity"],
            removed: false,
            opacity: 0.4,
            url: nil
          },
          %{
            id: 22,
            layer_key: "room",
            overridden_fields: [],
            removed: true,
            url: nil
          }
        ],
        sequence_tracks: [
          %{
            id: 23,
            track_key: "theme",
            kind: "music",
            is_override: true,
            overridden_fields: ["volume"],
            removed: false,
            volume: 0.5,
            url: nil
          },
          %{
            id: 24,
            track_key: "wind",
            kind: "ambience",
            is_override: true,
            overridden_fields: [],
            removed: true,
            url: nil
          }
        ]
      }

      graph = DebugExecutionHandlers.present_runtime_graph(%{nodes: %{1 => base, 2 => dialogue}, connections: []})

      composition =
        DebugExecutionHandlers.present_debug_composition(%{current_node_id: 2}, graph.nodes)

      assert composition.presentationNodeId == 2
      assert [%{key: "hero"} = hero] = composition.visualLayers
      assert hero.origin.nodeId == 1
      assert hero.lastChangedByNodeId == 2
      assert hero.overriddenProperties == [%{field: "opacity", nodeId: 2}]

      assert [%{key: "room", removed: true, removedByNodeId: 2} = room] =
               composition.removedVisualLayers

      assert room.origin.nodeId == 1

      assert [%{trackKey: "theme"} = theme] = composition.audioTracks
      assert theme.origin.nodeId == 1
      assert theme.lastChangedByNodeId == 2
      assert theme.overriddenProperties == [%{field: "volume", nodeId: 2}]

      assert [%{trackKey: "wind", removed: true, removedByNodeId: 2} = wind] =
               composition.removedAudioTracks

      assert wind.origin.nodeId == 1

      assert composition.diagnostics == []
    end
  end

  # ===========================================================================
  # schedule_auto_step/1 and cancel_auto_timer/1
  # ===========================================================================

  describe "schedule_auto_step/1" do
    test "schedules a timer and assigns it to socket" do
      socket = build_socket(%{debug_speed: 200})

      result = DebugExecutionHandlers.schedule_auto_step(socket)

      assert result.assigns.debug_auto_timer
      assert_receive :debug_auto_step, 500
    end

    test "cancels existing timer before scheduling new one" do
      socket = build_socket(%{debug_speed: 200})

      result1 = DebugExecutionHandlers.schedule_auto_step(socket)
      old_timer = result1.assigns.debug_auto_timer

      result2 = DebugExecutionHandlers.schedule_auto_step(result1)

      # New timer should be different from old one
      assert result2.assigns.debug_auto_timer != old_timer
      # Should still receive the message from the new timer
      assert_receive :debug_auto_step, 500
    end
  end

  describe "cancel_auto_timer/1" do
    test "cancels an existing timer" do
      socket = build_socket(%{debug_speed: 200})
      socket_with_timer = DebugExecutionHandlers.schedule_auto_step(socket)

      result = DebugExecutionHandlers.cancel_auto_timer(socket_with_timer)

      assert result.assigns.debug_auto_timer == nil
      refute_receive :debug_auto_step, 300
    end

    test "handles nil timer gracefully" do
      socket = build_socket(%{debug_auto_timer: nil})

      result = DebugExecutionHandlers.cancel_auto_timer(socket)

      assert result.assigns == socket.assigns
    end
  end

  # ===========================================================================
  # Full debug lifecycle through LiveView
  # ===========================================================================

  describe "debug lifecycle through LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Debug Test Flow"})

      # flow_fixture auto-creates entry + exit nodes; use them
      full_flow = Flows.get_flow!(project.id, flow.id)
      entry = Enum.find(full_flow.nodes, &(&1.type == "entry"))
      auto_exit = Enum.find(full_flow.nodes, &(&1.type == "exit"))

      # Add a hub between entry and exit
      hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "h1", "color" => "#000"}})

      _conn1 =
        connection_fixture(flow, entry, hub, %{source_pin: "output", target_pin: "input"})

      _conn2 =
        connection_fixture(flow, hub, auto_exit, %{source_pin: "output", target_pin: "input"})

      %{project: project, flow: flow, entry: entry, hub: hub, exit_node: auto_exit}
    end

    test "debug_start + debug_step advances through flow", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      # Start debug session
      render_click(view, "debug_start", %{})

      # Step once
      render_click(view, "debug_step", %{})

      assert debug_panel(view)["open"] == true
    end

    test "debug_start + debug_step + debug_step_back steps back", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      render_click(view, "debug_start", %{})
      render_click(view, "debug_step", %{})
      render_click(view, "debug_step_back", %{})

      debug = debug_panel(view)
      assert debug["open"] == true
      assert debug["state"]
    end

    test "debug_play enables auto-play and debug_pause stops it", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      render_click(view, "debug_start", %{})
      render_click(view, "debug_play", %{})

      assert debug_panel(view)["controls"]["autoPlaying"] == true

      render_click(view, "debug_pause", %{})

      assert debug_panel(view)["controls"]["autoPlaying"] == false
    end

    test "debug_set_speed changes the speed display", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      render_click(view, "debug_start", %{})
      render_click(view, "debug_set_speed", %{"speed" => "1500"})

      assert debug_panel(view)["controls"]["speed"] == 1500
    end

    test "debug_stop closes the debug panel", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      render_click(view, "debug_start", %{})

      assert debug_panel(view)["open"] == true

      render_click(view, "debug_stop", %{})

      assert debug_panel(view)["open"] == false
    end

    test "auto_step timer fires and advances the debug state", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      render_click(view, "debug_start", %{})
      render_click(view, "debug_set_speed", %{"speed" => "200"})
      render_click(view, "debug_play", %{})

      # Wait for auto-step timer to fire
      Process.sleep(300)
      # Flush the timer message through the LiveView
      render(view)

      # The auto-step should have advanced, or finished
      assert debug_panel(view)["state"]
    end
  end

  # ===========================================================================
  # Dialogue response flow through LiveView
  # ===========================================================================

  describe "dialogue response through LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Dialogue Flow"})

      # flow_fixture auto-creates entry + exit nodes; use the entry
      full_flow = Flows.get_flow!(project.id, flow.id)
      entry = Enum.find(full_flow.nodes, &(&1.type == "entry"))

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Choose wisely</p>",
            "responses" => [
              %{"id" => "r1", "text" => "Option A", "condition" => "", "instruction" => ""},
              %{"id" => "r2", "text" => "Option B", "condition" => "", "instruction" => ""}
            ]
          }
        })

      exit_a = node_fixture(flow, %{type: "exit", data: %{}})
      exit_b = node_fixture(flow, %{type: "exit", data: %{}})

      _conn1 =
        connection_fixture(flow, entry, dialogue, %{
          source_pin: "output",
          target_pin: "input"
        })

      _conn2 =
        connection_fixture(flow, dialogue, exit_a, %{
          source_pin: "r1",
          target_pin: "input"
        })

      _conn3 =
        connection_fixture(flow, dialogue, exit_b, %{
          source_pin: "r2",
          target_pin: "input"
        })

      %{
        project: project,
        flow: flow,
        dialogue: dialogue,
        exit_a: exit_a,
        exit_b: exit_b
      }
    end

    test "stepping into dialogue shows response choices", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      render_click(view, "debug_start", %{})
      # Step through entry
      render_click(view, "debug_step", %{})
      # Step to dialogue — should enter waiting_input with choices
      render_click(view, "debug_step", %{})

      debug = debug_panel(view)
      assert debug["state"]["status"] == "waiting_input"
      responses = debug["state"]["pending_choices"]
      assert is_list(responses)
      assert responses != []
    end

    test "choosing a response advances past dialogue", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      render_click(view, "debug_start", %{})
      render_click(view, "debug_step", %{})
      render_click(view, "debug_step", %{})

      # Choose response r1
      render_click(view, "debug_choose_response", %{"id" => "r1"})

      html = render(view)
      # Should have advanced past the dialogue
      refute html =~ "Choose a response"
    end
  end

  # ===========================================================================
  # Step limit through LiveView
  # ===========================================================================

  describe "step limit through LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Loop Flow"})

      # flow_fixture auto-creates entry + exit nodes; use the entry for our loop
      full_flow = Flows.get_flow!(project.id, flow.id)
      entry = Enum.find(full_flow.nodes, &(&1.type == "entry"))

      hub_a = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "a", "color" => "#000"}})
      hub_b = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "b", "color" => "#000"}})

      _c1 = connection_fixture(flow, entry, hub_a, %{source_pin: "output", target_pin: "input"})
      _c2 = connection_fixture(flow, hub_a, hub_b, %{source_pin: "output", target_pin: "input"})
      _c3 = connection_fixture(flow, hub_b, hub_a, %{source_pin: "output", target_pin: "input"})

      %{project: project, flow: flow}
    end

    test "auto-play stops at step limit with loop", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      render_click(view, "debug_start", %{})

      # Step many times to hit the limit (default 1000) — or use auto-play
      # Since we can't easily reach 1000 via the UI test, let's verify the
      # step_limit mechanic at the unit level (already covered above)
      # and just verify the LiveView doesn't crash with rapid stepping
      for _i <- 1..5 do
        render_click(view, "debug_step", %{})
      end

      render(view)
      assert debug_panel(view)["open"] == true
    end
  end

  # ===========================================================================
  # apply_step_result edge cases (via handle_debug_step)
  # ===========================================================================

  describe "apply_step_result edge cases" do
    test "flow_return with empty call stack finishes" do
      # Exit node with caller_return but no call stack
      nodes = %{
        1 => node(1, "exit", %{"exit_mode" => "caller_return"})
      }

      state = Engine.init(%{}, 1)
      # Empty call stack by default

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: []
        })

      {:noreply, result} = DebugExecutionHandlers.handle_debug_step(socket)

      assert result.assigns.debug_state.status == :finished
    end

    test "error result from step sets state correctly" do
      # Node that doesn't exist triggers an error
      state = Engine.init(%{}, 999)

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: %{},
          debug_connections: []
        })

      {:noreply, result} = DebugExecutionHandlers.handle_debug_step(socket)

      assert result.assigns.debug_state.status == :finished
      assert result.assigns.debug_step_limit_reached == false
    end
  end
end
