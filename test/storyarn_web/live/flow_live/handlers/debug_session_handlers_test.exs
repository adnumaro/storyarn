defmodule StoryarnWeb.FlowLive.Handlers.DebugSessionHandlersTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Evaluator.Engine
  alias StoryarnWeb.FlowLive.Handlers.DebugSessionHandlers

  # ===========================================================================
  # Helpers
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

  defp conn(source_id, source_pin, target_id) do
    %{
      source_node_id: source_id,
      source_pin: source_pin,
      target_node_id: target_id,
      target_pin: "input"
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
  # handle_debug_start/1
  # ===========================================================================

  describe "handle_debug_start/1" do
    test "returns socket unchanged when debug_state already exists" do
      state = Engine.init(%{}, 1)
      socket = build_socket(%{debug_state: state})

      {:noreply, result} = DebugSessionHandlers.handle_debug_start(socket)

      # Should not change anything - state already exists
      assert result.assigns.debug_state == state
    end
  end

  # ===========================================================================
  # handle_debug_change_start_node/2
  # ===========================================================================

  describe "handle_debug_change_start_node/2" do
    test "resets session to new start node" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub"),
        3 => node(3, "exit")
      }

      state = Engine.init(%{}, 1)

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: [conn(1, "output", 2)]
        })

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_change_start_node(%{"node_id" => "2"}, socket)

      assert result.assigns.debug_state.start_node_id == 2
      assert result.assigns.debug_state.current_node_id == 2
      assert result.assigns.debug_auto_playing == false
    end

    test "ignores non-existent node id" do
      state = Engine.init(%{}, 1)

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: %{1 => node(1, "entry")},
          debug_connections: []
        })

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_change_start_node(%{"node_id" => "99"}, socket)

      assert result.assigns.debug_state.start_node_id == 1
    end

    test "ignores invalid node id string" do
      state = Engine.init(%{}, 1)

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: %{1 => node(1, "entry")},
          debug_connections: []
        })

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_change_start_node(%{"node_id" => "abc"}, socket)

      assert result.assigns.debug_state.start_node_id == 1
    end
  end

  # ===========================================================================
  # handle_debug_reset/1
  # ===========================================================================

  describe "handle_debug_reset/1" do
    test "resets state with empty call stack" do
      nodes = %{1 => node(1, "entry"), 2 => node(2, "hub")}
      state = Engine.init(%{}, 1)
      {:ok, state} = Engine.step(state, nodes, [conn(1, "output", 2)])

      socket =
        build_socket(%{
          debug_state: state,
          debug_nodes: nodes,
          debug_connections: [conn(1, "output", 2)],
          debug_auto_playing: true
        })

      {:noreply, result} = DebugSessionHandlers.handle_debug_reset(socket)

      assert result.assigns.debug_state.current_node_id == 1
      assert result.assigns.debug_state.step_count == 0
      assert result.assigns.debug_auto_playing == false
      assert result.assigns.debug_step_limit_reached == false
    end
  end

  # ===========================================================================
  # handle_debug_stop/1
  # ===========================================================================

  describe "handle_debug_stop/1" do
    test "clears all debug state" do
      state = Engine.init(%{}, 1)

      socket =
        build_socket(%{
          debug_state: state,
          debug_auto_playing: true,
          debug_panel_open: true,
          debug_nodes: %{1 => node(1, "entry")},
          debug_connections: [conn(1, "output", 2)]
        })

      {:noreply, result} = DebugSessionHandlers.handle_debug_stop(socket)

      assert result.assigns.debug_state == nil
      assert result.assigns.debug_panel_open == false
      assert result.assigns.debug_auto_playing == false
      assert result.assigns.debug_step_limit_reached == false
      assert result.assigns.debug_nodes == %{}
      assert result.assigns.debug_connections == []
    end
  end

  # ===========================================================================
  # handle_debug_tab_change/2
  # ===========================================================================

  describe "handle_debug_tab_change/2" do
    test "assigns new tab value" do
      socket = build_socket(%{debug_active_tab: "console"})

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_tab_change(%{"tab" => "variables"}, socket)

      assert result.assigns.debug_active_tab == "variables"
    end
  end

  # ===========================================================================
  # handle_debug_edit_variable/2
  # ===========================================================================

  describe "handle_debug_edit_variable/2" do
    test "sets editing var key" do
      socket = build_socket()

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_edit_variable(%{"key" => "mc.health"}, socket)

      assert result.assigns.debug_editing_var == "mc.health"
    end
  end

  # ===========================================================================
  # handle_debug_cancel_edit/1
  # ===========================================================================

  describe "handle_debug_cancel_edit/1" do
    test "clears editing var" do
      socket = build_socket(%{debug_editing_var: "mc.health"})

      {:noreply, result} = DebugSessionHandlers.handle_debug_cancel_edit(socket)

      assert result.assigns.debug_editing_var == nil
    end
  end

  # ===========================================================================
  # handle_debug_set_variable/2
  # ===========================================================================

  describe "handle_debug_set_variable/2" do
    test "sets number variable" do
      variables = %{"mc.health" => var(100, "number")}
      state = Engine.init(variables, 1)
      socket = build_socket(%{debug_state: state, debug_editing_var: "mc.health"})

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_set_variable(
          %{"key" => "mc.health", "value" => "75"},
          socket
        )

      assert result.assigns.debug_state.variables["mc.health"].value == 75.0
      assert result.assigns.debug_editing_var == nil
    end

    test "sets boolean variable to true" do
      variables = %{"mc.alive" => var(false, "boolean")}
      state = Engine.init(variables, 1)
      socket = build_socket(%{debug_state: state})

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_set_variable(
          %{"key" => "mc.alive", "value" => "true"},
          socket
        )

      assert result.assigns.debug_state.variables["mc.alive"].value == true
    end

    test "sets boolean variable to false for non-true value" do
      variables = %{"mc.alive" => var(true, "boolean")}
      state = Engine.init(variables, 1)
      socket = build_socket(%{debug_state: state})

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_set_variable(
          %{"key" => "mc.alive", "value" => "anything"},
          socket
        )

      assert result.assigns.debug_state.variables["mc.alive"].value == false
    end

    test "sets text variable" do
      variables = %{"mc.name" => var("", "text")}
      state = Engine.init(variables, 1)
      socket = build_socket(%{debug_state: state})

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_set_variable(
          %{"key" => "mc.name", "value" => "Jaime"},
          socket
        )

      assert result.assigns.debug_state.variables["mc.name"].value == "Jaime"
    end

    test "handles invalid number with warning" do
      variables = %{"mc.health" => var(100, "number")}
      state = Engine.init(variables, 1)
      socket = build_socket(%{debug_state: state})

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_set_variable(
          %{"key" => "mc.health", "value" => "abc"},
          socket
        )

      # Falls back to 0 and adds console warning
      assert result.assigns.debug_state.variables["mc.health"].value == 0

      assert Enum.any?(result.assigns.debug_state.console, fn entry ->
               entry.level == :warning and String.contains?(entry.message, "Invalid number")
             end)
    end

    test "empty string for number defaults to 0 without warning" do
      variables = %{"mc.health" => var(100, "number")}
      state = Engine.init(variables, 1)
      socket = build_socket(%{debug_state: state})

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_set_variable(
          %{"key" => "mc.health", "value" => ""},
          socket
        )

      assert result.assigns.debug_state.variables["mc.health"].value == 0
      # No warning for empty string
      refute Enum.any?(result.assigns.debug_state.console, fn entry ->
               entry.level == :warning
             end)
    end

    test "clears editing on unknown variable" do
      state = Engine.init(%{}, 1)
      socket = build_socket(%{debug_state: state, debug_editing_var: "unknown"})

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_set_variable(
          %{"key" => "unknown", "value" => "42"},
          socket
        )

      assert result.assigns.debug_editing_var == nil
    end
  end

  # ===========================================================================
  # handle_debug_var_filter/2
  # ===========================================================================

  describe "handle_debug_var_filter/2" do
    test "assigns filter value" do
      socket = build_socket()

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_var_filter(%{"filter" => "health"}, socket)

      assert result.assigns.debug_var_filter == "health"
    end

    test "clears filter with empty string" do
      socket = build_socket(%{debug_var_filter: "health"})

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_var_filter(%{"filter" => ""}, socket)

      assert result.assigns.debug_var_filter == ""
    end
  end

  # ===========================================================================
  # handle_debug_var_toggle_changed/1
  # ===========================================================================

  describe "handle_debug_var_toggle_changed/1" do
    test "toggles from false to true" do
      socket = build_socket(%{debug_var_changed_only: false})

      {:noreply, result} = DebugSessionHandlers.handle_debug_var_toggle_changed(socket)

      assert result.assigns.debug_var_changed_only == true
    end

    test "toggles from true to false" do
      socket = build_socket(%{debug_var_changed_only: true})

      {:noreply, result} = DebugSessionHandlers.handle_debug_var_toggle_changed(socket)

      assert result.assigns.debug_var_changed_only == false
    end
  end

  # ===========================================================================
  # handle_debug_continue_past_limit/1
  # ===========================================================================

  describe "handle_debug_continue_past_limit/1" do
    test "extends step limit and clears flag" do
      state = Engine.init(%{}, 1)
      socket = build_socket(%{debug_state: state, debug_step_limit_reached: true})

      {:noreply, result} = DebugSessionHandlers.handle_debug_continue_past_limit(socket)

      assert result.assigns.debug_step_limit_reached == false
      assert result.assigns.debug_state.max_steps > state.max_steps
    end
  end

  # ===========================================================================
  # handle_debug_toggle_breakpoint/2
  # ===========================================================================

  describe "handle_debug_toggle_breakpoint/2" do
    test "adds breakpoint for a node" do
      state = Engine.init(%{}, 1)
      socket = build_socket(%{debug_state: state})

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_toggle_breakpoint(%{"node_id" => "5"}, socket)

      assert MapSet.member?(result.assigns.debug_state.breakpoints, 5)
    end

    test "removes existing breakpoint" do
      state = Engine.init(%{}, 1) |> Engine.toggle_breakpoint(5)
      socket = build_socket(%{debug_state: state})

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_toggle_breakpoint(%{"node_id" => "5"}, socket)

      refute MapSet.member?(result.assigns.debug_state.breakpoints, 5)
    end

    test "ignores invalid node id string" do
      state = Engine.init(%{}, 1)
      socket = build_socket(%{debug_state: state})

      {:noreply, result} =
        DebugSessionHandlers.handle_debug_toggle_breakpoint(%{"node_id" => "abc"}, socket)

      assert result.assigns.debug_state.breakpoints == state.breakpoints
    end
  end
end
