defmodule StoryarnWeb.ProjectLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

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

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      assert html =~ "Shared Project"
      # Settings button is hidden for non-owners (editors can't manage project)
      refute html =~ "Settings"
    end

    test "shows settings link for owner", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      assert html =~ "Settings"
    end

    test "hides settings button for non-owner", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      # Settings button is hidden for non-owners
      refute html =~ "Settings"
    end

    test "redirects for non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      assert path == "/workspaces"
      assert flash["error"] =~ "not found"
    end

    test "shows workspace sidebar with link to workspace", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      # Layouts.app sidebar has workspace link
      assert html =~ ~r/workspaces\/#{project.workspace.slug}/
    end
  end
end
