defmodule StoryarnWeb.ProjectLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  defp get_left_toolbar_vue(view) do
    LiveVue.Test.get_vue(view, name: "layout/LeftToolbar")
  end

  describe "Show" do
    setup :register_and_log_in_user

    test "renders project dashboard for owner", %{conn: conn, user: user} do
      project =
        project_fixture(user, %{name: "My Project"})
        |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      # Project name shows in the left toolbar
      toolbar = get_left_toolbar_vue(view)
      assert toolbar.props["project-name"] == "My Project"
      assert toolbar.props["active-tool"] == "dashboard"
    end

    test "renders project dashboard for member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Shared Project"}) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      toolbar = get_left_toolbar_vue(view)
      assert toolbar.props["project-name"] == "Shared Project"
    end

    test "redirects for non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      assert path == "/workspaces"
      assert flash["error"] =~ "not found"
    end

    test "shows tool switcher enabled", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      toolbar = get_left_toolbar_vue(view)
      assert toolbar.props["show-tool-switcher"] == true
    end
  end
end
