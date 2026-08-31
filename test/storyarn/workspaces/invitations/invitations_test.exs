defmodule Storyarn.Workspaces.InvitationsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Invitations.Commands.Revoke
  alias Storyarn.Workspaces.Invitations.Tokens.Issuer
  alias Storyarn.Workspaces.WorkspaceInvitation
  alias Storyarn.Workspaces.WorkspaceMembership

  # --------------------------------------------------------------------------
  # Helpers
  # --------------------------------------------------------------------------

  defp create_invitation_with_token(workspace, invited_by, email, role \\ "member") do
    {encoded_token, invitation} =
      Issuer.issue(workspace, invited_by, email, role)

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
        Workspaces.create_invitation(%{user: owner}, workspace.id, "invitee@example.com", "member")

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
        Issuer.issue(workspace, owner, "expired@example.com")

      expired_invitation = %{invitation | expires_at: expired_datetime()}
      {:ok, _} = Repo.insert(expired_invitation)

      assert Workspaces.list_pending_invitations(workspace.id) == []
    end

    test "preloads invited_by association" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {:ok, _invitation} =
        Workspaces.create_invitation(%{user: owner}, workspace.id, "invitee@example.com", "member")

      [invitation] = Workspaces.list_pending_invitations(workspace.id)
      assert invitation.invited_by.id == owner.id
    end

    test "a pending invitation reserves the remaining plan seat" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {:ok, _inv1} =
        Workspaces.create_invitation(%{user: owner}, workspace.id, "first@example.com", "member")

      assert {:error, :limit_reached, %{resource: :members_per_workspace, used: 2, limit: 2}} =
               Workspaces.create_invitation(%{user: owner}, workspace.id, "second@example.com", "member")

      invitations = Workspaces.list_pending_invitations(workspace.id)
      assert Enum.map(invitations, & &1.email) == ["first@example.com"]
    end
  end

  describe "billing limits" do
    test "create_invitation returns limit_reached when member limit reached" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      # Add a second member to reach the limit of 2
      other_user = user_fixture()
      _membership = workspace_membership_fixture(workspace, other_user)

      email = unique_user_email()

      assert {:error, :limit_reached, %{resource: :members_per_workspace}} =
               Workspaces.create_invitation(%{user: owner}, workspace.id, email, "member")
    end
  end

  describe "create_invitation/4" do
    test "creates invitation and returns it" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      email = unique_user_email()

      assert {:ok, invitation} = Workspaces.create_invitation(%{user: owner}, workspace.id, email, "admin")
      assert invitation.email == String.downcase(email)
      assert invitation.role == "admin"
      assert invitation.workspace_id == workspace.id
      assert invitation.invited_by_id == owner.id
    end

    test "allows an admin through authorization and reaches capacity policy" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      admin = user_fixture()
      _membership = workspace_membership_fixture(workspace, admin, "admin")

      assert {:error, :limit_reached, %{resource: :members_per_workspace, used: 2, limit: 2}} =
               Workspaces.create_invitation(
                 %{user: admin},
                 workspace.id,
                 unique_user_email(),
                 "member"
               )

      assert Workspaces.get_membership(workspace.id, owner.id).role == "owner"
    end

    test "rejects a current member without manage-members authority" do
      %{workspace: workspace} = create_workspace_and_owner()
      member = user_fixture()
      _membership = workspace_membership_fixture(workspace, member, "member")
      email = unique_user_email()

      assert {:error, :unauthorized} =
               Workspaces.create_invitation(%{user: member}, workspace.id, email, "viewer")

      refute Repo.get_by(WorkspaceInvitation, workspace_id: workspace.id, email: email)
    end

    test "fails closed when canonical workspace ownership is ambiguous" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      duplicate_owner = user_fixture()

      %WorkspaceMembership{}
      |> WorkspaceMembership.changeset(%{
        workspace_id: workspace.id,
        user_id: duplicate_owner.id,
        role: "owner"
      })
      |> Repo.insert!()

      email = unique_user_email()

      assert {:error, :ownership_invariant_violation} =
               Workspaces.create_invitation(%{user: owner}, workspace.id, email, "member")

      refute Repo.get_by(WorkspaceInvitation, workspace_id: workspace.id, email: email)
    end

    test "defaults to member role" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      email = unique_user_email()

      assert {:ok, invitation} = Workspaces.create_invitation(%{user: owner}, workspace.id, email)
      assert invitation.role == "member"
    end

    test "downcases email" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      assert {:ok, invitation} =
               Workspaces.create_invitation(%{user: owner}, workspace.id, "UPPER@EXAMPLE.COM", "member")

      assert invitation.email == "upper@example.com"
    end

    test "returns error when email is already a workspace member" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      member = user_fixture()
      _membership = workspace_membership_fixture(workspace, member, "member")

      assert {:error, :already_member} =
               Workspaces.create_invitation(%{user: owner}, workspace.id, member.email, "member")
    end

    test "returns error when email is already a member (case-insensitive)" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      member = user_fixture()
      _membership = workspace_membership_fixture(workspace, member, "member")

      assert {:error, :already_member} =
               Workspaces.create_invitation(
                 %{user: owner},
                 workspace.id,
                 String.upcase(member.email),
                 "member"
               )
    end

    test "returns error when pending invitation already exists" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      email = unique_user_email()

      {:ok, _} = Workspaces.create_invitation(%{user: owner}, workspace.id, email, "member")

      assert {:error, :already_invited} =
               Workspaces.create_invitation(%{user: owner}, workspace.id, email, "admin")
    end

    test "returns error when pending invitation already exists (case-insensitive)" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      email = unique_user_email()

      {:ok, _} = Workspaces.create_invitation(%{user: owner}, workspace.id, email, "member")

      assert {:error, :already_invited} =
               Workspaces.create_invitation(%{user: owner}, workspace.id, String.upcase(email), "admin")
    end

    test "stale revoke and accept calls return errors instead of raising" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      invitee = user_fixture()

      assert {:ok, invitation} =
               Workspaces.create_invitation(%{user: owner}, workspace.id, invitee.email, "member")

      assert {:ok, _invitation} =
               Workspaces.revoke_invitation(%{user: owner}, workspace.id, invitation.id)

      assert {:error, :not_found} =
               Workspaces.revoke_invitation(%{user: owner}, workspace.id, invitation.id)

      assert {:error, accept_changeset} =
               Workspaces.accept_invitation(invitation, invitee)

      assert errors_on(accept_changeset).id
    end

    test "hard-deleted workspaces return errors for stale create and accept calls" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      invitee = user_fixture()

      assert {:ok, invitation} =
               Workspaces.create_invitation(%{user: owner}, workspace.id, invitee.email, "member")

      Repo.delete!(workspace)

      assert {:error, :not_found} =
               Workspaces.create_invitation(
                 %{user: owner},
                 workspace.id,
                 "after-delete@example.com",
                 "member"
               )

      assert {:error, :invitation_unavailable} =
               Workspaces.accept_invitation(invitation, invitee)
    end

    test "preloads workspace and invited_by on created invitation" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      email = unique_user_email()

      {:ok, invitation} = Workspaces.create_invitation(%{user: owner}, workspace.id, email, "member")
      assert invitation.workspace.id == workspace.id
      assert invitation.invited_by.id == owner.id
    end

    test "renews an expired invitation for the same email" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      email = "renew-expired@example.com"

      {old_token, invitation} =
        Issuer.issue(workspace, owner, email)

      expired_invitation = %{invitation | expires_at: expired_datetime()}
      expired_invitation = Repo.insert!(expired_invitation)

      assert {:ok, renewed_invitation} =
               Workspaces.create_invitation(%{user: owner}, workspace.id, email, "admin")

      refute renewed_invitation.id == expired_invitation.id
      assert renewed_invitation.role == "admin"
      assert is_nil(renewed_invitation.accepted_at)
      assert DateTime.after?(renewed_invitation.expires_at, DateTime.utc_now(:second))
      refute renewed_invitation.token == expired_invitation.token
      assert {:error, :invalid_token} = Workspaces.get_invitation_by_token(old_token)
    end

    test "renews an accepted invitation after the former member is removed" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      invitee = user_fixture()

      assert {:ok, invitation} =
               Workspaces.create_invitation(%{user: owner}, workspace.id, invitee.email, "member")

      assert {:ok, membership} = Workspaces.accept_invitation(invitation, invitee)
      Repo.delete!(membership)

      assert {:ok, renewed_invitation} =
               Workspaces.create_invitation(%{user: owner}, workspace.id, invitee.email, "viewer")

      refute renewed_invitation.id == invitation.id
      assert renewed_invitation.role == "viewer"
      assert is_nil(renewed_invitation.accepted_at)
    end

    test "normalizes emails and rejects invalid roles in context calls" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      assert {:ok, invitation} =
               Workspaces.create_invitation(
                 %{user: owner},
                 workspace.id,
                 "  MIXED@example.com  ",
                 "member"
               )

      assert invitation.email == "mixed@example.com"

      assert {:error, changeset} =
               Workspaces.create_invitation(
                 %{user: owner},
                 workspace.id,
                 "invalid-role@example.com",
                 "owner"
               )

      assert "is invalid" in errors_on(changeset).role
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
        Issuer.issue(workspace, owner, "expired@example.com")

      expired_invitation = %{invitation | expires_at: expired_datetime()}
      {:ok, _} = Repo.insert(expired_invitation)

      assert {:error, :invalid_token} = Workspaces.get_invitation_by_token(encoded_token)
    end

    test "returns error for already accepted invitation token" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {encoded_token, invitation} =
        Issuer.issue(workspace, owner, "accepted@example.com")

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
        Workspaces.create_invitation(%{user: owner}, workspace.id, invitee.email, "admin")

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
        Workspaces.create_invitation(%{user: owner}, workspace.id, invitee.email, "member")

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
        Issuer.issue(workspace, owner, invitee.email)

      expired_invitation = %{invitation | expires_at: expired_datetime()}
      {:ok, expired_invitation} = Repo.insert(expired_invitation)

      assert {:error, :expired} = Workspaces.accept_invitation(expired_invitation, invitee)
    end

    test "returns error when user email does not match invitation email" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      wrong_user = user_fixture()

      {:ok, invitation} =
        Workspaces.create_invitation(%{user: owner}, workspace.id, "someone-else@example.com", "member")

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

  describe "revoke_invitation/3" do
    test "deletes the invitation" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      email = unique_user_email()

      {:ok, invitation} = Workspaces.create_invitation(%{user: owner}, workspace.id, email, "member")

      assert {:ok, _deleted} =
               Workspaces.revoke_invitation(%{user: owner}, workspace.id, invitation.id)

      assert Workspaces.list_pending_invitations(workspace.id) == []
    end

    test "rejects an actor who no longer has manage-members authority" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {:ok, invitation} =
        Workspaces.create_invitation(%{user: owner}, workspace.id, unique_user_email(), "member")

      former_admin = user_fixture()
      membership = workspace_membership_fixture(workspace, former_admin, "admin")

      Repo.delete!(membership)

      assert {:error, :unauthorized} =
               Workspaces.revoke_invitation(
                 %{user: former_admin},
                 workspace.id,
                 invitation.id
               )

      assert Repo.get!(WorkspaceInvitation, invitation.id)
    end

    test "scopes the invitation identity to the authorized workspace" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()
      other_owner = user_fixture()
      other_workspace = workspace_fixture(other_owner)

      {:ok, invitation} =
        Workspaces.create_invitation(
          %{user: other_owner},
          other_workspace.id,
          unique_user_email(),
          "member"
        )

      assert {:error, :not_found} =
               Workspaces.revoke_invitation(%{user: owner}, workspace.id, invitation.id)

      assert Repo.get!(WorkspaceInvitation, invitation.id)
    end

    test "rolls the deletion back when a later revoke step fails" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {:ok, invitation} =
        Workspaces.create_invitation(%{user: owner}, workspace.id, unique_user_email(), "member")

      assert {:error, :forced_failure} =
               Revoke.execute(
                 %{user: owner},
                 workspace.id,
                 invitation.id,
                 after_delete: fn -> {:error, :forced_failure} end
               )

      assert Repo.get!(WorkspaceInvitation, invitation.id)
    end
  end

  describe "post-commit delivery wakeup" do
    test "keeps a committed invitation when the queue signal fails" do
      %{workspace: workspace} = create_workspace_and_owner()
      email = "workspace-wakeup-unavailable@example.com"
      test_process = self()

      assert {:ok, invitation} =
               Workspaces.create_admin_invitation(
                 workspace,
                 email,
                 "member",
                 queue_notifier: fn payload ->
                   send(test_process, {:workspace_wakeup_attempted, payload})
                   {:error, :notifier_unavailable}
                 end
               )

      assert_receive {:workspace_wakeup_attempted, %{queue: "invitation_delivery"}}
      assert invitation.email == email
      assert Repo.get_by(WorkspaceInvitation, workspace_id: workspace.id, email: email)
    end
  end

  describe "get_pending_invitation/1" do
    test "returns pending invitation by ID" do
      %{owner: owner, workspace: workspace} = create_workspace_and_owner()

      {:ok, invitation} =
        Workspaces.create_invitation(%{user: owner}, workspace.id, unique_user_email(), "member")

      result = Workspaces.get_pending_invitation(invitation.id)
      assert result
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
        Issuer.issue(workspace, owner, "expired@example.com")

      expired_invitation = %{invitation | expires_at: expired_datetime()}
      {:ok, expired_invitation} = Repo.insert(expired_invitation)

      assert Workspaces.get_pending_invitation(expired_invitation.id) == nil
    end

    test "returns nil for non-existent ID" do
      assert Workspaces.get_pending_invitation(999_999) == nil
    end
  end
end
