defmodule StoryarnWeb.ProjectLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  defp get_project_layout_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/layouts/project/Layout")
  end

  describe "Show" do
    setup :register_and_log_in_user

    test "renders project dashboard for owner", %{conn: conn, user: user} do
      project =
        user
        |> project_fixture(%{name: "My Project"})
        |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      chrome = get_project_layout_vue(view).props["chrome"]
      assert chrome["projectName"] == "My Project"
      assert chrome["activeTool"] == "dashboard"
    end

    test "renders project dashboard for member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture(%{name: "Shared Project"}) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      chrome = get_project_layout_vue(view).props["chrome"]
      assert chrome["projectName"] == "Shared Project"
    end

    test "redirects for non-member", %{conn: conn} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "shows tool switcher enabled", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      chrome = get_project_layout_vue(view).props["chrome"]
      assert chrome["showToolSwitcher"] == true
    end
  end
end
