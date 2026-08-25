defmodule Storyarn.Workspaces.Invitations.Delivery.HandlerTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Invitations.Tokens.Issuer

  describe "deliver_invitation_email/2" do
    setup do
      owner = user_fixture()
      workspace = workspace_fixture(owner, %{name: "Test Workspace"})

      {encoded_token, invitation_struct} =
        Issuer.issue(workspace, owner, "invitee@example.com", "member")

      Repo.insert!(invitation_struct)

      %{encoded_token: encoded_token, owner: owner}
    end

    test "delivers the Workspace-owned invitation content", %{
      encoded_token: encoded_token
    } do
      assert {:ok, email} = Workspaces.deliver_invitation_email(encoded_token)

      assert email.to == [{"", "invitee@example.com"}]
      assert email.from == {"Storyarn", "noreply@storyarn.com"}
      assert email.subject =~ "Test Workspace"
      assert email.text_body =~ "workspace"
      assert email.text_body =~ "member"
      assert email.text_body =~ "/workspaces/invitations/#{encoded_token}"
      assert email.text_body =~ "7 days"
    end

    test "uses the inviter display name when available", %{
      encoded_token: encoded_token,
      owner: owner
    } do
      owner |> Ecto.Changeset.change(display_name: "John Doe") |> Repo.update!()

      assert {:ok, email} = Workspaces.deliver_invitation_email(encoded_token)
      assert email.text_body =~ "John Doe"
    end

    test "falls back to the inviter email", %{encoded_token: encoded_token, owner: owner} do
      assert {:ok, email} = Workspaces.deliver_invitation_email(encoded_token)
      assert email.text_body =~ owner.email
    end

    test "accepts an explicit inviter name", %{encoded_token: encoded_token} do
      assert {:ok, email} =
               Workspaces.deliver_invitation_email(encoded_token,
                 inviter_name: "Storyarn Support"
               )

      assert email.text_body =~ "Storyarn Support"
    end
  end
end
