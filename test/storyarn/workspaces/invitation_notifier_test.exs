defmodule Storyarn.Workspaces.InvitationNotifierTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Workspaces.InvitationNotifier
  alias Storyarn.Workspaces.WorkspaceInvitation

  describe "deliver_invitation/3" do
    setup do
      owner = user_fixture()
      workspace = workspace_fixture(owner, %{name: "Test Workspace"})

      {encoded_token, invitation_struct} =
        WorkspaceInvitation.build_invitation(workspace, owner, "invitee@example.com", "member")

      invitation =
        invitation_struct
        |> Repo.insert!()
        |> Repo.preload([:workspace, :invited_by])

      url = "http://localhost:4000/workspaces/invitations/#{encoded_token}"

      %{invitation: invitation, url: url, encoded_token: encoded_token, owner: owner}
    end

    test "delivers the Workspace-owned invitation content", %{
      invitation: invitation,
      url: url,
      encoded_token: encoded_token
    } do
      assert {:ok, email} = InvitationNotifier.deliver_invitation(invitation, url)

      assert email.to == [{"", "invitee@example.com"}]
      assert email.from == {"Storyarn", "noreply@storyarn.com"}
      assert email.subject =~ "Test Workspace"
      assert email.text_body =~ "workspace"
      assert email.text_body =~ "member"
      assert email.text_body =~ "/workspaces/invitations/#{encoded_token}"
      assert email.text_body =~ "7 days"
    end

    test "uses the inviter display name when available", %{
      invitation: invitation,
      url: url,
      owner: owner
    } do
      owner = owner |> Ecto.Changeset.change(display_name: "John Doe") |> Repo.update!()
      invitation = %{invitation | invited_by: owner}

      assert {:ok, email} = InvitationNotifier.deliver_invitation(invitation, url)
      assert email.text_body =~ "John Doe"
    end

    test "falls back to the inviter email", %{invitation: invitation, url: url, owner: owner} do
      assert {:ok, email} = InvitationNotifier.deliver_invitation(invitation, url)
      assert email.text_body =~ owner.email
    end

    test "accepts an explicit inviter for admin-created invitations", %{
      invitation: invitation,
      url: url
    } do
      invitation = %{invitation | invited_by: nil}

      assert {:ok, email} =
               InvitationNotifier.deliver_invitation(invitation, url, inviter_name: "Storyarn Support")

      assert email.text_body =~ "Storyarn Support"
    end
  end
end
