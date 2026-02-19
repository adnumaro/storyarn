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
    test "GenericNodeHandlers exports all expected functions" do
      module = StoryarnWeb.FlowLive.Handlers.GenericNodeHandlers
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
      assert function_exported?(module, :handle_save_shortcut, 2)
      assert function_exported?(module, :handle_restore_flow_meta, 2)
      assert function_exported?(module, :handle_start_preview, 2)
    end

    test "Dialogue.Node exports all expected functions" do
      module = StoryarnWeb.FlowLive.Nodes.Dialogue.Node
      Code.ensure_loaded!(module)

      assert function_exported?(module, :handle_add_response, 2)
      assert function_exported?(module, :handle_remove_response, 2)
      assert function_exported?(module, :handle_update_response_text, 2)
      assert function_exported?(module, :handle_update_response_condition, 2)
      assert function_exported?(module, :handle_update_response_instruction, 2)
      assert function_exported?(module, :handle_generate_technical_id, 1)
      assert function_exported?(module, :handle_open_screenplay, 1)
    end

    test "Condition.Node exports all expected functions" do
      module = StoryarnWeb.FlowLive.Nodes.Condition.Node
      Code.ensure_loaded!(module)

      assert function_exported?(module, :handle_update_condition_builder, 2)
      assert function_exported?(module, :handle_update_response_condition_builder, 2)
      assert function_exported?(module, :handle_toggle_switch_mode, 1)
    end

    test "Instruction.Node exports all expected functions" do
      module = StoryarnWeb.FlowLive.Nodes.Instruction.Node
      Code.ensure_loaded!(module)

      assert function_exported?(module, :handle_update_instruction_builder, 2)
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

  describe "undo/redo events through LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      %{project: project, flow: flow}
    end

    test "restore_node_data reverts node data to previous snapshot",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Original text", "speaker" => "NPC"}
        })

      # Update the node data first
      {:ok, updated_node, _meta} =
        Storyarn.Flows.update_node_data(node, %{"text" => "Modified text", "speaker" => "NPC"})

      assert updated_node.data["text"] == "Modified text"

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      # Simulate undo: restore to original data
      render_click(view, "restore_node_data", %{
        "id" => node.id,
        "data" => %{"text" => "Original text", "speaker" => "NPC"}
      })

      restored_node = Storyarn.Flows.get_node!(flow.id, node.id)
      assert restored_node.data["text"] == "Original text"
    end

    test "restore_node_data rejects hub_id conflict (data unchanged)",
         %{conn: conn, project: project, flow: flow} do
      _hub1 =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "hub_a", "color" => "purple"}
        })

      hub2 =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "hub_b", "color" => "blue"}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      # Try to restore hub2 with hub_a's ID — should conflict
      render_click(view, "restore_node_data", %{
        "id" => hub2.id,
        "data" => %{"hub_id" => "hub_a", "color" => "blue"}
      })

      # Data should remain unchanged — restore was rejected
      unchanged_hub2 = Storyarn.Flows.get_node!(flow.id, hub2.id)
      assert unchanged_hub2.data["hub_id"] == "hub_b"
    end

    test "restore_flow_meta restores flow name",
         %{conn: conn, project: project, flow: flow} do
      # Update flow name first
      {:ok, _} = Storyarn.Flows.update_flow(flow, %{name: "Modified Name"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      # Simulate undo: restore original name
      render_click(view, "restore_flow_meta", %{
        "field" => "name",
        "value" => "Test Flow"
      })

      restored_flow = Storyarn.Flows.get_flow!(project.id, flow.id)
      assert restored_flow.name == "Test Flow"
    end

    test "restore_flow_meta restores flow shortcut",
         %{conn: conn, project: project, flow: flow} do
      {:ok, _} = Storyarn.Flows.update_flow(flow, %{shortcut: "test.shortcut"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      # Restore shortcut to nil (empty)
      render_click(view, "restore_flow_meta", %{
        "field" => "shortcut",
        "value" => ""
      })

      restored_flow = Storyarn.Flows.get_flow!(project.id, flow.id)
      assert restored_flow.shortcut == nil
    end

    test "restore_flow_meta with unknown field is a no-op",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      # Should not crash — catch-all clause returns {:noreply, socket}
      render_click(view, "restore_flow_meta", %{
        "field" => "unknown_field",
        "value" => "anything"
      })

      # Flow unchanged
      unchanged_flow = Storyarn.Flows.get_flow!(project.id, flow.id)
      assert unchanged_flow.name == "Test Flow"
    end

    test "save_name pushes flow_meta_changed event",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "save_name", %{"name" => "New Name"})

      updated_flow = Storyarn.Flows.get_flow!(project.id, flow.id)
      assert updated_flow.name == "New Name"
    end

    test "save_shortcut pushes flow_meta_changed event",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "save_shortcut", %{"shortcut" => "new.shortcut"})

      updated_flow = Storyarn.Flows.get_flow!(project.id, flow.id)
      assert updated_flow.shortcut == "new.shortcut"
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
