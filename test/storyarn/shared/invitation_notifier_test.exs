defmodule Storyarn.Shared.InvitationNotifierTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Shared.InvitationNotifier
  alias Storyarn.Workspaces.WorkspaceInvitation

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  @config %{
    invitation_schema: WorkspaceInvitation,
    parent_assoc: :workspace,
    template: :workspace_invitation
  }

  describe "deliver_invitation/4" do
    setup do
      owner = user_fixture()
      workspace = workspace_fixture(owner, %{name: "Test Workspace"})

      {encoded_token, invitation_struct} =
        WorkspaceInvitation.build_invitation(workspace, owner, "invitee@example.com", "member")

      {:ok, invitation} = Repo.insert(invitation_struct)
      invitation = Repo.preload(invitation, [:workspace, :invited_by])

      url = "http://localhost:4000/workspaces/invitations/#{encoded_token}"

      %{
        invitation: invitation,
        url: url,
        encoded_token: encoded_token,
        owner: owner,
        workspace: workspace
      }
    end

    test "delivers email to the invited address", %{invitation: invitation, url: url} do
      assert {:ok, email} = InvitationNotifier.deliver_invitation(@config, invitation, url)
      assert email.to == [{"", "invitee@example.com"}]
    end

    test "sets the correct from address", %{invitation: invitation, url: url} do
      {:ok, email} = InvitationNotifier.deliver_invitation(@config, invitation, url)
      assert {"Storyarn", "noreply@storyarn.com"} = email.from
    end

    test "includes entity name in subject", %{invitation: invitation, url: url} do
      {:ok, email} = InvitationNotifier.deliver_invitation(@config, invitation, url)
      assert email.subject =~ "Test Workspace"
    end

    test "includes invitation URL with token in body", %{
      invitation: invitation,
      url: url,
      encoded_token: encoded_token
    } do
      {:ok, email} = InvitationNotifier.deliver_invitation(@config, invitation, url)
      assert email.text_body =~ "/workspaces/invitations/#{encoded_token}"
    end

    test "includes entity name in body", %{invitation: invitation, url: url} do
      {:ok, email} = InvitationNotifier.deliver_invitation(@config, invitation, url)
      assert email.text_body =~ "Test Workspace"
    end

    test "includes the role in body", %{invitation: invitation, url: url} do
      {:ok, email} = InvitationNotifier.deliver_invitation(@config, invitation, url)
      assert email.text_body =~ "member"
    end

    test "includes inviter name in body when display_name is set", %{
      invitation: invitation,
      url: url,
      owner: owner
    } do
      {:ok, owner_with_name} =
        owner
        |> Ecto.Changeset.change(display_name: "John Doe")
        |> Repo.update()

      invitation = %{invitation | invited_by: owner_with_name}

      {:ok, email} = InvitationNotifier.deliver_invitation(@config, invitation, url)
      assert email.text_body =~ "John Doe"
    end

    test "falls back to email when display_name is nil", %{
      invitation: invitation,
      url: url,
      owner: owner
    } do
      {:ok, email} = InvitationNotifier.deliver_invitation(@config, invitation, url)
      assert email.text_body =~ owner.email
    end

    test "includes expiration days in body", %{invitation: invitation, url: url} do
      {:ok, email} = InvitationNotifier.deliver_invitation(@config, invitation, url)
      days = WorkspaceInvitation.validity_in_days()
      assert email.text_body =~ "#{days} days"
    end

    test "returns ok tuple with Swoosh email struct", %{invitation: invitation, url: url} do
      assert {:ok, %Swoosh.Email{} = email} =
               InvitationNotifier.deliver_invitation(@config, invitation, url)

      assert email.to != []
      assert email.from != nil
      assert email.subject != nil
      assert email.text_body != nil
    end
  end
end
