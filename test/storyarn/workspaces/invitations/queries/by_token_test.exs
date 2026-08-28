defmodule Storyarn.Workspaces.Invitations.Queries.ByTokenTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Workspaces.Invitations.Queries.ByToken
  alias Storyarn.Workspaces.Invitations.Tokens.Issuer

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)
    %{workspace: workspace, user: user}
  end

  test "returns a valid invitation with its associations", %{workspace: workspace, user: user} do
    {encoded_token, invitation} = Issuer.issue(workspace, user, "invitee@example.com")
    {:ok, _inserted} = Repo.insert(invitation)

    assert {:ok, result} = ByToken.get(encoded_token)
    assert result.email == "invitee@example.com"
    assert result.workspace.id == workspace.id
    assert result.invited_by.id == user.id
  end

  test "rejects invalid and unknown tokens" do
    assert {:error, :invalid_token} = ByToken.get("not valid base64!!!")

    unknown_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    assert {:error, :invalid_token} = ByToken.get(unknown_token)
  end

  test "does not return expired invitations", %{workspace: workspace, user: user} do
    {encoded_token, invitation} = Issuer.issue(workspace, user, "invitee@example.com")

    expired_at =
      DateTime.utc_now()
      |> DateTime.add(-1, :day)
      |> DateTime.truncate(:second)

    {:ok, _inserted} = Repo.insert(%{invitation | expires_at: expired_at})

    assert {:error, :invalid_token} = ByToken.get(encoded_token)
  end

  test "does not return accepted invitations", %{workspace: workspace, user: user} do
    {encoded_token, invitation} = Issuer.issue(workspace, user, "invitee@example.com")
    {:ok, _inserted} = Repo.insert(%{invitation | accepted_at: DateTime.utc_now(:second)})

    assert {:error, :invalid_token} = ByToken.get(encoded_token)
  end
end
