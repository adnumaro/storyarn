defmodule StoryarnWeb.WorkspaceLive.InvitationTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.WorkspaceInvitation

  describe "mount with valid token" do
    setup :register_and_log_in_user

    test "renders invitation details", %{conn: conn, user: user} do
      {workspace, _invitation, encoded_token} = create_invitation_for(user)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      assert html =~ workspace.name
      assert html =~ "Accept Invitation"
    end

    test "shows email mismatch warning when logged in as different user", %{conn: conn} do
      other_user = user_fixture()
      {_workspace, invitation, encoded_token} = create_invitation_for(other_user)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      assert html =~ invitation.email
      assert html =~ "logged in as"
    end
  end

  describe "mount with invalid token" do
    setup :register_and_log_in_user

    test "renders invalid invitation page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/workspaces/invitations/invalidtoken123")
      assert html =~ "Invalid Invitation"
    end
  end

  describe "mount unauthenticated" do
    test "shows login prompt", %{conn: conn} do
      user = user_fixture()
      {_workspace, _invitation, encoded_token} = create_invitation_for(user)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      assert html =~ "Log in to accept"
    end
  end

  describe "accept event" do
    setup :register_and_log_in_user

    test "accepts invitation and redirects", %{conn: conn, user: user} do
      {workspace, _invitation, encoded_token} = create_invitation_for(user)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      result = view |> element("button", "Accept Invitation") |> render_click()

      assert {:error, {:live_redirect, %{to: redirect_path}}} = result
      assert redirect_path =~ "/workspaces/#{workspace.slug}"
    end

    test "handles already accepted invitation", %{conn: conn, user: user} do
      {_workspace, invitation, encoded_token} = create_invitation_for(user)

      # Accept first
      Workspaces.accept_invitation(invitation, user)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      # Already accepted invitation should show as invalid
      assert html =~ "Invalid Invitation"
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp create_invitation_for(target_user) do
    owner = user_fixture()
    workspace = workspace_fixture(owner)

    # Build invitation manually to capture encoded_token
    {encoded_token, invitation_struct} =
      WorkspaceInvitation.build_invitation(workspace, owner, target_user.email)

    {:ok, invitation} = Storyarn.Repo.insert(invitation_struct)
    invitation = Storyarn.Repo.preload(invitation, [:workspace, :invited_by])

    {workspace, invitation, encoded_token}
  end
end
