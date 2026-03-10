defmodule StoryarnWeb.ProjectLive.SettingsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  defp settings_path(project, section \\ nil) do
    base = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings"
    if section, do: "#{base}/#{section}", else: base
  end

  describe "General section" do
    setup :register_and_log_in_user

    test "renders settings with sidebar navigation", %{conn: conn, user: user} do
      project = project_fixture(user, %{name: "My Project"}) |> Repo.preload(:workspace)

      {:ok, _view, html} = live(conn, settings_path(project))

      # Sidebar sections
      assert html =~ "Back to project"
      assert html =~ "General"
      assert html =~ "Integrations"
      assert html =~ "Localization"
      assert html =~ "Administration"
      assert html =~ "Members"
      assert html =~ "Import &amp; Export"

      # General content
      assert html =~ "My Project"
      assert html =~ "Project Theme"
      assert html =~ "Maintenance"
      assert html =~ "Danger Zone"
    end

    test "redirects non-owner", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, settings_path(project))

      assert path =~ "/workspaces/#{project.workspace.slug}/projects/#{project.slug}"
      assert flash["error"] =~ "permission"
    end

    test "updates project details", %{conn: conn, user: user} do
      project = project_fixture(user, %{name: "Old Name"}) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project))

      html =
        view
        |> form("#project-form", project: %{name: "New Name"})
        |> render_submit()

      assert html =~ "updated successfully"
      assert html =~ ~s(value="New Name")
    end

    test "deletes project from danger zone", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project))

      render_click(view, "delete_project")

      {path, flash} = assert_redirect(view)
      assert path == "/workspaces/#{project.workspace.slug}"
      assert flash["info"] =~ "deleted"
    end
  end

  describe "Members section" do
    setup :register_and_log_in_user

    test "lists team members", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      member = user_fixture(%{email: "member@example.com"})
      _membership = membership_fixture(project, member, "editor")

      {:ok, _view, html} = live(conn, settings_path(project, "members"))

      assert html =~ user.email
      assert html =~ "member@example.com"
      assert html =~ "owner"
      assert html =~ "editor"
    end

    test "sends invitation request", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      view
      |> form("#invite-form", invite: %{email: "newmember@example.com", role: "editor"})
      |> render_submit()

      assert render(view) =~ "Invitation request sent"
    end

    test "removes member", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      member = user_fixture(%{email: "removeme@example.com"})
      membership = membership_fixture(project, member, "editor")

      {:ok, view, html} = live(conn, settings_path(project, "members"))

      assert html =~ "removeme@example.com"

      render_click(view, "remove_member", %{id: to_string(membership.id)})

      assert render(view) =~ "Member removed"
      refute render(view) =~ "removeme@example.com"
    end
  end
end
