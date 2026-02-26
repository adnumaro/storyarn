defmodule StoryarnWeb.FlowLive.Helpers.SocketHelpersTest do
  use Storyarn.DataCase, async: true

  alias StoryarnWeb.FlowLive.Helpers.SocketHelpers

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.FlowsFixtures

  # ── schedule_save_status_reset/0 ──────────────────────────────────

  describe "schedule_save_status_reset/0" do
    test "sends :reset_save_status message after delay" do
      SocketHelpers.schedule_save_status_reset()

      assert_receive :reset_save_status, 3000
    end

    test "does not deliver message immediately" do
      SocketHelpers.schedule_save_status_reset()

      refute_receive :reset_save_status, 50
    end
  end

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
  end
end
