defmodule StoryarnWeb.ScreenplayLive.Handlers.TreeHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  alias Storyarn.{Repo, Screenplays}

  describe "tree operations via LiveView" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp show_url(project, screenplay) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays/#{screenplay.id}"
    end

    # ── Create ────────────────────────────────────────────────────

    test "create_screenplay creates and navigates to new screenplay", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      assert {:error, {:live_redirect, %{to: to}}} =
               render_click(view, "create_screenplay")

      assert to =~ "/screenplays/"
    end

    test "create_child_screenplay creates with parent_id", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      assert {:error, {:live_redirect, %{to: to}}} =
               render_click(view, "create_child_screenplay", %{
                 "parent-id" => to_string(screenplay.id)
               })

      assert to =~ "/screenplays/"
    end

    # ── Delete ────────────────────────────────────────────────────

    test "delete current screenplay navigates to index", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      render_click(view, "set_pending_delete_screenplay", %{"id" => to_string(screenplay.id)})

      assert {:error, {:live_redirect, %{to: to}}} =
               render_click(view, "confirm_delete_screenplay")

      assert to =~ "/screenplays"
    end

    test "delete other screenplay reloads tree", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      other = screenplay_fixture(project, %{name: "Other"})
      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      render_click(view, "set_pending_delete_screenplay", %{"id" => to_string(other.id)})
      html = render_click(view, "confirm_delete_screenplay")

      assert html =~ "moved to trash"
    end

    test "delete non-existent screenplay shows error", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      render_click(view, "set_pending_delete_screenplay", %{"id" => "99999"})
      html = render_click(view, "confirm_delete_screenplay")

      assert html =~ "not found"
    end

    # ── Rename ────────────────────────────────────────────────────

    test "save_name updates screenplay name", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      render_click(view, "save_name", %{"name" => "Renamed Script"})

      updated = Screenplays.get_screenplay!(project.id, screenplay.id)
      assert updated.name == "Renamed Script"
    end

    # ── Move ──────────────────────────────────────────────────────

    test "move screenplay to root position", %{conn: conn, project: project} do
      parent = screenplay_fixture(project, %{name: "Parent"})
      child = screenplay_fixture(project, %{name: "Child", parent_id: parent.id})
      {:ok, view, _html} = live(conn, show_url(project, child))

      render_click(view, "move_to_parent", %{
        "item_id" => to_string(child.id),
        "new_parent_id" => "",
        "position" => "0"
      })

      updated = Screenplays.get_screenplay!(project.id, child.id)
      assert is_nil(updated.parent_id)
    end

    # ── Authorization ─────────────────────────────────────────────

    test "viewer cannot create screenplay", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      result = render_click(view, "create_screenplay")

      # Should either show permission error or not navigate
      html = if is_binary(result), do: result, else: render(view)
      assert html =~ "permission" or html =~ "screenplay-page"
    end
  end
end
