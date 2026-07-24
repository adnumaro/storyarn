defmodule Storyarn.Flows.StructuralAnalysisCharacterizationTest do
  @moduledoc """
  Characterization guard for the structural flags emitted by
  `Flows.serialize_for_canvas/2`.

  Written BEFORE moving the graph semantics into the StructuralAnalysis
  engine: these assertions freeze the editor-observable behavior that the
  refactor must preserve bit for bit.
  """
  use Storyarn.DataCase

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode

  # Drift states (multiple entries, stale pins, missing entry) cannot be
  # produced through the CRUD API — its guards forbid them — but they exist in
  # the wild (imports, legacy data, cross-flow pin drift), so the serializer
  # contract must handle them. Set them up at the Repo level.
  defp force_node!(flow, attrs) do
    %FlowNode{flow_id: flow.id}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end

  defp force_data!(node, data) do
    node |> Ecto.Changeset.change(data: data) |> Repo.update!()
  end

  defp soft_delete!(node) do
    node
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
    |> Repo.update!()
  end

  defp serialize(project, flow) do
    project.id |> Flows.get_flow!(flow.id) |> Flows.serialize_for_canvas()
  end

  defp node_payload(serialized, node_id) do
    Enum.find(serialized.nodes, &(&1.id == node_id))
  end

  defp entry_node(flow) do
    flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
  end

  defp exit_node(flow) do
    flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "exit"))
  end

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    %{project: project, flow: flow}
  end

  describe "clean linear graph" do
    test "entry → dialogue → exit carries no structural flags", %{project: project, flow: flow} do
      entry = entry_node(flow)
      exit_n = exit_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hi"}})

      connection_fixture(flow, entry, dialogue)
      connection_fixture(flow, dialogue, exit_n)

      serialized = serialize(project, flow)

      for node <- serialized.nodes do
        refute node.data["unreachable"], "#{node.type} unexpectedly unreachable"
        refute node.data["dead_end"], "#{node.type} unexpectedly dead_end"
        refute Map.has_key?(node.data, "missing_output_pins")
        refute Map.has_key?(node.data, "invalid_output_pins")
        refute Map.has_key?(node.data, "invalid_input_pins")
      end
    end
  end

  describe "reachability" do
    test "node with edges but detached from entry is unreachable", %{
      project: project,
      flow: flow
    } do
      entry = entry_node(flow)
      exit_n = exit_node(flow)
      connected = node_fixture(flow, %{type: "dialogue"})
      island_a = node_fixture(flow, %{type: "dialogue"})
      island_b = node_fixture(flow, %{type: "dialogue"})

      connection_fixture(flow, entry, connected)
      connection_fixture(flow, connected, exit_n)
      connection_fixture(flow, island_a, island_b)

      serialized = serialize(project, flow)

      assert node_payload(serialized, island_a.id).data["unreachable"] == true
      assert node_payload(serialized, island_b.id).data["unreachable"] == true
      refute node_payload(serialized, connected.id).data["unreachable"]
    end

    test "isolated node is both unreachable and dead_end", %{project: project, flow: flow} do
      isolated = node_fixture(flow, %{type: "dialogue"})

      serialized = serialize(project, flow)
      payload = node_payload(serialized, isolated.id)

      assert payload.data["unreachable"] == true
      assert payload.data["dead_end"] == true
    end

    test "jump reaches its hub through the virtual edge", %{project: project, flow: flow} do
      entry = entry_node(flow)
      exit_n = exit_node(flow)

      hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "camp", "color" => "violet"}})
      jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "camp"}})

      connection_fixture(flow, entry, jump)
      connection_fixture(flow, hub, exit_n)

      serialized = serialize(project, flow)

      refute node_payload(serialized, hub.id).data["unreachable"]
      refute node_payload(serialized, jump.id).data["unreachable"]
    end

    test "cycles are traversed safely and count as reachable", %{project: project, flow: flow} do
      entry = entry_node(flow)
      a = node_fixture(flow, %{type: "dialogue"})
      b = node_fixture(flow, %{type: "dialogue"})

      connection_fixture(flow, entry, a)
      connection_fixture(flow, a, b)
      connection_fixture(flow, b, a)

      serialized = serialize(project, flow)

      refute node_payload(serialized, a.id).data["unreachable"]
      refute node_payload(serialized, b.id).data["unreachable"]
    end

    test "without any entry no node is flagged unreachable", %{project: project, flow: flow} do
      entry = entry_node(flow)
      lonely = node_fixture(flow, %{type: "dialogue"})
      soft_delete!(entry)

      serialized = serialize(project, flow)

      refute node_payload(serialized, lonely.id).data["unreachable"]
    end

    test "multiple entries all seed the traversal", %{project: project, flow: flow} do
      entry_one = entry_node(flow)
      entry_two = force_node!(flow, %{type: "entry", data: %{}, position_x: 0.0, position_y: 0.0})
      from_one = node_fixture(flow, %{type: "dialogue"})
      from_two = node_fixture(flow, %{type: "dialogue"})

      connection_fixture(flow, entry_one, from_one)
      connection_fixture(flow, entry_two, from_two)

      serialized = serialize(project, flow)

      refute node_payload(serialized, from_one.id).data["unreachable"]
      refute node_payload(serialized, from_two.id).data["unreachable"]
    end
  end

  describe "dead ends and output pins" do
    test "reachable non-terminal node without outgoing connection is dead_end", %{
      project: project,
      flow: flow
    } do
      entry = entry_node(flow)
      stuck = node_fixture(flow, %{type: "dialogue"})
      connection_fixture(flow, entry, stuck)

      serialized = serialize(project, flow)

      assert node_payload(serialized, stuck.id).data["dead_end"] == true
    end

    test "exit, jump and annotation are never dead_end", %{project: project, flow: flow} do
      entry = entry_node(flow)
      exit_n = exit_node(flow)
      _hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "camp", "color" => "violet"}})
      jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "camp"}})
      annotation = node_fixture(flow, %{type: "annotation", data: %{"text" => "note"}})

      connection_fixture(flow, entry, exit_n)

      serialized = serialize(project, flow)

      refute node_payload(serialized, exit_n.id).data["dead_end"]
      refute node_payload(serialized, jump.id).data["dead_end"]
      refute node_payload(serialized, annotation.id).data["dead_end"]
    end

    test "dialogue with responses reports unconnected response pins", %{
      project: project,
      flow: flow
    } do
      entry = entry_node(flow)
      exit_n = exit_node(flow)

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose",
            "responses" => [
              %{"id" => "r1", "text" => "Yes"},
              %{"id" => "r2", "text" => "No"}
            ]
          }
        })

      connection_fixture(flow, entry, dialogue)
      connection_fixture(flow, dialogue, exit_n, %{source_pin: "r1"})

      serialized = serialize(project, flow)
      payload = node_payload(serialized, dialogue.id)

      assert payload.data["missing_output_pins"] == ["r2"]
      refute payload.data["dead_end"]
    end
  end

  describe "invalid pins" do
    test "connection on a pin that no longer exists is flagged and excluded from the health graph",
         %{project: project, flow: flow} do
      entry = entry_node(flow)
      exit_n = exit_node(flow)

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Choose", "responses" => [%{"id" => "r1", "text" => "Yes"}]}
        })

      connection_fixture(flow, entry, dialogue)
      connection_fixture(flow, dialogue, exit_n, %{source_pin: "r1"})

      force_data!(dialogue, %{"text" => "Choose", "responses" => []})

      serialized = serialize(project, flow)
      dialogue_payload = node_payload(serialized, dialogue.id)
      exit_payload = node_payload(serialized, exit_n.id)

      assert dialogue_payload.data["invalid_output_pins"] == ["r1"]
      # The stale connection no longer feeds reachability: exit is orphaned.
      assert exit_payload.data["unreachable"] == true
      # The default output pin is now unconnected.
      assert dialogue_payload.data["missing_output_pins"] == ["output"]
    end
  end
end
