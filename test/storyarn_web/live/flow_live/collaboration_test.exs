defmodule StoryarnWeb.FlowLive.CollaborationTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Collaboration
  alias Storyarn.Repo

  # Extracts the name part of an email (before @), matching the collab_toast rendering
  defp email_name(email), do: email |> String.split("@") |> List.first()

  # Simulates the FlowLoader JS hook: triggers the event + waits for start_async
  defp load_flow(view) do
    render_click(view, "load_flow_data", %{})
    render_async(view, 500)
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
      assert html =~ "flow-canvas-#{flow.id}"
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

  describe "handle_presence_event" do
    setup :register_and_log_in_user

    test "updates online_users assign when presence join received", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      # Send a presence join message via the new proxy pattern
      send(
        view.pid,
        {Storyarn.Collaboration.Presence,
         {:join,
          %{
            id: user.id,
            user: %{
              id: user.id,
              email: user.email,
              display_name: user.display_name,
              color: "#ef4444"
            },
            metas: %{metas: [%{user_id: user.id}]}
          }}}
      )

      # Smoke test: presence state is pushed to the JS client via data attributes,
      # not rendered as visible HTML. Verify the handler doesn't crash.
      html = render(view)
      assert html =~ "flow-canvas"
    end
  end

  describe "handle_cursor_update" do
    setup :register_and_log_in_user

    test "ignores cursor updates from own user", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      # Send cursor_update from the same user — should be ignored
      cursor_data = %{
        user_id: user.id,
        user_email: user.email,
        user_color: "#ff0000",
        x: 50.0,
        y: 100.0
      }

      send(view.pid, {:cursor_update, cursor_data})

      # Smoke test: own-user cursors are filtered in the handler; verify no crash.
      html = render(view)
      assert html =~ "flow-canvas"
    end

    test "stores remote cursor from another user", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      other_user = user_fixture()

      cursor_data = %{
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#00ff00",
        x: 200.0,
        y: 300.0
      }

      send(view.pid, {:cursor_update, cursor_data})

      # Smoke test: remote cursors are pushed to JS via events, not rendered as HTML.
      # Verify the handler processes without crashing.
      html = render(view)
      assert html =~ "flow-canvas"
    end
  end

  describe "handle_cursor_leave" do
    setup :register_and_log_in_user

    test "removes user from remote cursors", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      other_user = user_fixture()

      # First add a cursor, then remove it
      cursor_data = %{
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#00ff00",
        x: 200.0,
        y: 300.0
      }

      send(view.pid, {:cursor_update, cursor_data})
      render(view)

      # Now send cursor_leave
      send(view.pid, {:cursor_leave, other_user.id})

      # Smoke test: cursor removal is pushed to JS, not rendered as HTML.
      html = render(view)
      assert html =~ "flow-canvas"
    end
  end

  describe "handle_clear_collab_toast" do
    setup :register_and_log_in_user

    test "clears collaboration toast", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      # First trigger a lock change from another user to get a toast
      other_user = user_fixture()

      lock_payload = %{
        node_id: 999,
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#ff0000"
      }

      send(view.pid, {:lock_change, :locked, lock_payload})
      html = render(view)

      # Toast should be visible (collab_toast shows email name part before @)
      assert html =~ email_name(other_user.email)

      # Now clear it
      send(view.pid, :clear_collab_toast)
      html = render(view)

      # Toast should be gone — the email name should no longer appear
      refute html =~ email_name(other_user.email)
    end
  end

  describe "handle_lock_change" do
    setup :register_and_log_in_user

    test "updates node_locks when another user locks a node", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      node = node_fixture(flow, %{type: "hub", data: %{"label" => "Test Hub"}})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      other_user = user_fixture()

      # Actually acquire the lock so list_locks returns it
      Collaboration.acquire_lock(flow.id, node.id, other_user)

      lock_payload = %{
        node_id: node.id,
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#ff0000"
      }

      send(view.pid, {:lock_change, :locked, lock_payload})
      html = render(view)

      # Should show a collaboration toast for the other user
      assert html =~ email_name(other_user.email)
    end

    test "self-echo for lock_change is prevented by broadcast_from (not handler guard)", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      # In production, broadcast_from prevents self-delivery.
      # When lock_change IS received, it always shows a toast.
      other_user = user_fixture()

      lock_payload = %{
        node_id: 999,
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#ff0000"
      }

      send(view.pid, {:lock_change, :locked, lock_payload})
      html = render(view)

      # Toast should appear since message came from another user
      assert html =~ email_name(other_user.email)
    end

    test "handles unlock from another user", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      other_user = user_fixture()

      unlock_payload = %{
        node_id: 999,
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#00ff00"
      }

      send(view.pid, {:lock_change, :unlocked, unlock_payload})
      html = render(view)

      # Should show a collaboration toast for the unlock
      assert html =~ email_name(other_user.email)
    end
  end

  describe "handle_remote_change" do
    setup :register_and_log_in_user

    test "self-echo is prevented by broadcast_from (not by handler guard)", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      # In production, broadcast_from prevents self-delivery.
      # When a remote_change is received (even with same user_id), it's processed.
      # This test verifies the handler doesn't crash on any payload shape.
      other_user = user_fixture()

      payload = %{
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#ff0000",
        node_id: 999
      }

      send(view.pid, {:remote_change, :node_updated, payload})
      html = render(view)

      # View should not crash; toast appears with "updated a node"
      assert html =~ "flow-canvas"
      assert html =~ email_name(other_user.email)
    end

    test "reloads flow data on node_updated from another user", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      node = node_fixture(flow, %{type: "hub", data: %{"label" => "Test Hub"}})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      other_user = user_fixture()

      payload = %{
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#00ff00",
        node_id: node.id,
        node_data: %{"label" => "Updated Hub"}
      }

      send(view.pid, {:remote_change, :node_updated, payload})
      html = render(view)

      # Should show collaboration toast
      assert html =~ email_name(other_user.email)
    end

    test "handles node_added from another user", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      other_user = user_fixture()

      payload = %{
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#00ff00",
        node_data: %{"type" => "hub", "label" => "New Hub"}
      }

      send(view.pid, {:remote_change, :node_added, payload})
      html = render(view)

      # Should show collaboration toast
      assert html =~ email_name(other_user.email)
    end

    test "handles node_deleted from another user", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})
      node = node_fixture(flow, %{type: "hub", data: %{"label" => "Test Hub"}})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      other_user = user_fixture()

      payload = %{
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#00ff00",
        node_id: node.id
      }

      send(view.pid, {:remote_change, :node_deleted, payload})
      html = render(view)

      assert html =~ email_name(other_user.email)
    end

    test "handles connection_added from another user", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      other_user = user_fixture()

      payload = %{
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#00ff00",
        connection_data: %{"source_node_id" => 1, "target_node_id" => 2}
      }

      send(view.pid, {:remote_change, :connection_added, payload})
      html = render(view)

      assert html =~ email_name(other_user.email)
    end

    test "handles connection_deleted from another user", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      other_user = user_fixture()

      payload = %{
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#00ff00",
        source_node_id: 1,
        target_node_id: 2
      }

      send(view.pid, {:remote_change, :connection_deleted, payload})
      html = render(view)

      assert html =~ email_name(other_user.email)
    end

    test "handles node_moved from another user", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      other_user = user_fixture()

      payload = %{
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#00ff00",
        node_id: 999,
        x: 500.0,
        y: 600.0
      }

      send(view.pid, {:remote_change, :node_moved, payload})
      html = render(view)

      assert html =~ email_name(other_user.email)
    end

    test "handles flow_refresh from another user", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      other_user = user_fixture()

      payload = %{
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#00ff00"
      }

      send(view.pid, {:remote_change, :flow_refresh, payload})
      html = render(view)

      assert html =~ email_name(other_user.email)
    end

    test "handles connection_updated from another user", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      other_user = user_fixture()

      payload = %{
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#00ff00",
        connection_id: 123,
        label: "true",
        condition: nil
      }

      send(view.pid, {:remote_change, :connection_updated, payload})
      html = render(view)

      assert html =~ email_name(other_user.email)
    end

    test "handles node_restored from another user", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Test Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      other_user = user_fixture()

      payload = %{
        user_id: other_user.id,
        user_email: other_user.email,
        user_color: "#00ff00",
        node_data: %{"type" => "hub", "label" => "Restored Hub"},
        connections: []
      }

      send(view.pid, {:remote_change, :node_restored, payload})
      html = render(view)

      assert html =~ email_name(other_user.email)
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
