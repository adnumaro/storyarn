defmodule Storyarn.Shared.InvitationOperationsTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects
  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.Repo

  test "rolls back invitation creation when token encryption is unavailable" do
    previous_encryptor = Application.get_env(:storyarn, :invitation_token_encryptor)

    on_exit(fn ->
      if previous_encryptor do
        Application.put_env(:storyarn, :invitation_token_encryptor, previous_encryptor)
      else
        Application.delete_env(:storyarn, :invitation_token_encryptor)
      end
    end)

    Application.put_env(
      :storyarn,
      :invitation_token_encryptor,
      Storyarn.FailingInvitationEncryptor
    )

    owner = user_fixture()
    project = project_fixture(owner)
    email = "encryption-unavailable@example.com"

    assert {:error, :encryption_unavailable} =
             Projects.create_invitation(project, owner, email, "editor")

    refute Repo.get_by(ProjectInvitation, project_id: project.id, email: email)
  end
end
