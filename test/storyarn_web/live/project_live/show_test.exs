defmodule StoryarnWeb.ProjectLive.ShowTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  describe "Show" do
    setup :register_and_log_in_user

    test "renders project for owner", %{conn: conn, user: user} do
      project =
        project_fixture(user, %{name: "My Project", description: "A description"})
        |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      assert html =~ "My Project"
      assert html =~ "A description"
      assert html =~ "Settings"
    end

    test "renders project for member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Shared Project"}) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:ok, view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      assert html =~ "Shared Project"
      # Settings button in header is hidden for non-owners, but sidebar link is always there
      refute has_element?(view, "header .btn", "Settings")
    end

    test "shows settings link for owner", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      assert html =~ "Settings"
    end

    test "hides settings button in header for non-owner", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      # Settings button in header is hidden for non-owners
      refute has_element?(view, "header .btn", "Settings")
    end

    test "redirects for non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      assert path == "/workspaces"
      assert flash["error"] =~ "not found"
    end

    test "shows back to workspace link", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      assert html =~ "Back to Workspace"
      # Check it links to the workspace
      assert html =~ ~r/workspaces\/#{project.workspace.slug}/
    end
  end
end
