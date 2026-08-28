defmodule Storyarn.Workspaces.Invitations.Entities.InvitationTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Workspaces.WorkspaceInvitation

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
end
