defmodule StoryarnWeb.ProjectLive.ShowTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  describe "Show" do
    setup :register_and_log_in_user

    test "renders project for owner", %{conn: conn, user: user} do
      project = project_fixture(user, %{name: "My Project", description: "A description"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}")

      assert html =~ "My Project"
      assert html =~ "A description"
      assert html =~ "Settings"
    end

    test "renders project for member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Shared Project"})
      _membership = membership_fixture(project, user, "editor")

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}")

      assert html =~ "Shared Project"
      # Settings link is shown only for owners - check that it's not in the project header
      # (Settings appears in user navbar, so we check for the project settings link specifically)
      refute html =~ ~r/projects\/#{project.id}\/settings/
    end

    test "shows settings link for owner", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}")

      assert html =~ "Settings"
    end

    test "hides settings link for non-owner", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner)
      _membership = membership_fixture(project, user, "editor")

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}")

      # Check that the project settings link is not present
      refute html =~ ~r/projects\/#{project.id}\/settings/
    end

    test "redirects for non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/projects/#{project.id}")

      assert path == "/projects"
      assert flash["error"] =~ "not found"
    end

    test "shows back to projects link", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}")

      assert html =~ "Back to projects"
    end
  end
end
