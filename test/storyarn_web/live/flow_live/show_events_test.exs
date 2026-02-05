defmodule StoryarnWeb.FlowLive.ShowEventsTest do
  @moduledoc """
  Tests that events route correctly through the delegation chain in show.ex.
  Verifies structural correctness of the handler extraction refactoring.
  """

  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  describe "handler module exports" do
    test "NodeEventHandlers exports all expected functions" do
      module = StoryarnWeb.FlowLive.Handlers.NodeEventHandlers
      Code.ensure_loaded!(module)

      assert function_exported?(module, :handle_add_node, 2)
      assert function_exported?(module, :handle_node_selected, 2)
      assert function_exported?(module, :handle_node_double_clicked, 2)
      assert function_exported?(module, :handle_node_moved, 2)
      assert function_exported?(module, :handle_delete_node, 2)
      assert function_exported?(module, :handle_duplicate_node, 2)
      assert function_exported?(module, :handle_update_node_data, 2)
      assert function_exported?(module, :handle_update_node_text, 2)
      assert function_exported?(module, :handle_update_node_field, 2)
      assert function_exported?(module, :handle_generate_technical_id, 1)
      assert function_exported?(module, :handle_save_shortcut, 2)
      assert function_exported?(module, :handle_start_preview, 2)
    end

    test "ResponseEventHandlers exports all expected functions" do
      module = StoryarnWeb.FlowLive.Handlers.ResponseEventHandlers
      Code.ensure_loaded!(module)

      assert function_exported?(module, :handle_add_response, 2)
      assert function_exported?(module, :handle_remove_response, 2)
      assert function_exported?(module, :handle_update_response_text, 2)
      assert function_exported?(module, :handle_update_response_condition, 2)
      assert function_exported?(module, :handle_update_response_instruction, 2)
    end

    test "ConditionEventHandlers exports all expected functions" do
      module = StoryarnWeb.FlowLive.Handlers.ConditionEventHandlers
      Code.ensure_loaded!(module)

      assert function_exported?(module, :handle_update_condition_builder, 2)
      assert function_exported?(module, :handle_update_response_condition_builder, 2)
      assert function_exported?(module, :handle_toggle_switch_mode, 1)
    end

    test "CollaborationEventHandlers exports all expected functions" do
      module = StoryarnWeb.FlowLive.Handlers.CollaborationEventHandlers
      Code.ensure_loaded!(module)

      assert function_exported?(module, :handle_cursor_moved, 2)
      assert function_exported?(module, :handle_presence_diff, 1)
      assert function_exported?(module, :handle_lock_change, 3)
      assert function_exported?(module, :handle_remote_change, 3)
      assert function_exported?(module, :handle_clear_collab_toast, 1)
    end

    test "EditorInfoHandlers exports all expected functions" do
      module = StoryarnWeb.FlowLive.Handlers.EditorInfoHandlers
      Code.ensure_loaded!(module)

      assert function_exported?(module, :handle_reset_save_status, 1)
      assert function_exported?(module, :handle_node_updated, 2)
      assert function_exported?(module, :handle_close_preview, 1)
      assert function_exported?(module, :handle_mention_suggestions, 3)
    end
  end

  describe "node events through LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      %{project: project, flow: flow}
    end

    test "add_node creates a dialogue node", %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "add_node", %{"type" => "dialogue"})

      updated_flow = Storyarn.Flows.get_flow!(project.id, flow.id)
      dialogue_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "dialogue"))
      assert length(dialogue_nodes) == 1
    end

    test "delete_node removes a node", %{conn: conn, project: project, flow: flow} do
      node = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "", "color" => "purple"}})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "delete_node", %{"id" => node.id})

      updated_flow = Storyarn.Flows.get_flow!(project.id, flow.id)
      hub_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "hub"))
      assert hub_nodes == []
    end

    test "duplicate_node creates a copy", %{conn: conn, project: project, flow: flow} do
      node = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "", "color" => "purple"}})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "duplicate_node", %{"id" => node.id})

      updated_flow = Storyarn.Flows.get_flow!(project.id, flow.id)
      hub_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "hub"))
      assert length(hub_nodes) == 2
    end
  end

  describe "connection events through LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      node1 = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "", "color" => "purple"}})
      node2 = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "", "color" => "blue"}})
      %{project: project, flow: flow, node1: node1, node2: node2}
    end

    test "connection_created creates a connection",
         %{conn: conn, project: project, flow: flow, node1: node1, node2: node2} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "connection_created", %{
        "source_node_id" => node1.id,
        "source_pin" => "output",
        "target_node_id" => node2.id,
        "target_pin" => "input"
      })

      updated_flow = Storyarn.Flows.get_flow!(project.id, flow.id)
      assert length(updated_flow.connections) == 1
    end

    test "connection_deleted removes a connection",
         %{conn: conn, project: project, flow: flow, node1: node1, node2: node2} do
      {:ok, _conn} =
        Storyarn.Flows.create_connection_with_attrs(flow, %{
          source_node_id: node1.id,
          target_node_id: node2.id,
          source_pin: "output",
          target_pin: "input"
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "connection_deleted", %{
        "source_node_id" => node1.id,
        "target_node_id" => node2.id
      })

      updated_flow = Storyarn.Flows.get_flow!(project.id, flow.id)
      assert updated_flow.connections == []
    end
  end
end
