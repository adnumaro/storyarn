defmodule StoryarnWeb.ScreenplayLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  alias Storyarn.Repo

  describe "Index" do
    setup :register_and_log_in_user

    test "renders Screenplays header for project owner", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays")

      assert html =~ "Screenplays"
      assert html =~ "Write and format screenplays with industry-standard formatting"
    end

    test "renders empty state when no screenplays exist", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays")

      assert html =~ "No screenplays yet"
    end

    test "renders Screenplays tool link in sidebar", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays")

      assert has_element?(view, "a", "Screenplays")
    end

    test "renders screenplay names in sidebar tree when screenplays exist", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      screenplay_fixture(project, %{name: "Act One"})
      screenplay_fixture(project, %{name: "Act Two"})

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays")

      assert html =~ "Act One"
      assert html =~ "Act Two"
    end

    test "renders 'No screenplays yet' in sidebar tree when empty", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays")

      assert has_element?(view, "#screenplays-tree-container") == false
      assert render(view) =~ "No screenplays yet"
    end

    test "creates screenplay when clicking New Screenplay button", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays")

      assert view
             |> element("button", "New Screenplay")
             |> render_click()
    end

    test "creates screenplay via form and redirects to show page", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays/new"
        )

      view
      |> form("#screenplay-form", screenplay: %{name: "My Screenplay"})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/screenplays/"
    end

    test "shows validation error when name is empty", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays/new"
        )

      assert view
             |> form("#screenplay-form", screenplay: %{name: ""})
             |> render_change() =~ "can&#39;t be blank"
    end

    test "redirects non-members to /workspaces", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays")

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end
  end

  describe "Event handlers" do
    setup :register_and_log_in_user

    test "create_screenplay creates and redirects to show", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays")

      view |> render_click("create_screenplay")

      {path, _flash} = assert_redirect(view)
      assert path =~ "/screenplays/"
    end

    test "create_child_screenplay creates with parent_id and redirects", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = screenplay_fixture(project, %{name: "Parent"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays")

      view |> render_click("create_child_screenplay", %{"parent-id" => to_string(parent.id)})

      {path, _flash} = assert_redirect(view)
      assert path =~ "/screenplays/"
    end

    test "delete_screenplay moves to trash and shows flash", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      screenplay = screenplay_fixture(project, %{name: "To Delete"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays")

      assert render(view) =~ "To Delete"

      view |> render_click("delete", %{"id" => to_string(screenplay.id)})

      html = render(view)
      refute html =~ "To Delete"
      assert html =~ "Screenplay moved to trash"
    end

    test "move_to_parent moves screenplay to new parent", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = screenplay_fixture(project, %{name: "Parent"})
      child = screenplay_fixture(project, %{name: "Child"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays")

      view
      |> render_click("move_to_parent", %{
        "item_id" => to_string(child.id),
        "new_parent_id" => to_string(parent.id),
        "position" => "0"
      })

      moved = Storyarn.Repo.get!(Storyarn.Screenplays.Screenplay, child.id)
      assert moved.parent_id == parent.id
    end

    test "viewer cannot create screenplay", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays")

      view |> render_click("create_screenplay")

      assert render(view) =~ "permission"
    end

    test "viewer cannot delete screenplay", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project, %{name: "Protected"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays")

      view |> render_click("delete", %{"id" => to_string(screenplay.id)})

      html = render(view)
      assert html =~ "permission"
      assert html =~ "Protected"
    end

    test "delete card shows confirmation text", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      screenplay_fixture(project, %{name: "Confirm Me"})

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays")

      assert html =~ "Are you sure you want to delete this screenplay?"
    end
  end
end
