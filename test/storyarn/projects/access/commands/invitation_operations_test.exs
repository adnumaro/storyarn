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

  test "keeps a committed invitation when its post-commit queue wakeup fails" do
    owner = user_fixture()
    project = project_fixture(owner)
    email = "project-wakeup-unavailable@example.com"
    test_process = self()

    assert {:ok, invitation} =
             Projects.create_admin_invitation(
               project,
               email,
               "editor",
               queue_notifier: fn payload ->
                 send(test_process, {:project_wakeup_attempted, payload})
                 {:error, :notifier_unavailable}
               end
             )

    assert_receive {:project_wakeup_attempted, %{queue: "invitation_delivery"}}
    assert invitation.email == email
    assert Repo.get_by(ProjectInvitation, project_id: project.id, email: email)
  end
end
