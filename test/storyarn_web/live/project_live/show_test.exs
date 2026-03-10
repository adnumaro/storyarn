defmodule StoryarnWeb.ProjectLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  describe "Show" do
    setup :register_and_log_in_user

    test "renders project dashboard for owner", %{conn: conn, user: user} do
      project =
        project_fixture(user, %{name: "My Project"})
        |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      # Project name in toolbar
      assert html =~ "My Project"
      # Dashboard tool is active (icon rendered)
      assert html =~ "layout-dashboard"
    end

    test "renders project dashboard for member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Shared Project"}) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      assert html =~ "Shared Project"
    end

    test "redirects for non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      assert path == "/workspaces"
      assert flash["error"] =~ "not found"
    end

    test "shows tool switcher with other tools", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      # Tool switcher shows other tools (not Dashboard since it's active)
      assert html =~ "Sheets"
      assert html =~ "Flows"
    end
  end
end
