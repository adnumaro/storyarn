defmodule Storyarn.Flows.DebugSessionTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.DebugSession
  alias Storyarn.Flows.Evaluator.Engine

  test "initializes at the graph entry and fails closed without one" do
    graph = graph([node(1, "entry"), node(2, "exit")], [])

    assert {:ok, %{state: state, graph: ^graph}} = DebugSession.initialize(%{}, graph, 10)
    assert state.start_node_id == 1
    assert state.current_flow_id == 10

    assert {:error, :no_entry_node} =
             DebugSession.initialize(%{}, graph([node(2, "exit")], []), 10)
  end

  test "owns start-node selection, reset and breakpoint parsing" do
    nodes = %{1 => node(1, "entry"), 2 => node(2, "hub")}
    state = Engine.init(%{}, 1)

    assert {:ok, state} = DebugSession.select_start_node(state, nodes, "2")
    assert state.start_node_id == 2
    assert state.current_node_id == 2
    assert {:error, :invalid_node} = DebugSession.select_start_node(state, nodes, "missing")

    assert {:ok, state} = DebugSession.toggle_breakpoint(state, "2")
    assert MapSet.member?(state.breakpoints, 2)
    assert {:error, :invalid_node} = DebugSession.toggle_breakpoint(state, "2x")
  end

  test "coerces variable overrides and records invalid-number warnings" do
    variables = %{
      "hero.health" => variable(100, "number"),
      "hero.tags" => variable([], "multi_select")
    }

    state = Engine.init(variables, 1)

    assert {:ok, state} = DebugSession.set_variable(state, "hero.health", "invalid")
    assert state.variables["hero.health"].value == 0
    assert Enum.any?(state.console, &(&1.level == :warning))

    assert {:ok, state} = DebugSession.set_variable(state, "hero.tags", "fast, strong")
    assert state.variables["hero.tags"].value == ["fast", "strong"]
    assert {:error, :not_found} = DebugSession.set_variable(state, "missing", "value")
  end

  test "stops automatic execution at a breakpoint" do
    nodes = %{1 => node(1, "entry"), 2 => node(2, "hub")}
    connections = [connection(1, "output", 2)]

    state =
      %{}
      |> Engine.init(1)
      |> Engine.toggle_breakpoint(2)

    assert {:continue, state, _graph, false, :stop} =
             DebugSession.auto_step(state, nodes, connections, "Root")

    assert state.current_node_id == 2
    assert Enum.any?(state.console, &String.contains?(&1.message, "breakpoint"))
  end

  test "automatic execution stops or waits from evaluator status without stepping" do
    graph = graph([node(1, "entry")], [])

    finished_state = %{Engine.init(%{}, 1) | status: :finished}

    assert {:continue, ^finished_state, ^graph, false, :stop} =
             DebugSession.auto_step(
               finished_state,
               graph.nodes,
               graph.connections,
               "Root"
             )

    waiting_state = %{Engine.init(%{}, 1) | status: :waiting_input}

    assert {:continue, ^waiting_state, ^graph, false, :wait} =
             DebugSession.auto_step(
               waiting_state,
               graph.nodes,
               graph.connections,
               "Root"
             )
  end

  test "moves subflow entry and caller return through the Flow-owned call stack" do
    parent_nodes = %{
      1 => node(1, "subflow", %{"referenced_flow_id" => 20}),
      2 => node(2, "exit")
    }

    parent_connections = [connection(1, "output", 2)]

    child_graph =
      graph(
        [
          node(100, "entry"),
          node(101, "exit", %{"exit_mode" => "caller_return"})
        ],
        [connection(100, "output", 101)]
      )

    state = Engine.init(%{}, 1)
    state = %{state | current_flow_id: 10}

    assert {:navigate, child_state, ^child_graph, 20} =
             DebugSession.step(
               state,
               parent_nodes,
               parent_connections,
               "Root",
               fn 20 -> child_graph end
             )

    assert child_state.current_node_id == 100
    assert length(child_state.call_stack) == 1

    assert {:continue, child_state, ^child_graph, false} =
             DebugSession.step(
               child_state,
               child_graph.nodes,
               child_graph.connections,
               "Child",
               fn _flow_id -> flunk("no graph load expected") end
             )

    assert child_state.current_node_id == 101

    assert {:navigate, returned_state, returned_graph, 10} =
             DebugSession.step(
               child_state,
               child_graph.nodes,
               child_graph.connections,
               "Child",
               fn _flow_id -> flunk("no graph load expected") end
             )

    assert returned_state.current_node_id == 2
    assert returned_state.call_stack == []
    assert returned_graph.nodes == parent_nodes
    assert returned_graph.connections == parent_connections
  end

  test "reset from a nested session returns the root graph" do
    root_nodes = %{1 => node(1, "entry")}
    root_connections = []

    state = Engine.init(%{}, 100)

    state = %{
      state
      | current_flow_id: 20,
        call_stack: [
          %{
            flow_id: 10,
            flow_name: "Root",
            return_node_id: 1,
            nodes: root_nodes,
            connections: root_connections,
            execution_path: [1]
          }
        ]
    }

    assert {:navigate, reset_state, reset_graph, 10} =
             DebugSession.reset(state, %{100 => node(100, "entry")}, [])

    assert reset_state.current_flow_id == 10
    assert reset_state.call_stack == []
    assert reset_graph == %{nodes: root_nodes, connections: root_connections}
  end

  defp graph(nodes, connections) do
    %{nodes: Map.new(nodes, &{&1.id, &1}), connections: connections}
  end

  defp node(id, type, data \\ %{}) do
    %{
      id: id,
      type: type,
      data: data,
      parent_id: nil,
      sequence_config: nil,
      sequence_visual_layers: [],
      sequence_tracks: []
    }
  end

  defp connection(source_node_id, source_pin, target_node_id) do
    %{
      source_node_id: source_node_id,
      source_pin: source_pin,
      target_node_id: target_node_id,
      target_pin: "input"
    }
  end

  defp variable(value, block_type) do
    %{
      value: value,
      initial_value: value,
      previous_value: value,
      source: :initial,
      block_type: block_type,
      block_id: 1,
      sheet_shortcut: "hero",
      variable_name: "value"
    }
  end
end
