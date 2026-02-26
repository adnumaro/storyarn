defmodule StoryarnWeb.FlowLive.Helpers.NodeHelpersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Repo
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  # ===========================================================================
  # Unit tests — normalize_form_params/1
  # ===========================================================================

  describe "normalize_form_params/1" do
    test "converts empty speaker_sheet_id to nil" do
      params = %{"speaker_sheet_id" => "", "text" => "Hello"}
      result = NodeHelpers.normalize_form_params(params)

      assert result["speaker_sheet_id"] == nil
      assert result["text"] == "Hello"
    end

    test "converts empty audio_asset_id to nil" do
      params = %{"audio_asset_id" => "", "text" => "Hello"}
      result = NodeHelpers.normalize_form_params(params)

      assert result["audio_asset_id"] == nil
    end

    test "converts both empty fields to nil" do
      params = %{"speaker_sheet_id" => "", "audio_asset_id" => ""}
      result = NodeHelpers.normalize_form_params(params)

      assert result["speaker_sheet_id"] == nil
      assert result["audio_asset_id"] == nil
    end

    test "preserves non-empty speaker_sheet_id" do
      params = %{"speaker_sheet_id" => "42", "audio_asset_id" => "7"}
      result = NodeHelpers.normalize_form_params(params)

      assert result["speaker_sheet_id"] == "42"
      assert result["audio_asset_id"] == "7"
    end

    test "preserves nil values (does not set to nil again)" do
      params = %{"speaker_sheet_id" => nil, "audio_asset_id" => nil}
      result = NodeHelpers.normalize_form_params(params)

      assert result["speaker_sheet_id"] == nil
      assert result["audio_asset_id"] == nil
    end

    test "handles params without ID fields" do
      params = %{"text" => "Hello world", "menu_text" => "Choose"}
      result = NodeHelpers.normalize_form_params(params)

      assert result == params
    end

    test "handles empty params" do
      assert NodeHelpers.normalize_form_params(%{}) == %{}
    end
  end

  # ===========================================================================
  # Integration tests — node operations through the LiveView
  # ===========================================================================

  describe "add_node via LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      %{project: project, flow: flow}
    end

    test "creates a dialogue node with default data",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "add_node", %{"type" => "dialogue"})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      dialogue_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "dialogue"))

      assert length(dialogue_nodes) == 1
      node = hd(dialogue_nodes)
      assert node.data["text"] == ""
      assert node.data["speaker_sheet_id"] == nil
    end

    test "creates a condition node",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "add_node", %{"type" => "condition"})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      condition_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "condition"))

      assert length(condition_nodes) == 1
      node = hd(condition_nodes)
      assert node.data["switch_mode"] == false
    end

    test "creates an instruction node",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "add_node", %{"type" => "instruction"})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      instruction_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "instruction"))

      assert length(instruction_nodes) == 1
      node = hd(instruction_nodes)
      assert node.data["assignments"] == []
    end

    test "creates a hub node",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "add_node", %{"type" => "hub"})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      hub_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "hub"))

      assert length(hub_nodes) == 1
    end

    test "creates a jump node",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "add_node", %{"type" => "jump"})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      jump_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "jump"))

      assert length(jump_nodes) == 1
      node = hd(jump_nodes)
      assert node.data["target_hub_id"] == ""
    end

    test "creates an exit node",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "add_node", %{"type" => "exit"})

      updated_flow = Flows.get_flow!(project.id, flow.id)

      # Flow starts with one auto-created exit node; adding one more makes two
      exit_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "exit"))
      assert length(exit_nodes) == 2
    end

    test "places node at specified position",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "add_node", %{
        "type" => "hub",
        "position_x" => 400.0,
        "position_y" => 250.0
      })

      updated_flow = Flows.get_flow!(project.id, flow.id)
      hub = Enum.find(updated_flow.nodes, &(&1.type == "hub"))

      assert hub.position_x == 400.0
      assert hub.position_y == 250.0
    end

    test "places node at random position when coordinates not provided",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "add_node", %{"type" => "hub"})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      hub = Enum.find(updated_flow.nodes, &(&1.type == "hub"))

      assert hub.position_x >= 100.0 and hub.position_x <= 300.0
      assert hub.position_y >= 100.0 and hub.position_y <= 300.0
    end

    test "creates a subflow node",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "add_node", %{"type" => "subflow"})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      subflow_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "subflow"))

      assert length(subflow_nodes) == 1
      node = hd(subflow_nodes)
      assert node.data["referenced_flow_id"] == nil
    end

    test "creates a scene node",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "add_node", %{"type" => "scene"})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      scene_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "scene"))

      assert length(scene_nodes) == 1
    end
  end

  describe "delete_node via LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      %{project: project, flow: flow}
    end

    test "soft-deletes a hub node",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{type: "hub", data: %{"hub_id" => "test_hub", "color" => "#8b5cf6"}})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "delete_node", %{"id" => node.id})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      hub_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "hub"))
      assert hub_nodes == []
    end

    test "soft-deletes a dialogue node",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello world", "speaker_sheet_id" => nil}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "delete_node", %{"id" => node.id})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      dialogue_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "dialogue"))
      assert dialogue_nodes == []
    end

    test "soft-deletes a condition node",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "condition",
          data: %{"condition" => %{"logic" => "all", "rules" => []}, "switch_mode" => false}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "delete_node", %{"id" => node.id})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      condition_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "condition"))
      assert condition_nodes == []
    end

    test "refuses to delete the entry node",
         %{conn: conn, project: project, flow: flow} do
      updated_flow = Flows.get_flow!(project.id, flow.id)
      entry_node = Enum.find(updated_flow.nodes, &(&1.type == "entry"))

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      html = render_click(view, "delete_node", %{"id" => entry_node.id})

      assert html =~ "Entry node cannot be deleted"

      # Entry node should still exist
      still_flow = Flows.get_flow!(project.id, flow.id)
      entry_nodes = Enum.filter(still_flow.nodes, &(&1.type == "entry"))
      assert length(entry_nodes) == 1
    end

    test "refuses to delete the last exit node",
         %{conn: conn, project: project, flow: flow} do
      updated_flow = Flows.get_flow!(project.id, flow.id)
      exit_node = Enum.find(updated_flow.nodes, &(&1.type == "exit"))

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      html = render_click(view, "delete_node", %{"id" => exit_node.id})

      assert html =~ "at least one Exit node"

      # Exit node should still exist
      still_flow = Flows.get_flow!(project.id, flow.id)
      exit_nodes = Enum.filter(still_flow.nodes, &(&1.type == "exit"))
      assert length(exit_nodes) == 1
    end

    test "allows deleting an exit node when another exit exists",
         %{conn: conn, project: project, flow: flow} do
      # Add a second exit node
      exit2 =
        node_fixture(flow, %{
          type: "exit",
          data: %{"label" => "Alt Exit", "technical_id" => "", "outcome_tags" => []}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "delete_node", %{"id" => exit2.id})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      exit_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "exit"))
      assert length(exit_nodes) == 1
    end

    test "deleting a hub with jumps orphans the jump target",
         %{conn: conn, project: project, flow: flow} do
      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "my_hub", "label" => "Hub", "color" => "#8b5cf6"}
        })

      _jump =
        node_fixture(flow, %{
          type: "jump",
          data: %{"target_hub_id" => "my_hub"}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "delete_node", %{"id" => hub.id})

      # Hub should be deleted
      updated_flow = Flows.get_flow!(project.id, flow.id)
      hub_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "hub"))
      assert hub_nodes == []

      # Jump node's target_hub_id should be cleared (orphaned)
      jump_node = Enum.find(updated_flow.nodes, &(&1.type == "jump"))
      assert jump_node.data["target_hub_id"] == ""
    end
  end

  describe "duplicate_node via LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      %{project: project, flow: flow}
    end

    test "duplicates a hub node",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "original_hub", "label" => "My Hub", "color" => "#8b5cf6"}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "duplicate_node", %{"id" => node.id})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      hub_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "hub"))
      assert length(hub_nodes) == 2
    end

    test "duplicated node is offset from original",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "hub",
          position_x: 200.0,
          position_y: 300.0,
          data: %{"hub_id" => "", "color" => "#8b5cf6"}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "duplicate_node", %{"id" => node.id})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      hub_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "hub"))
      duplicated = Enum.find(hub_nodes, &(&1.id != node.id))

      assert duplicated.position_x == 250.0
      assert duplicated.position_y == 350.0
    end

    test "duplicates a dialogue node with text data",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Hello world</p>",
            "speaker_sheet_id" => nil,
            "menu_text" => "Choose wisely"
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "duplicate_node", %{"id" => node.id})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      dialogue_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "dialogue"))
      assert length(dialogue_nodes) == 2

      duplicated = Enum.find(dialogue_nodes, &(&1.id != node.id))
      assert duplicated.data["text"] == "<p>Hello world</p>"
      assert duplicated.data["menu_text"] == "Choose wisely"
    end

    test "duplicates a condition node",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" => %{"logic" => "all", "rules" => []},
            "switch_mode" => false
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "duplicate_node", %{"id" => node.id})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      condition_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "condition"))
      assert length(condition_nodes) == 2
    end

    test "duplicates an instruction node",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [%{"variable" => "mc.health", "operator" => "set", "value" => "100"}],
            "description" => "Heal"
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "duplicate_node", %{"id" => node.id})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      instruction_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "instruction"))
      assert length(instruction_nodes) == 2

      duplicated = Enum.find(instruction_nodes, &(&1.id != node.id))
      assert duplicated.data["description"] == "Heal"
    end
  end

  describe "update_node_text via LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      %{project: project, flow: flow}
    end

    test "updates the text field of a dialogue node",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "<p>Original</p>", "speaker_sheet_id" => nil}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      # Trigger async load and select node so selected_node is set
      render_click(view, "load_flow_data", %{})
      render_async(view, 500)
      render_click(view, "node_selected", %{"id" => node.id})

      render_click(view, "update_node_text", %{
        "id" => node.id,
        "content" => "<p>Updated text</p>"
      })

      updated_node = Flows.get_node!(flow.id, node.id)
      assert updated_node.data["text"] == "<p>Updated text</p>"
    end

    test "preserves other data fields when updating text",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Original</p>",
            "speaker_sheet_id" => nil,
            "menu_text" => "My menu text",
            "stage_directions" => "walks in"
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "load_flow_data", %{})
      render_async(view, 500)
      render_click(view, "node_selected", %{"id" => node.id})

      render_click(view, "update_node_text", %{
        "id" => node.id,
        "content" => "<p>New dialogue</p>"
      })

      updated_node = Flows.get_node!(flow.id, node.id)
      assert updated_node.data["text"] == "<p>New dialogue</p>"
      assert updated_node.data["menu_text"] == "My menu text"
      assert updated_node.data["stage_directions"] == "walks in"
    end

    test "can set text to empty string",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "<p>Some text</p>", "speaker_sheet_id" => nil}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "load_flow_data", %{})
      render_async(view, 500)
      render_click(view, "node_selected", %{"id" => node.id})

      render_click(view, "update_node_text", %{
        "id" => node.id,
        "content" => ""
      })

      updated_node = Flows.get_node!(flow.id, node.id)
      assert updated_node.data["text"] == ""
    end
  end

  describe "update_node_data via LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      %{project: project, flow: flow}
    end

    test "updates dialogue node data from form params",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Hello</p>",
            "speaker_sheet_id" => nil,
            "menu_text" => "",
            "stage_directions" => ""
          }
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      # Must load flow data and select node so selected_node assign is set
      render_click(view, "load_flow_data", %{})
      render_async(view, 500)
      render_click(view, "node_selected", %{"id" => node.id})

      render_click(view, "update_node_data", %{
        "node" => %{
          "menu_text" => "Choose this",
          "stage_directions" => "leans forward"
        }
      })

      updated_node = Flows.get_node!(flow.id, node.id)
      assert updated_node.data["menu_text"] == "Choose this"
      assert updated_node.data["stage_directions"] == "leans forward"
      # Existing data should be preserved via Map.merge
      assert updated_node.data["text"] == "<p>Hello</p>"
    end

    test "normalizes empty speaker_sheet_id to nil",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "", "speaker_sheet_id" => nil}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "load_flow_data", %{})
      render_async(view, 500)
      render_click(view, "node_selected", %{"id" => node.id})

      render_click(view, "update_node_data", %{
        "node" => %{"speaker_sheet_id" => ""}
      })

      updated_node = Flows.get_node!(flow.id, node.id)
      assert updated_node.data["speaker_sheet_id"] == nil
    end

    test "normalizes empty audio_asset_id to nil",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "", "audio_asset_id" => nil}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "load_flow_data", %{})
      render_async(view, 500)
      render_click(view, "node_selected", %{"id" => node.id})

      render_click(view, "update_node_data", %{
        "node" => %{"audio_asset_id" => ""}
      })

      updated_node = Flows.get_node!(flow.id, node.id)
      assert updated_node.data["audio_asset_id"] == nil
    end

    test "update_node_data without 'node' key is a no-op",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      # Should not crash — catch-all clause in show.ex handles missing "node" key
      render_click(view, "update_node_data", %{"something" => "else"})
    end

    test "updates hub node data",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "my_hub", "label" => "", "color" => "#8b5cf6"}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "load_flow_data", %{})
      render_async(view, 500)
      render_click(view, "node_selected", %{"id" => node.id})

      render_click(view, "update_node_data", %{
        "node" => %{"label" => "Central Hub"}
      })

      updated_node = Flows.get_node!(flow.id, node.id)
      assert updated_node.data["label"] == "Central Hub"
      assert updated_node.data["hub_id"] == "my_hub"
    end
  end

  describe "restore_node via LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      %{project: project, flow: flow}
    end

    test "restores a soft-deleted node",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "deleted_hub", "label" => "Restored", "color" => "#8b5cf6"}
        })

      # Soft-delete the node through the context
      {:ok, _, _meta} = Flows.delete_node(node)

      # Verify it is gone from the active flow
      flow_before = Flows.get_flow!(project.id, flow.id)
      assert Enum.filter(flow_before.nodes, &(&1.type == "hub")) == []

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "restore_node", %{"id" => node.id})

      # Node should be back
      flow_after = Flows.get_flow!(project.id, flow.id)
      hub_nodes = Enum.filter(flow_after.nodes, &(&1.type == "hub"))
      assert length(hub_nodes) == 1
      assert hd(hub_nodes).id == node.id
      assert hd(hub_nodes).data["hub_id"] == "deleted_hub"
    end

    test "restore_node for an already-active node is a no-op",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "active_hub", "label" => "", "color" => "#8b5cf6"}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      # Should not crash — returns {:ok, :already_active}
      render_click(view, "restore_node", %{"id" => node.id})

      flow_after = Flows.get_flow!(project.id, flow.id)
      hub_nodes = Enum.filter(flow_after.nodes, &(&1.type == "hub"))
      assert length(hub_nodes) == 1
    end

    test "restores a soft-deleted dialogue node with its data intact",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "<p>Important dialogue</p>",
            "speaker_sheet_id" => nil,
            "menu_text" => "Select me"
          }
        })

      {:ok, _, _meta} = Flows.delete_node(node)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "restore_node", %{"id" => node.id})

      flow_after = Flows.get_flow!(project.id, flow.id)
      dialogue_nodes = Enum.filter(flow_after.nodes, &(&1.type == "dialogue"))
      assert length(dialogue_nodes) == 1

      restored = hd(dialogue_nodes)
      assert restored.data["text"] == "<p>Important dialogue</p>"
      assert restored.data["menu_text"] == "Select me"
    end
  end

  describe "restore_node_data via LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      %{project: project, flow: flow}
    end

    test "restores node data to a previous snapshot (undo)",
         %{conn: conn, project: project, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Original", "speaker_sheet_id" => nil}
        })

      # Modify data first
      {:ok, _updated, _meta} =
        Flows.update_node_data(node, %{"text" => "Modified", "speaker_sheet_id" => nil})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "restore_node_data", %{
        "id" => node.id,
        "data" => %{"text" => "Original", "speaker_sheet_id" => nil}
      })

      restored_node = Flows.get_node!(flow.id, node.id)
      assert restored_node.data["text"] == "Original"
    end

    test "rejects restoring hub data that would create duplicate hub_id",
         %{conn: conn, project: project, flow: flow} do
      _hub1 =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "hub_alpha", "label" => "", "color" => "#8b5cf6"}
        })

      hub2 =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "hub_beta", "label" => "", "color" => "#3b82f6"}
        })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      # Try to restore hub2 with hub_alpha's ID — should be rejected
      render_click(view, "restore_node_data", %{
        "id" => hub2.id,
        "data" => %{"hub_id" => "hub_alpha", "label" => "", "color" => "#3b82f6"}
      })

      unchanged = Flows.get_node!(flow.id, hub2.id)
      assert unchanged.data["hub_id"] == "hub_beta"
    end
  end

  describe "authorization for node operations" do
    setup :register_and_log_in_user

    test "viewer cannot add nodes", %{conn: conn, user: user} do
      owner = Storyarn.AccountsFixtures.user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      flow = flow_fixture(project, %{name: "Viewer Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      html = render_click(view, "add_node", %{"type" => "dialogue"})

      # Should show unauthorized flash
      assert html =~ "not authorized" or html =~ "permission"

      # No dialogue node should have been created
      updated_flow = Flows.get_flow!(project.id, flow.id)
      dialogue_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "dialogue"))
      assert dialogue_nodes == []
    end

    test "viewer cannot delete nodes", %{conn: conn, user: user} do
      owner = Storyarn.AccountsFixtures.user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      flow = flow_fixture(project, %{name: "Viewer Flow"})

      node =
        node_fixture(flow, %{type: "hub", data: %{"hub_id" => "test", "color" => "#8b5cf6"}})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "delete_node", %{"id" => node.id})

      # Node should still exist
      updated_flow = Flows.get_flow!(project.id, flow.id)
      hub_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "hub"))
      assert length(hub_nodes) == 1
    end

    test "viewer cannot duplicate nodes", %{conn: conn, user: user} do
      owner = Storyarn.AccountsFixtures.user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      flow = flow_fixture(project, %{name: "Viewer Flow"})

      node =
        node_fixture(flow, %{type: "hub", data: %{"hub_id" => "test", "color" => "#8b5cf6"}})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "duplicate_node", %{"id" => node.id})

      # Should still be just one hub
      updated_flow = Flows.get_flow!(project.id, flow.id)
      hub_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "hub"))
      assert length(hub_nodes) == 1
    end

    test "viewer cannot restore nodes", %{conn: conn, user: user} do
      owner = Storyarn.AccountsFixtures.user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      flow = flow_fixture(project, %{name: "Viewer Flow"})

      node =
        node_fixture(flow, %{type: "hub", data: %{"hub_id" => "test", "color" => "#8b5cf6"}})

      {:ok, _, _meta} = Flows.delete_node(node)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "restore_node", %{"id" => node.id})

      # Node should still be deleted
      updated_flow = Flows.get_flow!(project.id, flow.id)
      hub_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "hub"))
      assert hub_nodes == []
    end

    test "editor can add nodes", %{conn: conn, user: user} do
      owner = Storyarn.AccountsFixtures.user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")
      flow = flow_fixture(project, %{name: "Editor Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_click(view, "add_node", %{"type" => "hub"})

      updated_flow = Flows.get_flow!(project.id, flow.id)
      hub_nodes = Enum.filter(updated_flow.nodes, &(&1.type == "hub"))
      assert length(hub_nodes) == 1
    end
  end
end
