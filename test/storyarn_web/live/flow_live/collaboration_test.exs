defmodule StoryarnWeb.FlowLive.CollaborationTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Collaboration
  alias Storyarn.Repo

  # Simulates the FlowLoader JS hook: triggers the event + waits for start_async
  defp load_flow(view) do
    render_click(view, "load_flow_data", %{})
    render_async(view)
  end

  describe "Flow Editor Collaboration" do
    setup :register_and_log_in_user

    test "renders flow editor with collaboration assigns", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      # Simulate FlowLoader hook + wait for async data load
      html = load_flow(view)

      # Canvas should have collaboration data attributes
      assert html =~ "data-user-id=\"#{user.id}\""
      assert html =~ "data-user-color"
      assert html =~ "data-locks"

      # View should have online_users assign
      assert view |> element("#flow-canvas") |> has_element?()
    end

    test "acquires lock on node selection", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      node = node_fixture(flow, %{type: "hub", data: %{"label" => "Test Hub"}})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      # Simulate node selection
      render_click(view, "node_selected", %{"id" => node.id})

      # Lock should be acquired
      {:ok, lock_info} = Collaboration.get_lock(flow.id, node.id)
      assert lock_info.user_id == user.id
    end

    test "releases lock on node deselection", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      node = node_fixture(flow, %{type: "hub", data: %{"label" => "Test Hub"}})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      # Select then deselect node
      render_click(view, "node_selected", %{"id" => node.id})
      render_click(view, "deselect_node", %{})

      # Lock should be released
      assert {:error, :not_locked} = Collaboration.get_lock(flow.id, node.id)
    end

    test "prevents editing node locked by another user", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      node = node_fixture(flow, %{type: "hub", data: %{"label" => "Test Hub"}})

      # Another user locks the node
      other_user = user_fixture()
      Collaboration.acquire_lock(flow.id, node.id, other_user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      # Try to delete the locked node
      html = render_click(view, "delete_node", %{"id" => node.id})

      # Should show error message
      assert html =~ "being edited by another user"
    end

    test "cursor_moved event is handled", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      # Should not crash when receiving cursor_moved event
      render_click(view, "cursor_moved", %{"x" => 100.0, "y" => 200.0})
    end

    test "broadcasts changes on node creation", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      # Subscribe to changes
      Collaboration.subscribe_changes(flow.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      # Create a node
      render_click(view, "add_node", %{"type" => "hub"})

      # Should receive broadcast
      assert_receive {:remote_change, :node_added, _payload}, 1000
    end

    test "broadcasts changes on node deletion", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      node = node_fixture(flow, %{type: "hub", data: %{"label" => "Test Hub"}})

      # Subscribe to changes
      Collaboration.subscribe_changes(flow.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      # Delete the node
      render_click(view, "delete_node", %{"id" => node.id})

      # Should receive broadcast
      assert_receive {:remote_change, :node_deleted, _payload}, 1000
    end
  end

  describe "Flow Editor viewer role" do
    setup :register_and_log_in_user

    test "viewer cannot edit nodes", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      node = node_fixture(flow, %{type: "hub", data: %{"label" => "Test Hub"}})

      # Add user as viewer to the project
      _membership = membership_fixture(project, user, "viewer")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      # Try to delete (should be blocked)
      html = render_click(view, "delete_node", %{"id" => node.id})

      # HTML entity encodes the apostrophe
      assert html =~ "You don" or html =~ "permission"
    end
  end
end
