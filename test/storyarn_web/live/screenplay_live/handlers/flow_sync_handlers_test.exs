defmodule StoryarnWeb.ScreenplayLive.Handlers.FlowSyncHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  alias Storyarn.Flows
  alias Storyarn.Repo
  alias Storyarn.Screenplays

  describe "FlowSyncHandlers" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp show_url(project, screenplay) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays/#{screenplay.id}"
    end

    # -----------------------------------------------------------------------
    # do_sync_to_flow
    # -----------------------------------------------------------------------

    test "sync_to_flow when not linked shows error flash", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Test.", position: 0})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("sync_to_flow")

      assert render(view) =~ "not linked"
    end

    test "sync_to_flow when linked syncs successfully", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      element_fixture(screenplay, %{
        type: "scene_heading",
        content: "INT. OFFICE - DAY",
        position: 0
      })

      {:ok, flow} = Flows.create_flow(project, %{name: "Test Flow"})
      {:ok, _screenplay} = Screenplays.FlowSync.link_to_flow(screenplay, flow.id)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("sync_to_flow")

      assert render(view) =~ "synced to flow"
    end

    # -----------------------------------------------------------------------
    # do_sync_from_flow
    # -----------------------------------------------------------------------

    test "sync_from_flow when not linked shows error flash", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Test.", position: 0})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("sync_from_flow")

      assert render(view) =~ "not linked"
    end

    test "sync_from_flow with linked flow updates elements", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      element_fixture(screenplay, %{
        type: "scene_heading",
        content: "INT. OFFICE - DAY",
        position: 0
      })

      element_fixture(screenplay, %{type: "action", content: "Original.", position: 1})

      # Create flow and sync to it first
      {:ok, _flow} = Screenplays.FlowSync.sync_to_flow(screenplay)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("sync_from_flow")

      assert render(view) =~ "updated from flow"
    end

    test "sync_from_flow with no entry node shows specific error", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = Flows.create_flow(project, %{name: "Empty Flow"})
      {:ok, _screenplay} = Screenplays.FlowSync.link_to_flow(screenplay, flow.id)

      # Soft-delete entry node directly (can't use delete_node for entry type)
      flow_nodes = Flows.list_nodes(flow.id)
      now = Storyarn.Shared.TimeHelpers.now()

      Enum.each(flow_nodes, fn node ->
        node
        |> Ecto.Changeset.change(deleted_at: now)
        |> Repo.update!()
      end)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("sync_from_flow")

      html = render(view)
      # Should show some error — either "no entry node" or generic
      assert html =~ "entry node" or html =~ "Could not sync"
    end

    # -----------------------------------------------------------------------
    # do_create_flow_from_screenplay
    # -----------------------------------------------------------------------

    test "create_flow_from_screenplay creates flow and syncs", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      element_fixture(screenplay, %{
        type: "scene_heading",
        content: "INT. OFFICE - DAY",
        position: 0
      })

      element_fixture(screenplay, %{type: "action", content: "A desk.", position: 1})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("create_flow_from_screenplay")

      html = render(view)
      assert html =~ "sp-sync-linked"
      assert html =~ "Flow created and synced"

      updated = Screenplays.get_screenplay!(project.id, screenplay.id)
      assert updated.linked_flow_id != nil
    end

    test "create_flow_from_screenplay with empty screenplay still creates flow", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("create_flow_from_screenplay")

      html = render(view)
      # Even with no elements, a flow + entry node should be created
      assert html =~ "Flow created" or html =~ "sp-sync-linked"
    end

    # -----------------------------------------------------------------------
    # do_unlink_flow
    # -----------------------------------------------------------------------

    test "unlink_flow clears link and updates status", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = Flows.create_flow(project, %{name: "Test Flow"})
      {:ok, _screenplay} = Screenplays.FlowSync.link_to_flow(screenplay, flow.id)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      assert render(view) =~ "sp-sync-linked"

      view |> render_click("unlink_flow")

      html = render(view)
      assert html =~ "Flow unlinked"
      assert html =~ "Create Flow"
      refute html =~ "sp-sync-linked"

      updated = Screenplays.get_screenplay!(project.id, screenplay.id)
      assert is_nil(updated.linked_flow_id)
    end

    # -----------------------------------------------------------------------
    # do_navigate_to_flow
    # -----------------------------------------------------------------------

    test "navigate_to_flow redirects to linked flow", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = Flows.create_flow(project, %{name: "Test Flow"})
      {:ok, _screenplay} = Screenplays.FlowSync.link_to_flow(screenplay, flow.id)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      assert {:error, {:live_redirect, %{to: to}}} =
               render_click(view, "navigate_to_flow")

      assert to =~ "/flows/#{flow.id}"
    end

    test "navigate_to_flow with no linked flow is a no-op", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      render_click(view, "navigate_to_flow")

      assert render(view) =~ "screenplay-page"
    end

    # -----------------------------------------------------------------------
    # detect_link_status — via mount rendering
    # -----------------------------------------------------------------------

    test "mount detects unlinked status for screenplay with no flow", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "Create Flow"
      refute html =~ "sp-sync-linked"
    end

    test "mount detects linked status for screenplay with valid flow", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = Flows.create_flow(project, %{name: "Linked Flow"})
      {:ok, _screenplay} = Screenplays.FlowSync.link_to_flow(screenplay, flow.id)

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "sp-sync-linked"
      assert html =~ "Linked Flow"
    end

    test "mount detects flow_deleted status when linked flow is soft-deleted", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = Flows.create_flow(project, %{name: "Deleted Flow"})
      {:ok, _screenplay} = Screenplays.FlowSync.link_to_flow(screenplay, flow.id)

      # Soft-delete the flow
      Flows.delete_flow(flow)

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      # Should not show as "linked" since the flow is deleted
      # The toolbar should indicate the flow is missing/deleted
      refute html =~ "sp-sync-linked"
    end

    test "mount detects flow_missing status when linked flow does not exist", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      {:ok, flow} = Flows.create_flow(project, %{name: "Temp Flow"})
      {:ok, _screenplay} = Screenplays.FlowSync.link_to_flow(screenplay, flow.id)

      # Hard-delete the flow record so it truly does not exist
      Repo.delete!(flow)

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      # Should not show as linked
      refute html =~ "sp-sync-linked"
    end

    # -----------------------------------------------------------------------
    # Authorization
    # -----------------------------------------------------------------------

    test "viewer cannot sync to flow", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      {:ok, flow} = Flows.create_flow(project, %{name: "Test Flow"})
      {:ok, _screenplay} = Screenplays.FlowSync.link_to_flow(screenplay, flow.id)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("sync_to_flow")

      assert render(view) =~ "permission"
    end

    test "viewer cannot sync from flow", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      {:ok, flow} = Flows.create_flow(project, %{name: "Test Flow"})
      {:ok, _screenplay} = Screenplays.FlowSync.link_to_flow(screenplay, flow.id)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("sync_from_flow")

      assert render(view) =~ "permission"
    end

    test "viewer cannot create flow from screenplay", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("create_flow_from_screenplay")

      assert render(view) =~ "permission"
      updated = Screenplays.get_screenplay!(project.id, screenplay.id)
      assert is_nil(updated.linked_flow_id)
    end

    test "viewer cannot unlink flow", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      {:ok, flow} = Flows.create_flow(project, %{name: "Test Flow"})
      {:ok, _screenplay} = Screenplays.FlowSync.link_to_flow(screenplay, flow.id)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("unlink_flow")

      assert render(view) =~ "permission"
      updated = Screenplays.get_screenplay!(project.id, screenplay.id)
      assert updated.linked_flow_id == flow.id
    end
  end
end
