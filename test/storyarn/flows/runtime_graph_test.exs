defmodule Storyarn.Flows.RuntimeGraphTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.RuntimeGraph

  test "builds the persisted evaluator graph behind the Flows facade" do
    project = project_fixture(user_fixture())
    flow = flow_fixture(project)
    hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "middle"}})
    target = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "target"}})
    connection_fixture(flow, hub, target, %{source_pin: "output", target_pin: "input"})

    graph = Flows.load_runtime_graph(flow.id)

    assert graph.nodes[hub.id].data["hub_id"] == "middle"

    assert Enum.any?(graph.connections, fn connection ->
             connection.source_node_id == hub.id and
               connection.target_node_id == target.id and
               connection.source_pin == "output"
           end)

    assert is_integer(Flows.runtime_entry_node_id(graph.nodes))
  end

  test "entry selection and active edge detection are graph semantics" do
    nodes = [
      %{id: 1, type: "dialogue", data: %{}},
      %{id: 2, type: "entry", data: %{}},
      %{id: 3, type: "exit", data: %{}}
    ]

    connections = [
      %{
        source_node_id: 2,
        source_pin: "output",
        target_node_id: 1,
        target_pin: "input"
      }
    ]

    graph = RuntimeGraph.from_records(nodes, connections)

    assert RuntimeGraph.entry_node_id(graph.nodes) == 2

    assert RuntimeGraph.active_connection([2, 1], graph.connections) == %{
             source_node_id: 2,
             source_pin: "output",
             target_node_id: 1
           }

    assert RuntimeGraph.active_connection([2], graph.connections) == nil
  end
end
