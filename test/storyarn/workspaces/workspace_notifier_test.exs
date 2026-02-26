defmodule Storyarn.Workspaces.WorkspaceNotifierTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Workspaces.{WorkspaceInvitation, WorkspaceNotifier}

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  describe "deliver_invitation/2" do
    setup do
      owner = user_fixture()
      workspace = workspace_fixture(owner, %{name: "Test Workspace"})

      {encoded_token, invitation_struct} =
        WorkspaceInvitation.build_invitation(workspace, owner, "invitee@example.com", "member")

      {:ok, invitation} = Repo.insert(invitation_struct)
      invitation = Repo.preload(invitation, [:workspace, :invited_by])

      %{
        invitation: invitation,
        encoded_token: encoded_token,
        owner: owner,
        workspace: workspace
      }
    end

    test "delivers email to the invited address", %{
      invitation: invitation,
      encoded_token: encoded_token
    } do
      assert {:ok, email} = WorkspaceNotifier.deliver_invitation(invitation, encoded_token)
      assert email.to == [{"", "invitee@example.com"}]
    end

    test "sets the correct from address", %{
      invitation: invitation,
      encoded_token: encoded_token
    } do
      {:ok, email} = WorkspaceNotifier.deliver_invitation(invitation, encoded_token)
      assert {"Storyarn", "noreply@storyarn.com"} = email.from
    end

    test "includes workspace name in subject", %{
      invitation: invitation,
      encoded_token: encoded_token
    } do
      {:ok, email} = WorkspaceNotifier.deliver_invitation(invitation, encoded_token)
      assert email.subject =~ "Test Workspace"
    end

    test "includes invitation URL with token in body", %{
      invitation: invitation,
      encoded_token: encoded_token
    } do
      {:ok, email} = WorkspaceNotifier.deliver_invitation(invitation, encoded_token)
      assert email.text_body =~ "/workspaces/invitations/#{encoded_token}"
    end

    test "includes workspace name in body", %{
      invitation: invitation,
      encoded_token: encoded_token
    } do
      {:ok, email} = WorkspaceNotifier.deliver_invitation(invitation, encoded_token)
      assert email.text_body =~ "Test Workspace"
    end

    test "includes the role in body", %{
      invitation: invitation,
      encoded_token: encoded_token
    } do
      {:ok, email} = WorkspaceNotifier.deliver_invitation(invitation, encoded_token)
      assert email.text_body =~ "member"
    end

    test "includes inviter name in body when display_name is set", %{
      invitation: invitation,
      encoded_token: encoded_token,
      owner: owner
    } do
      # Set display_name on the owner
      {:ok, owner_with_name} =
        owner
        |> Ecto.Changeset.change(display_name: "John Doe")
        |> Repo.update()

      invitation = %{invitation | invited_by: owner_with_name}

      {:ok, email} = WorkspaceNotifier.deliver_invitation(invitation, encoded_token)
      assert email.text_body =~ "John Doe"
    end

    test "falls back to email when display_name is nil", %{
      invitation: invitation,
      encoded_token: encoded_token,
      owner: owner
    } do
      {:ok, email} = WorkspaceNotifier.deliver_invitation(invitation, encoded_token)
      assert email.text_body =~ owner.email
    end

    test "includes expiration days in body", %{
      invitation: invitation,
      encoded_token: encoded_token
    } do
      {:ok, email} = WorkspaceNotifier.deliver_invitation(invitation, encoded_token)
      days = WorkspaceInvitation.validity_in_days()
      assert email.text_body =~ "#{days} days"
    end

    test "returns ok tuple with Swoosh email struct", %{
      invitation: invitation,
      encoded_token: encoded_token
    } do
      assert {:ok, %Swoosh.Email{} = email} =
               WorkspaceNotifier.deliver_invitation(invitation, encoded_token)

      # Verify it is a complete email with all required fields
      assert email.to != []
      assert email.from != nil
      assert email.subject != nil
      assert email.text_body != nil
    end
  end
end
