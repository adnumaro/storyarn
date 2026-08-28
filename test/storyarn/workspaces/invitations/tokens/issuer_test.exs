defmodule Storyarn.Workspaces.Invitations.Tokens.IssuerTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Workspaces.Invitations.Tokens.Issuer
  alias Storyarn.Workspaces.WorkspaceInvitation

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)
    %{workspace: workspace, user: user}
  end

  test "issues an encoded token and invitation entity", %{workspace: workspace, user: user} do
    {encoded_token, invitation} = Issuer.issue(workspace, user, "invitee@example.com")

    assert is_binary(encoded_token)
    assert %WorkspaceInvitation{} = invitation
    assert invitation.workspace_id == workspace.id
    assert invitation.invited_by_id == user.id
    assert invitation.email == "invitee@example.com"
    assert invitation.role == "member"
    assert invitation.token
    assert invitation.expires_at
  end

  test "downcases email", %{workspace: workspace, user: user} do
    {_token, invitation} = Issuer.issue(workspace, user, "UPPER@EXAMPLE.COM")

    assert invitation.email == "upper@example.com"
  end

  test "accepts a custom role", %{workspace: workspace, user: user} do
    {_token, invitation} = Issuer.issue(workspace, user, "invitee@example.com", "admin")

    assert invitation.role == "admin"
  end

  test "sets expiration seven days in the future", %{workspace: workspace, user: user} do
    {_token, invitation} = Issuer.issue(workspace, user, "invitee@example.com")

    diff = DateTime.diff(invitation.expires_at, DateTime.utc_now(), :second)
    assert_in_delta diff, 7 * 24 * 60 * 60, 60
  end

  test "generates unique tokens", %{workspace: workspace, user: user} do
    {token1, invitation1} = Issuer.issue(workspace, user, "a@example.com")
    {token2, invitation2} = Issuer.issue(workspace, user, "b@example.com")

    refute token1 == token2
    refute invitation1.token == invitation2.token
  end
end
