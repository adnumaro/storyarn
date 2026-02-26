defmodule Storyarn.Workspaces.InvitationsTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.{WorkspaceInvitation, WorkspaceMembership}

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  # --------------------------------------------------------------------------
  # Helpers
  # --------------------------------------------------------------------------

  defp create_invitation_with_token(workspace, invited_by, email, role \\ "member") do
    {encoded_token, invitation} =
      WorkspaceInvitation.build_invitation(workspace, invited_by, email, role)

    {:ok, invitation} = Repo.insert(invitation)
    {encoded_token, invitation}
  end

  defp create_workspace_and_owner do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    %{owner: owner, workspace: workspace}
  end

  defp expired_datetime do
    DateTime.utc_now()
    |> DateTime.add(-1, :day)
    |> DateTime.truncate(:second)
  end

  # --------------------------------------------------------------------------
  # Tests
  # --------------------------------------------------------------------------

  describe "list_pending_invitations/1" do
    test "returns pending invitations for a workspace" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {:ok, _invitation} =
        Workspaces.create_invitation(workspace, owner, "invitee@example.com", "member")

      invitations = Workspaces.list_pending_invitations(workspace.id)
      assert length(invitations) == 1
      assert hd(invitations).email == "invitee@example.com"
    end

    test "returns empty list when no pending invitations" do
      %{workspace: workspace} = create_workspace_and_owner()

      assert Workspaces.list_pending_invitations(workspace.id) == []
    end

    test "does not return accepted invitations" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {_token, invitation} =
        create_invitation_with_token(workspace, owner, "invitee@example.com")

      # Mark as accepted
      invitation
      |> Ecto.Changeset.change(accepted_at: DateTime.utc_now(:second))
      |> Repo.update!()

      assert Workspaces.list_pending_invitations(workspace.id) == []
    end

    test "does not return expired invitations" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {_encoded_token, invitation} =
        WorkspaceInvitation.build_invitation(workspace, owner, "expired@example.com")

      expired_invitation = %{invitation | expires_at: expired_datetime()}
      {:ok, _} = Repo.insert(expired_invitation)

      assert Workspaces.list_pending_invitations(workspace.id) == []
    end

    test "preloads invited_by association" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {:ok, _invitation} =
        Workspaces.create_invitation(workspace, owner, "invitee@example.com", "member")

      [invitation] = Workspaces.list_pending_invitations(workspace.id)
      assert invitation.invited_by.id == owner.id
    end

    test "returns multiple pending invitations" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {:ok, _inv1} =
        Workspaces.create_invitation(workspace, owner, "first@example.com", "member")

      {:ok, _inv2} =
        Workspaces.create_invitation(workspace, owner, "second@example.com", "member")

      invitations = Workspaces.list_pending_invitations(workspace.id)
      assert length(invitations) == 2

      emails = Enum.map(invitations, & &1.email)
      assert "first@example.com" in emails
      assert "second@example.com" in emails
    end
  end

  describe "create_invitation/4" do
    test "creates invitation and returns it" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      email = unique_user_email()

      assert {:ok, invitation} = Workspaces.create_invitation(workspace, owner, email, "admin")
      assert invitation.email == String.downcase(email)
      assert invitation.role == "admin"
      assert invitation.workspace_id == workspace.id
      assert invitation.invited_by_id == owner.id
    end

    test "defaults to member role" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      email = unique_user_email()

      assert {:ok, invitation} = Workspaces.create_invitation(workspace, owner, email)
      assert invitation.role == "member"
    end

    test "downcases email" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      assert {:ok, invitation} =
               Workspaces.create_invitation(workspace, owner, "UPPER@EXAMPLE.COM", "member")

      assert invitation.email == "upper@example.com"
    end

    test "returns error when email is already a workspace member" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      member = user_fixture()
      _membership = workspace_membership_fixture(workspace, member, "member")

      assert {:error, :already_member} =
               Workspaces.create_invitation(workspace, owner, member.email, "member")
    end

    test "returns error when email is already a member (case-insensitive)" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      member = user_fixture()
      _membership = workspace_membership_fixture(workspace, member, "member")

      assert {:error, :already_member} =
               Workspaces.create_invitation(
                 workspace,
                 owner,
                 String.upcase(member.email),
                 "member"
               )
    end

    test "returns error when pending invitation already exists" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      email = unique_user_email()

      {:ok, _} = Workspaces.create_invitation(workspace, owner, email, "member")

      assert {:error, :already_invited} =
               Workspaces.create_invitation(workspace, owner, email, "admin")
    end

    test "returns error when pending invitation already exists (case-insensitive)" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      email = unique_user_email()

      {:ok, _} = Workspaces.create_invitation(workspace, owner, email, "member")

      assert {:error, :already_invited} =
               Workspaces.create_invitation(workspace, owner, String.upcase(email), "admin")
    end

    test "preloads workspace and invited_by on created invitation" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      email = unique_user_email()

      {:ok, invitation} = Workspaces.create_invitation(workspace, owner, email, "member")
      assert invitation.workspace.id == workspace.id
      assert invitation.invited_by.id == owner.id
    end
  end

  describe "get_invitation_by_token/1" do
    test "returns invitation for valid token" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      email = unique_user_email()

      {token, _invitation} = create_invitation_with_token(workspace, owner, email)

      assert {:ok, invitation} = Workspaces.get_invitation_by_token(token)
      assert invitation.email == String.downcase(email)
    end

    test "preloads workspace and invited_by" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      email = unique_user_email()

      {token, _invitation} = create_invitation_with_token(workspace, owner, email)

      {:ok, invitation} = Workspaces.get_invitation_by_token(token)
      assert invitation.workspace.id == workspace.id
      assert invitation.invited_by.id == owner.id
    end

    test "returns error for invalid base64 token" do
      assert {:error, :invalid_token} = Workspaces.get_invitation_by_token("not-valid!!!")
    end

    test "returns error for token not matching any invitation" do
      fake_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      assert {:error, :invalid_token} = Workspaces.get_invitation_by_token(fake_token)
    end

    test "returns error for expired invitation token" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {encoded_token, invitation} =
        WorkspaceInvitation.build_invitation(workspace, owner, "expired@example.com")

      expired_invitation = %{invitation | expires_at: expired_datetime()}
      {:ok, _} = Repo.insert(expired_invitation)

      assert {:error, :invalid_token} = Workspaces.get_invitation_by_token(encoded_token)
    end

    test "returns error for already accepted invitation token" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {encoded_token, invitation} =
        WorkspaceInvitation.build_invitation(workspace, owner, "accepted@example.com")

      accepted_invitation = %{invitation | accepted_at: DateTime.utc_now(:second)}
      {:ok, _} = Repo.insert(accepted_invitation)

      assert {:error, :invalid_token} = Workspaces.get_invitation_by_token(encoded_token)
    end
  end

  describe "accept_invitation/2" do
    test "creates membership for the invited user" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      invitee = user_fixture()

      {:ok, invitation} =
        Workspaces.create_invitation(workspace, owner, invitee.email, "admin")

      assert {:ok, membership} = Workspaces.accept_invitation(invitation, invitee)
      assert %WorkspaceMembership{} = membership
      assert membership.user_id == invitee.id
      assert membership.workspace_id == workspace.id
      assert membership.role == "admin"
    end

    test "marks invitation as accepted" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      invitee = user_fixture()

      {:ok, invitation} =
        Workspaces.create_invitation(workspace, owner, invitee.email, "member")

      {:ok, _membership} = Workspaces.accept_invitation(invitation, invitee)

      # Invitation should no longer appear in pending list
      assert Workspaces.list_pending_invitations(workspace.id) == []
    end

    test "returns error when invitation is already accepted" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      invitee = user_fixture()

      {token, _inv} = create_invitation_with_token(workspace, owner, invitee.email)
      {:ok, invitation} = Workspaces.get_invitation_by_token(token)

      {:ok, _membership} = Workspaces.accept_invitation(invitation, invitee)

      # Reload the invitation to get the updated accepted_at
      updated_invitation = Repo.get!(WorkspaceInvitation, invitation.id)

      assert {:error, :already_accepted} =
               Workspaces.accept_invitation(updated_invitation, invitee)
    end

    test "returns error when invitation has expired" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      invitee = user_fixture()

      {_token, invitation} =
        WorkspaceInvitation.build_invitation(workspace, owner, invitee.email)

      expired_invitation = %{invitation | expires_at: expired_datetime()}
      {:ok, expired_invitation} = Repo.insert(expired_invitation)

      assert {:error, :expired} = Workspaces.accept_invitation(expired_invitation, invitee)
    end

    test "returns error when user email does not match invitation email" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      wrong_user = user_fixture()

      {:ok, invitation} =
        Workspaces.create_invitation(workspace, owner, "someone-else@example.com", "member")

      assert {:error, :email_mismatch} = Workspaces.accept_invitation(invitation, wrong_user)
    end

    test "returns error when user is already a member" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      member = user_fixture()

      # Create invitation, then add member directly (simulating race condition)
      {token, _inv} = create_invitation_with_token(workspace, owner, member.email)
      _membership = workspace_membership_fixture(workspace, member, "viewer")

      {:ok, invitation} = Workspaces.get_invitation_by_token(token)
      assert {:error, :already_member} = Workspaces.accept_invitation(invitation, member)
    end
  end

  describe "revoke_invitation/1" do
    test "deletes the invitation" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      email = unique_user_email()

      {:ok, invitation} = Workspaces.create_invitation(workspace, owner, email, "member")

      assert {:ok, _deleted} = Workspaces.revoke_invitation(invitation)
      assert Workspaces.list_pending_invitations(workspace.id) == []
    end
  end

  describe "get_pending_invitation/1" do
    test "returns pending invitation by ID" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {:ok, invitation} =
        Workspaces.create_invitation(workspace, owner, unique_user_email(), "member")

      result = Workspaces.get_pending_invitation(invitation.id)
      assert result != nil
      assert result.id == invitation.id
    end

    test "returns nil for accepted invitation" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {_token, invitation} =
        create_invitation_with_token(workspace, owner, unique_user_email())

      invitation
      |> Ecto.Changeset.change(accepted_at: DateTime.utc_now(:second))
      |> Repo.update!()

      assert Workspaces.get_pending_invitation(invitation.id) == nil
    end

    test "returns nil for expired invitation" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {_encoded_token, invitation} =
        WorkspaceInvitation.build_invitation(workspace, owner, "expired@example.com")

      expired_invitation = %{invitation | expires_at: expired_datetime()}
      {:ok, expired_invitation} = Repo.insert(expired_invitation)

      assert Workspaces.get_pending_invitation(expired_invitation.id) == nil
    end

    test "returns nil for non-existent ID" do
      assert Workspaces.get_pending_invitation(999_999) == nil
    end
  end
end
