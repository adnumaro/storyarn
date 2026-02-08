defmodule StoryarnWeb.FlowLive.Handlers.DebugHandlersTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Evaluator.Engine
  alias StoryarnWeb.FlowLive.Handlers.DebugHandlers

  # ===========================================================================
  # Test helpers
  # ===========================================================================

  defp var(value, block_type) do
    %{
      value: value,
      initial_value: value,
      previous_value: value,
      source: :initial,
      block_type: block_type,
      block_id: 1,
      sheet_shortcut: "test",
      variable_name: "var"
    }
  end

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
      debug_active_tab: "console",
      debug_panel_open: true
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
  # handle_debug_set_speed/2
  # ===========================================================================

  describe "handle_debug_set_speed/2" do
    test "assigns parsed speed value" do
      socket = build_socket()

      {:noreply, result} = DebugHandlers.handle_debug_set_speed(%{"speed" => "400"}, socket)

      assert result.assigns.debug_speed == 400
    end

    test "clamps speed to minimum 200ms" do
      socket = build_socket()

      {:noreply, result} = DebugHandlers.handle_debug_set_speed(%{"speed" => "50"}, socket)

      assert result.assigns.debug_speed == 200
    end

    test "clamps speed to maximum 3000ms" do
      socket = build_socket()

      {:noreply, result} = DebugHandlers.handle_debug_set_speed(%{"speed" => "5000"}, socket)

      assert result.assigns.debug_speed == 3000
    end

    test "defaults to 800 for invalid input" do
      socket = build_socket()

      {:noreply, result} = DebugHandlers.handle_debug_set_speed(%{"speed" => "abc"}, socket)

      assert result.assigns.debug_speed == 800
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
        2 => node(2, "dialogue", %{
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
        2 => node(2, "dialogue", %{
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
  # handle_debug_reset/1 — cancels auto-play
  # ===========================================================================

  describe "handle_debug_reset/1 cancels auto-play" do
    test "sets debug_auto_playing to false" do
      state = Engine.init(%{"mc.health" => var(100, "number")}, 1)

      socket =
        build_socket(%{
          debug_state: state,
          debug_auto_playing: true
        })

      {:noreply, result} = DebugHandlers.handle_debug_reset(socket)

      assert result.assigns.debug_auto_playing == false
    end
  end

  # ===========================================================================
  # handle_debug_stop/1 — cancels auto-play
  # ===========================================================================

  describe "handle_debug_stop/1 cancels auto-play" do
    test "sets debug_auto_playing to false" do
      socket = build_socket(%{debug_auto_playing: true})

      {:noreply, result} = DebugHandlers.handle_debug_stop(socket)

      assert result.assigns.debug_auto_playing == false
      assert result.assigns.debug_state == nil
    end
  end

  # ===========================================================================
  # handle_debug_edit_variable/2
  # ===========================================================================

  describe "handle_debug_edit_variable/2" do
    test "sets debug_editing_var assign" do
      socket = build_socket(%{debug_editing_var: nil})

      {:noreply, result} = DebugHandlers.handle_debug_edit_variable(%{"key" => "mc.health"}, socket)

      assert result.assigns.debug_editing_var == "mc.health"
    end
  end

  # ===========================================================================
  # handle_debug_cancel_edit/1
  # ===========================================================================

  describe "handle_debug_cancel_edit/1" do
    test "clears debug_editing_var" do
      socket = build_socket(%{debug_editing_var: "mc.health"})

      {:noreply, result} = DebugHandlers.handle_debug_cancel_edit(socket)

      assert result.assigns.debug_editing_var == nil
    end
  end

  # ===========================================================================
  # handle_debug_set_variable/2
  # ===========================================================================

  describe "handle_debug_set_variable/2" do
    test "updates variable value and clears editing state" do
      variables = %{"mc.health" => var(100, "number")}
      state = Engine.init(variables, 1)
      socket = build_socket(%{debug_state: state, debug_editing_var: "mc.health"})

      {:noreply, result} =
        DebugHandlers.handle_debug_set_variable(%{"key" => "mc.health", "value" => "75"}, socket)

      assert result.assigns.debug_state.variables["mc.health"].value == 75.0
      assert result.assigns.debug_state.variables["mc.health"].source == :user_override
      assert result.assigns.debug_editing_var == nil
    end

    test "parses boolean values" do
      variables = %{"mc.alive" => var(false, "boolean")}
      state = Engine.init(variables, 1)
      socket = build_socket(%{debug_state: state, debug_editing_var: "mc.alive"})

      {:noreply, result} =
        DebugHandlers.handle_debug_set_variable(%{"key" => "mc.alive", "value" => "true"}, socket)

      assert result.assigns.debug_state.variables["mc.alive"].value == true
    end

    test "handles text values" do
      variables = %{"mc.name" => var("", "text")}
      state = Engine.init(variables, 1)
      socket = build_socket(%{debug_state: state, debug_editing_var: "mc.name"})

      {:noreply, result} =
        DebugHandlers.handle_debug_set_variable(%{"key" => "mc.name", "value" => "Jaime"}, socket)

      assert result.assigns.debug_state.variables["mc.name"].value == "Jaime"
    end

    test "clears editing on unknown variable" do
      state = Engine.init(%{}, 1)
      socket = build_socket(%{debug_state: state, debug_editing_var: "unknown"})

      {:noreply, result} =
        DebugHandlers.handle_debug_set_variable(%{"key" => "unknown", "value" => "42"}, socket)

      assert result.assigns.debug_editing_var == nil
    end
  end

  # ===========================================================================
  # handle_debug_var_filter/2
  # ===========================================================================

  describe "handle_debug_var_filter/2" do
    test "assigns filter value" do
      socket = build_socket(%{debug_var_filter: ""})

      {:noreply, result} = DebugHandlers.handle_debug_var_filter(%{"filter" => "health"}, socket)

      assert result.assigns.debug_var_filter == "health"
    end

    test "clears filter with empty string" do
      socket = build_socket(%{debug_var_filter: "health"})

      {:noreply, result} = DebugHandlers.handle_debug_var_filter(%{"filter" => ""}, socket)

      assert result.assigns.debug_var_filter == ""
    end
  end

  # ===========================================================================
  # handle_debug_var_toggle_changed/1
  # ===========================================================================

  describe "handle_debug_var_toggle_changed/1" do
    test "toggles from false to true" do
      socket = build_socket(%{debug_var_changed_only: false})

      {:noreply, result} = DebugHandlers.handle_debug_var_toggle_changed(socket)

      assert result.assigns.debug_var_changed_only == true
    end

    test "toggles from true to false" do
      socket = build_socket(%{debug_var_changed_only: true})

      {:noreply, result} = DebugHandlers.handle_debug_var_toggle_changed(socket)

      assert result.assigns.debug_var_changed_only == false
    end
  end
end
