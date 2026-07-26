defmodule StoryarnWeb.FlowLive.Helpers.SocketHelpersTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.SocketHelpers

  # ── reload_flow_data/1 ────────────────────────────────────────────

  describe "reload_flow_data/1" do
    setup do
      project = project_fixture(user_fixture())
      flow = flow_fixture(project)

      socket = %Socket{
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

      health = result.assigns.flow_health
      item = Enum.find(health.warningItems, &(&1.entityId == dialogue.id))
      codes = Enum.map(item.reasons, & &1.code)

      # Reasons travel as CODES for Vue to translate; the server no longer renders
      # the sentence. Editorial and structural now share one surface, so the
      # isolated-node finding belongs here too.
      assert "missing_dialogue_text" in codes
      assert "missing_dialogue_speaker" in codes
      assert "isolated_node" in codes
      assert item.entityType == "dialogue"
      refute Enum.any?(health.errorItems, &(&1.entityId == dialogue.id))
      refute Enum.any?(health.infoItems, &(&1.entityId == dialogue.id))
    end
  end

  # ── project-wide graph notification ───────────────────────────────

  describe "reload_flow_data/2 project notification" do
    setup do
      project = project_fixture(user_fixture())
      flow = Flows.get_flow!(project.id, flow_fixture(project).id)

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          project: project,
          flow: flow,
          flow_data: nil,
          flow_hubs: []
        }
      }

      Collaboration.subscribe_flow_graph(project.id)

      %{project: project, flow: flow, socket: socket}
    end

    # The broadcast excludes its sender, so the reload has to run off the test
    # process for the subscription to see it.
    defp reload_from_other_process(socket, opts \\ []) do
      test_pid = self()

      Task.await(
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Repo, test_pid, self())
          SocketHelpers.reload_flow_data(socket, opts)
        end)
      )
    end

    test "content-only mutations do not stale other flows' snapshots", %{
      flow: flow,
      socket: socket
    } do
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})

      reload_from_other_process(socket)

      refute_receive {:flow_graph_changed, _flow_id}, 100
    end

    test "an exit-node change notifies the project", %{flow: flow, socket: socket} do
      node_fixture(flow, %{type: "exit", data: %{"label" => "Second ending"}})

      reload_from_other_process(socket)

      flow_id = flow.id
      assert_receive {:flow_graph_changed, ^flow_id}, 500
    end

    test "notify_project: false never notifies", %{flow: flow, socket: socket} do
      node_fixture(flow, %{type: "exit", data: %{"label" => "Second ending"}})

      reload_from_other_process(socket, notify_project: false)

      refute_receive {:flow_graph_changed, _flow_id}, 100
    end
  end
end
