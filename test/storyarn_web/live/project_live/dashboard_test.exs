defmodule StoryarnWeb.ProjectLive.DashboardTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  describe "Dashboard" do
    setup :register_and_log_in_user

    test "renders empty state when user has no projects", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/projects")

      assert html =~ "Projects"
      assert html =~ "No projects yet"
    end

    test "lists user's projects", %{conn: conn, user: user} do
      _project = project_fixture(user, %{name: "Test Project", description: "A description"})

      {:ok, _view, html} = live(conn, ~p"/projects")

      assert html =~ "Test Project"
      assert html =~ "A description"
      assert html =~ "owner"
    end

    test "lists projects where user is a member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Shared Project"})
      _membership = membership_fixture(project, user, "editor")

      {:ok, _view, html} = live(conn, ~p"/projects")

      assert html =~ "Shared Project"
      assert html =~ "editor"
    end

    test "opens new project modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/projects")

      assert view |> element("a", "New Project") |> render_click()

      assert_patch(view, ~p"/projects/new")
      assert render(view) =~ "Project Name"
    end

    test "creates a new project", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/projects/new")

      view
      |> form("#project-form", project: %{name: "My New Project", description: "Description"})
      |> render_submit()

      {path, flash} = assert_redirect(view)
      assert path =~ "/projects/"
      assert flash["info"] =~ "created"
    end

    test "validates project form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/projects/new")

      html =
        view
        |> form("#project-form", project: %{name: ""})
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end
  end
end
