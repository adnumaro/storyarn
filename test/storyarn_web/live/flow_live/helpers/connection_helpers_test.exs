defmodule StoryarnWeb.FlowLive.Helpers.ConnectionHelpersTest do
  use Storyarn.DataCase, async: true

  alias StoryarnWeb.FlowLive.Helpers.ConnectionHelpers

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  # =============================================================================
  # create_connection/2
  # =============================================================================

  describe "create_connection/2" do
    setup :setup_flow_with_nodes

    test "creates connection between two nodes", %{
      socket: socket,
      entry_node: entry,
      dialogue_node: dialogue
    } do
      params = %{
        "source_node_id" => entry.id,
        "source_pin" => "output",
        "target_node_id" => dialogue.id,
        "target_pin" => "input"
      }

      {:noreply, result} = ConnectionHelpers.create_connection(socket, params)

      assert result.assigns.save_status == :saved
      # Flow data should be reloaded with the new connection
      assert result.assigns.flow_data != nil
      connections = Storyarn.Flows.list_connections(result.assigns.flow.id)

      assert Enum.any?(connections, fn c ->
               c.source_node_id == entry.id && c.target_node_id == dialogue.id
             end)
    end

    test "returns error flash for invalid connection", %{socket: socket, entry_node: entry} do
      # Try to connect a node to itself
      params = %{
        "source_node_id" => entry.id,
        "source_pin" => "output",
        "target_node_id" => entry.id,
        "target_pin" => "input"
      }

      {:noreply, result} = ConnectionHelpers.create_connection(socket, params)

      assert result.assigns.flash["error"] != nil
    end
  end

  # =============================================================================
  # delete_connection_by_nodes/3
  # =============================================================================

  describe "delete_connection_by_nodes/3" do
    setup :setup_flow_with_connection

    test "deletes connection between nodes", %{
      socket: socket,
      entry_node: entry,
      dialogue_node: dialogue
    } do
      {:noreply, result} =
        ConnectionHelpers.delete_connection_by_nodes(socket, entry.id, dialogue.id)

      assert result.assigns.save_status == :saved
      # Connection should be deleted
      connections = Storyarn.Flows.list_connections(result.assigns.flow.id)

      refute Enum.any?(connections, fn c ->
               c.source_node_id == entry.id && c.target_node_id == dialogue.id
             end)
    end

    test "handles non-existent connection gracefully", %{
      socket: socket,
      dialogue_node: dialogue,
      exit_node: exit_node
    } do
      connections_before = Storyarn.Flows.list_connections(socket.assigns.flow.id)

      # These nodes aren't connected
      {:noreply, result} =
        ConnectionHelpers.delete_connection_by_nodes(socket, dialogue.id, exit_node.id)

      connections_after = Storyarn.Flows.list_connections(result.assigns.flow.id)
      assert length(connections_after) == length(connections_before)
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp setup_flow_with_nodes(_context) do
    user = user_fixture()
    project = project_fixture(user)
    flow = Storyarn.FlowsFixtures.flow_fixture(project)

    # flow_fixture already creates an entry node, so find it
    flow_with_nodes = Storyarn.Flows.get_flow!(project.id, flow.id)
    entry_node = Enum.find(flow_with_nodes.nodes, &(&1.type == "entry"))

    dialogue_node =
      Storyarn.FlowsFixtures.node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => "Hello", "responses" => [], "speaker_sheet_id" => nil},
        position_x: 300.0,
        position_y: 100.0
      })

    exit_node =
      Storyarn.FlowsFixtures.node_fixture(flow, %{
        type: "exit",
        data: %{"label" => "End", "technical_id" => "", "exit_mode" => "terminal"},
        position_x: 500.0,
        position_y: 100.0
      })

    flow = Storyarn.Flows.get_flow!(project.id, flow.id)
    flow_data = Storyarn.Flows.serialize_for_canvas(flow)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        flow: flow,
        project: project,
        flow_data: flow_data,
        flow_hubs: [],
        save_status: :idle,
        current_user_id: user.id,
        current_scope: %{user: user},
        node_locks: %{}
      },
      private: %{lifecycle_events: [], live_temp: %{}}
    }

    %{
      flow: flow,
      socket: socket,
      project: project,
      entry_node: entry_node,
      dialogue_node: dialogue_node,
      exit_node: exit_node
    }
  end

  defp setup_flow_with_connection(context) do
    result = setup_flow_with_nodes(context)

    _connection =
      Storyarn.FlowsFixtures.connection_fixture(
        result.flow,
        result.entry_node,
        result.dialogue_node
      )

    # Reload flow data after connection
    flow = Storyarn.Flows.get_flow!(result.project.id, result.flow.id)
    flow_data = Storyarn.Flows.serialize_for_canvas(flow)

    socket = %{
      result.socket
      | assigns: %{result.socket.assigns | flow: flow, flow_data: flow_data}
    }

    result
    |> Map.put(:socket, socket)
    |> Map.put(:flow, flow)
  end
end
