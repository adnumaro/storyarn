defmodule StoryarnWeb.FlowLive.Helpers.ConnectionHelpersTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.ConnectionHelpers

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
      assert result.assigns.flow_data
      connections = Flows.list_connections(result.assigns.flow.id)

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

      assert result.assigns.flash["error"]
    end
  end

  # =============================================================================
  # delete_connection/2
  # =============================================================================

  describe "delete_connection/2" do
    setup :setup_flow_with_nodes

    test "deletes exactly one persisted connection between parallel node pins", %{
      socket: socket,
      flow: flow,
      dialogue_node: target
    } do
      source = node_fixture(flow, %{type: "condition"})

      first =
        connection_fixture(flow, source, target, %{
          source_pin: "true",
          target_pin: "input"
        })

      second =
        connection_fixture(flow, source, target, %{
          source_pin: "false",
          target_pin: "input"
        })

      params = %{
        "id" => first.id,
        "source_node_id" => source.id,
        "source_pin" => "true",
        "target_node_id" => target.id,
        "target_pin" => "input"
      }

      {:noreply, result} = ConnectionHelpers.delete_connection(socket, params)

      assert result.assigns.save_status == :saved
      assert Flows.get_connection(flow.id, first.id) == nil
      second_id = second.id

      assert %{
               id: ^second_id,
               source_pin: "false",
               target_pin: "input"
             } = Flows.get_connection(flow.id, second.id)
    end

    test "uses the exact pin pair before the persisted id reaches the canvas", %{
      socket: socket,
      flow: flow,
      dialogue_node: target
    } do
      source = node_fixture(flow, %{type: "condition"})

      first =
        connection_fixture(flow, source, target, %{
          source_pin: "true",
          target_pin: "input"
        })

      second =
        connection_fixture(flow, source, target, %{
          source_pin: "false",
          target_pin: "input"
        })

      params = %{
        "source_node_id" => source.id,
        "source_pin" => "false",
        "target_node_id" => target.id,
        "target_pin" => "input"
      }

      {:noreply, result} = ConnectionHelpers.delete_connection(socket, params)

      assert result.assigns.save_status == :saved
      assert Flows.get_connection(flow.id, first.id)
      assert Flows.get_connection(flow.id, second.id) == nil
    end

    test "a forged id never falls back to deleting the supplied local pins", %{
      socket: socket,
      flow: flow,
      dialogue_node: target,
      project: project
    } do
      source = node_fixture(flow, %{type: "condition"})

      local =
        connection_fixture(flow, source, target, %{
          source_pin: "true",
          target_pin: "input"
        })

      foreign_flow = flow_fixture(project)
      foreign_source = node_fixture(foreign_flow, %{type: "condition"})
      foreign_target = node_fixture(foreign_flow, %{type: "dialogue"})

      foreign =
        connection_fixture(foreign_flow, foreign_source, foreign_target, %{
          source_pin: "true",
          target_pin: "input"
        })

      params = %{
        "id" => foreign.id,
        "source_node_id" => source.id,
        "source_pin" => "true",
        "target_node_id" => target.id,
        "target_pin" => "input"
      }

      {:noreply, result} = ConnectionHelpers.delete_connection(socket, params)

      assert result.assigns.save_status == :idle
      assert result.assigns.flash["error"]
      assert Flows.get_connection(flow.id, local.id)
      assert Flows.get_connection(foreign_flow.id, foreign.id)
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
      connections = Flows.list_connections(result.assigns.flow.id)

      refute Enum.any?(connections, fn c ->
               c.source_node_id == entry.id && c.target_node_id == dialogue.id
             end)

      warning_node = Enum.find(result.assigns.flow_warning_nodes, &(&1.id == entry.id))

      assert "No outgoing connection" in warning_node.reasons
    end

    test "resyncs and reports a non-existent connection without marking a save", %{
      socket: socket,
      dialogue_node: dialogue,
      exit_node: exit_node
    } do
      connections_before = Flows.list_connections(socket.assigns.flow.id)

      # These nodes aren't connected
      {:noreply, result} =
        ConnectionHelpers.delete_connection_by_nodes(socket, dialogue.id, exit_node.id)

      connections_after = Flows.list_connections(result.assigns.flow.id)
      assert length(connections_after) == length(connections_before)
      assert result.assigns.save_status == :idle
      assert result.assigns.flash["error"]
      assert result.assigns[:auto_snapshot_ref] == nil
      assert length(result.assigns.flow_data.connections) == length(connections_before)
    end

    test "a rejected delete does not snapshot or broadcast success and restores authoritative canvas data",
         %{socket: socket, flow: flow} do
      parent = self()

      listener =
        spawn(fn ->
          :ok = Collaboration.subscribe_changes({:flow, flow.id})
          send(parent, :connection_listener_ready)

          receive do
            message -> send(parent, {:connection_listener_message, message})
          after
            250 -> send(parent, :connection_listener_idle)
          end
        end)

      assert_receive :connection_listener_ready

      stale_socket = %{
        socket
        | assigns: Map.put(socket.assigns, :flow_data, %{id: flow.id, nodes: [], connections: []})
      }

      {:noreply, result} =
        ConnectionHelpers.delete_connection_by_nodes(stale_socket, "not-an-id", "also-invalid")

      assert result.assigns.save_status == :idle
      assert result.assigns[:auto_snapshot_ref] == nil
      assert result.assigns.flash["error"]
      assert length(result.assigns.flow_data.connections) == 1

      refute_receive {:connection_listener_message, {:remote_change, :connection_deleted, _payload}},
                     300

      if Process.alive?(listener), do: Process.exit(listener, :kill)
    end

    test "a rejected delete after the flow is removed clears stale canvas state", %{
      socket: socket,
      flow: flow,
      entry_node: entry,
      dialogue_node: dialogue
    } do
      assert {:ok, _deleted_flow} = Flows.delete_flow(flow)

      {:noreply, result} =
        ConnectionHelpers.delete_connection_by_nodes(socket, entry.id, dialogue.id)

      assert result.assigns.save_status == :idle
      assert result.assigns[:auto_snapshot_ref] == nil
      assert result.assigns.flash["error"]

      assert result.assigns.flow_data == %{
               id: flow.id,
               name: flow.name,
               nodes: [],
               connections: []
             }

      assert result.assigns.flow_hubs == []
    end

    test "a transient database error during rejected-delete recovery preserves the socket", %{
      socket: socket
    } do
      flow_data = socket.assigns.flow_data

      result =
        ConnectionHelpers.resync_authoritative_flow(socket, fn _socket ->
          raise DBConnection.ConnectionError, "database unavailable"
        end)

      assert result.assigns.flow_data == flow_data
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
    flow_with_nodes = Flows.get_flow!(project.id, flow.id)
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

    flow = Flows.get_flow!(project.id, flow.id)
    flow_data = Flows.serialize_for_canvas(flow)

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
    flow = Flows.get_flow!(result.project.id, result.flow.id)
    flow_data = Flows.serialize_for_canvas(flow)

    socket = %{
      result.socket
      | assigns: %{result.socket.assigns | flow: flow, flow_data: flow_data}
    }

    result
    |> Map.put(:socket, socket)
    |> Map.put(:flow, flow)
  end
end
