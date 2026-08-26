defmodule Storyarn.Projects.InvitationNotifierTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects.InvitationNotifier
  alias Storyarn.Projects.ProjectInvitation

  describe "deliver_invitation/3" do
    setup do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Test Project"})

      {encoded_token, invitation_struct} =
        ProjectInvitation.build_invitation(project, owner, "invitee@example.com", "viewer")

      invitation =
        invitation_struct
        |> Repo.insert!()
        |> Repo.preload([:project, :invited_by])

      url = "http://localhost:4000/projects/invitations/#{encoded_token}"

      %{invitation: invitation, url: url, encoded_token: encoded_token, owner: owner}
    end

    test "delivers the Project-owned invitation content", %{
      invitation: invitation,
      url: url,
      encoded_token: encoded_token
    } do
      assert {:ok, email} = InvitationNotifier.deliver_invitation(invitation, url)

      assert email.to == [{"", "invitee@example.com"}]
      assert email.from == {"Storyarn", "noreply@storyarn.com"}
      assert email.subject =~ "Test Project"
      assert email.text_body =~ ~s(join "Test Project")
      assert email.text_body =~ "viewer"
      assert email.text_body =~ "/projects/invitations/#{encoded_token}"
      assert email.text_body =~ "7 days"
    end

    test "uses the inviter identity from the Project invitation", %{
      invitation: invitation,
      url: url,
      owner: owner
    } do
      owner = owner |> Ecto.Changeset.change(display_name: "Project Owner") |> Repo.update!()
      invitation = %{invitation | invited_by: owner}

      assert {:ok, email} = InvitationNotifier.deliver_invitation(invitation, url)
      assert email.text_body =~ "Project Owner"
    end

    test "defaults admin-created invitations to the Storyarn identity", %{
      invitation: invitation,
      url: url
    } do
      invitation = %{invitation | invited_by: nil}

      assert {:ok, email} = InvitationNotifier.deliver_invitation(invitation, url)
      assert email.text_body =~ "Storyarn has invited you"
    end
  end
end
