defmodule StoryarnWeb.ProjectLive.SettingsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  describe "Settings" do
    setup :register_and_log_in_user

    test "renders project settings for owner", %{conn: conn, user: user} do
      project = project_fixture(user, %{name: "My Project"}) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")

      assert html =~ "Project Settings"
      assert html =~ "My Project"
      assert html =~ "Team Members"
      assert html =~ "Danger Zone"
    end

    test "redirects non-owner", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")

      assert path =~ "/workspaces/#{project.workspace.slug}/projects/#{project.slug}"
      assert flash["error"] =~ "permission"
    end

    test "updates project details", %{conn: conn, user: user} do
      project = project_fixture(user, %{name: "Old Name"}) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")

      html =
        view
        |> form("#project-form", project: %{name: "New Name"})
        |> render_submit()

      assert html =~ "updated successfully"
      # The form should now show the new name as the value
      assert html =~ ~s(value="New Name")
    end

    test "lists team members", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      member = user_fixture(%{email: "member@example.com"})
      _membership = membership_fixture(project, member, "editor")

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")

      assert html =~ user.email
      assert html =~ "member@example.com"
      assert html =~ "owner"
      assert html =~ "editor"
    end

    test "sends invitation", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")

      view
      |> form("#invite-form", invite: %{email: "newmember@example.com", role: "editor"})
      |> render_submit()

      assert render(view) =~ "Invitation sent"
      assert render(view) =~ "newmember@example.com"
      assert render(view) =~ "Pending"
    end

    test "shows error for duplicate invitation", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      _invitation = invitation_fixture(project, user, "existing@example.com")

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")

      view
      |> form("#invite-form", invite: %{email: "existing@example.com", role: "editor"})
      |> render_submit()

      assert render(view) =~ "already been sent"
    end

    test "revokes invitation", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      invitation = invitation_fixture(project, user, "pending@example.com")

      {:ok, view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")

      assert html =~ "pending@example.com"

      render_click(view, "revoke_invitation", %{id: to_string(invitation.id)})

      assert render(view) =~ "Invitation revoked"
      refute render(view) =~ "pending@example.com"
    end

    test "removes member", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      member = user_fixture(%{email: "removeme@example.com"})
      membership = membership_fixture(project, member, "editor")

      {:ok, view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")

      assert html =~ "removeme@example.com"

      render_click(view, "remove_member", %{id: to_string(membership.id)})

      assert render(view) =~ "Member removed"
      refute render(view) =~ "removeme@example.com"
    end

    test "deletes project", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")

      render_click(view, "delete_project")

      {path, flash} = assert_redirect(view)
      assert path == "/workspaces/#{project.workspace.slug}"
      assert flash["info"] =~ "deleted"
    end
  end
end
