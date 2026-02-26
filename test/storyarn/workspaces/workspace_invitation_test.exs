defmodule Storyarn.Workspaces.WorkspaceInvitationTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Workspaces.WorkspaceInvitation

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  describe "changeset/2" do
    setup do
      user = user_fixture()
      workspace = workspace_fixture(user)
      %{workspace: workspace, user: user}
    end

    test "valid changeset with all required fields", %{workspace: workspace, user: user} do
      attrs = %{
        email: "invitee@example.com",
        role: "member",
        workspace_id: workspace.id,
        invited_by_id: user.id
      }

      changeset = WorkspaceInvitation.changeset(%WorkspaceInvitation{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset without required fields" do
      changeset = WorkspaceInvitation.changeset(%WorkspaceInvitation{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert "can't be blank" in errors.email
      assert "can't be blank" in errors.workspace_id
      assert "can't be blank" in errors.invited_by_id
    end

    test "role defaults to member" do
      changeset =
        WorkspaceInvitation.changeset(%WorkspaceInvitation{}, %{
          email: "test@example.com",
          workspace_id: 1,
          invited_by_id: 1
        })

      # role has a schema default of "member", so it should be valid without providing it
      assert changeset.valid?
    end

    test "invalid changeset with bad email format", %{workspace: workspace, user: user} do
      attrs = %{
        email: "not-an-email",
        role: "member",
        workspace_id: workspace.id,
        invited_by_id: user.id
      }

      changeset = WorkspaceInvitation.changeset(%WorkspaceInvitation{}, attrs)
      refute changeset.valid?
      assert "must have the @ sign and no spaces" in errors_on(changeset).email
    end

    test "invalid changeset with invalid role", %{workspace: workspace, user: user} do
      attrs = %{
        email: "invitee@example.com",
        role: "superadmin",
        workspace_id: workspace.id,
        invited_by_id: user.id
      }

      changeset = WorkspaceInvitation.changeset(%WorkspaceInvitation{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).role
    end

    test "accepts valid roles", %{workspace: workspace, user: user} do
      for role <- ~w(admin member viewer) do
        attrs = %{
          email: "invitee@example.com",
          role: role,
          workspace_id: workspace.id,
          invited_by_id: user.id
        }

        changeset = WorkspaceInvitation.changeset(%WorkspaceInvitation{}, attrs)
        assert changeset.valid?, "expected role #{role} to be valid"
      end
    end
  end

  describe "build_invitation/4" do
    setup do
      user = user_fixture()
      workspace = workspace_fixture(user)
      %{workspace: workspace, user: user}
    end

    test "returns encoded token and invitation struct", %{workspace: workspace, user: user} do
      {encoded_token, invitation} =
        WorkspaceInvitation.build_invitation(workspace, user, "invitee@example.com")

      assert is_binary(encoded_token)
      assert %WorkspaceInvitation{} = invitation
      assert invitation.workspace_id == workspace.id
      assert invitation.invited_by_id == user.id
      assert invitation.email == "invitee@example.com"
      assert invitation.role == "member"
      assert invitation.token != nil
      assert invitation.expires_at != nil
    end

    test "downcases email", %{workspace: workspace, user: user} do
      {_token, invitation} =
        WorkspaceInvitation.build_invitation(workspace, user, "UPPER@EXAMPLE.COM")

      assert invitation.email == "upper@example.com"
    end

    test "accepts custom role", %{workspace: workspace, user: user} do
      {_token, invitation} =
        WorkspaceInvitation.build_invitation(workspace, user, "invitee@example.com", "admin")

      assert invitation.role == "admin"
    end

    test "sets expiration 7 days in the future", %{workspace: workspace, user: user} do
      {_token, invitation} =
        WorkspaceInvitation.build_invitation(workspace, user, "invitee@example.com")

      now = DateTime.utc_now()
      # Should be roughly 7 days from now (within a minute tolerance)
      diff = DateTime.diff(invitation.expires_at, now, :second)
      expected_seconds = 7 * 24 * 60 * 60
      assert_in_delta diff, expected_seconds, 60
    end

    test "generates unique tokens for each call", %{workspace: workspace, user: user} do
      {token1, invitation1} =
        WorkspaceInvitation.build_invitation(workspace, user, "a@example.com")

      {token2, invitation2} =
        WorkspaceInvitation.build_invitation(workspace, user, "b@example.com")

      refute token1 == token2
      refute invitation1.token == invitation2.token
    end
  end

  describe "verify_token_query/1" do
    setup do
      user = user_fixture()
      workspace = workspace_fixture(user)
      %{workspace: workspace, user: user}
    end

    test "returns query for valid token", %{workspace: workspace, user: user} do
      {encoded_token, invitation} =
        WorkspaceInvitation.build_invitation(workspace, user, "invitee@example.com")

      {:ok, _inserted} = Repo.insert(invitation)

      assert {:ok, query} = WorkspaceInvitation.verify_token_query(encoded_token)
      assert %Ecto.Query{} = query

      result = Repo.one(query)
      assert result != nil
      assert result.email == "invitee@example.com"
    end

    test "returns error for invalid base64 token" do
      assert :error = WorkspaceInvitation.verify_token_query("not valid base64!!!")
    end

    test "returns ok with query but no result for non-existent token" do
      # A valid base64 token that doesn't match any invitation
      fake_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      assert {:ok, query} = WorkspaceInvitation.verify_token_query(fake_token)
      assert Repo.one(query) == nil
    end

    test "does not find expired invitations", %{workspace: workspace, user: user} do
      {encoded_token, invitation} =
        WorkspaceInvitation.build_invitation(workspace, user, "invitee@example.com")

      # Insert with an already-expired date
      expired_at =
        DateTime.utc_now()
        |> DateTime.add(-1, :day)
        |> DateTime.truncate(:second)

      expired_invitation = %{invitation | expires_at: expired_at}
      {:ok, _inserted} = Repo.insert(expired_invitation)

      assert {:ok, query} = WorkspaceInvitation.verify_token_query(encoded_token)
      assert Repo.one(query) == nil
    end

    test "does not find already accepted invitations", %{workspace: workspace, user: user} do
      {encoded_token, invitation} =
        WorkspaceInvitation.build_invitation(workspace, user, "invitee@example.com")

      accepted_invitation = %{invitation | accepted_at: DateTime.utc_now(:second)}
      {:ok, _inserted} = Repo.insert(accepted_invitation)

      assert {:ok, query} = WorkspaceInvitation.verify_token_query(encoded_token)
      assert Repo.one(query) == nil
    end
  end

  describe "validity_in_days/0" do
    test "returns 7" do
      assert WorkspaceInvitation.validity_in_days() == 7
    end
  end
end
