defmodule StoryarnWeb.FlowLive.Helpers.SocketHelpersTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias StoryarnWeb.FlowLive.Helpers.SocketHelpers

  # ── reload_flow_data/1 ────────────────────────────────────────────

  describe "reload_flow_data/1" do
    setup do
      project = project_fixture(user_fixture())
      flow = flow_fixture(project)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          project: project,
          flow: flow,
          flow_data: nil,
          flow_hubs: []
        }
      }

      %{project: project, flow: flow, socket: socket}
    end

    test "reloads flow from database", %{socket: socket, flow: flow} do
      result = SocketHelpers.reload_flow_data(socket)

      assert result.assigns.flow.id == flow.id
      assert result.assigns.flow.name == flow.name
    end

    test "assigns flow_data with serialized canvas format", %{socket: socket} do
      result = SocketHelpers.reload_flow_data(socket)

      flow_data = result.assigns.flow_data
      assert is_map(flow_data)
      assert Map.has_key?(flow_data, :id)
      assert Map.has_key?(flow_data, :nodes)
      assert Map.has_key?(flow_data, :connections)
    end

    test "assigns flow_hubs as a list", %{socket: socket} do
      result = SocketHelpers.reload_flow_data(socket)

      assert is_list(result.assigns.flow_hubs)
    end

    test "includes hub nodes in flow_hubs", %{flow: flow, socket: socket} do
      hub_id = "hub_#{System.unique_integer([:positive])}"

      node_fixture(flow, %{
        type: "hub",
        data: %{"hub_id" => hub_id, "label" => "Checkpoint", "color" => "#8b5cf6"}
      })

      result = SocketHelpers.reload_flow_data(socket)

      assert length(result.assigns.flow_hubs) == 1
      assert hd(result.assigns.flow_hubs).hub_id == hub_id
    end

    test "reflects newly added nodes in flow_data", %{flow: flow, socket: socket} do
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => "Hello", "speaker_sheet_id" => nil}
      })

      result = SocketHelpers.reload_flow_data(socket)

      # Entry node (auto-created) + our dialogue node
      assert length(result.assigns.flow_data.nodes) >= 2
    end

    test "uses the localization contract for the editor word count", %{flow: flow, socket: socket} do
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "Dialogue words",
          "stage_directions" => "Walks away",
          "menu_text" => "Choose wisely",
          "responses" => [%{"id" => "response-1", "text" => "Response words"}]
        }
      })

      node_fixture(flow, %{type: "exit", data: %{"label" => "Leave now"}})

      result = SocketHelpers.reload_flow_data(socket)

      assert result.assigns.flow_word_count == 10
    end

    test "reports multiple health reasons for dialogue nodes", %{flow: flow, socket: socket} do
      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "<p><br></p>", "responses" => []}
        })

      result = SocketHelpers.reload_flow_data(socket)

      warning_node = Enum.find(result.assigns.flow_warning_nodes, &(&1.id == dialogue.id))

      assert "Missing dialogue text" in warning_node.reasons
      assert "Missing dialogue speaker" in warning_node.reasons
      assert "Not reachable from any entry node" in warning_node.reasons
      assert "No outgoing connection" in warning_node.reasons
      refute Enum.any?(result.assigns.flow_error_nodes, &(&1.id == dialogue.id))
      refute Enum.any?(result.assigns.flow_info_nodes, &(&1.id == dialogue.id))
    end
  end
end
