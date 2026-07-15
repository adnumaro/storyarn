defmodule Storyarn.Workers.DeliverInvitationWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Shared.EncryptedBinary
  alias Storyarn.Workers.DeliverInvitationWorker
  alias Storyarn.Workspaces

  setup do
    mailer_config = Application.get_env(:storyarn, Storyarn.Mailer)
    locale = Gettext.get_locale(Storyarn.Gettext)

    on_exit(fn ->
      Application.put_env(:storyarn, Storyarn.Mailer, mailer_config)
      Gettext.put_locale(Storyarn.Gettext, locale)
    end)

    :ok
  end

  test "queues an encrypted token and delivers in the invitation locale" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    Gettext.put_locale(Storyarn.Gettext, "es")

    assert {:ok, invitation} =
             Workspaces.create_admin_invitation(
               workspace,
               "invitee@example.com",
               "member",
               inviter_name: "Ada"
             )

    job = latest_job()
    encrypted_token = job.args["encrypted_token"]

    assert {:ok, encrypted_binary} = Base.decode64(encrypted_token)
    assert {:ok, token} = EncryptedBinary.load(encrypted_binary)
    assert is_binary(token)
    refute encrypted_token == token
    assert job.args["locale"] == "es"

    assert :ok = perform_job(DeliverInvitationWorker, job.args)
    assert_receive {:email, email}
    assert email.to == [{"", invitation.email}]
    assert email.subject == "Has sido invitado a #{workspace.name}"
    assert email.text_body =~ "Ada"
  end

  test "cancels delivery when the invitation was revoked" do
    owner = user_fixture()
    project = project_fixture(owner)

    assert {:ok, invitation} =
             Projects.create_invitation(project, owner, "revoked@example.com", "editor")

    job = latest_job()
    assert {:ok, _invitation} = Projects.revoke_invitation(invitation)

    assert {:cancel, :invitation_unavailable} =
             DeliverInvitationWorker.perform(%Oban.Job{
               args: job.args,
               attempt: 1,
               max_attempts: 5
             })

    refute_receive {:email, _email}
  end

  test "delivers a project invitation with its acceptance URL" do
    owner = user_fixture()
    project = project_fixture(owner)

    assert {:ok, invitation} =
             Projects.create_invitation(project, owner, "project-invitee@example.com", "viewer")

    job = latest_job()
    assert :ok = perform_job(DeliverInvitationWorker, job.args)
    assert_receive {:email, email}
    assert email.to == [{"", invitation.email}]
    assert email.subject == "You've been invited to #{project.name}"
    assert email.text_body =~ "/projects/invitations/"
  end

  test "reports the remaining lifetime when a queued email is delivered later" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)

    assert {:ok, invitation} =
             Workspaces.create_invitation(workspace, owner, "delayed@example.com", "member")

    job = latest_job()

    invitation
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), 12 * 60 * 60, :second))
    |> Repo.update!()

    assert :ok = perform_job(DeliverInvitationWorker, job.args)
    assert_receive {:email, email}
    assert email.text_body =~ "expires in 1 day."
    refute email.text_body =~ "expires in 1 days."
  end

  test "cancels a queued project email after the project is deleted" do
    owner = user_fixture()
    project = project_fixture(owner)

    assert {:ok, invitation} =
             Projects.create_invitation(project, owner, "deleted-project@example.com", "viewer")

    job = latest_job()
    assert {:ok, _deleted_project} = Projects.delete_project(project, owner.id)
    refute Repo.get(invitation.__struct__, invitation.id)

    assert {:cancel, :invitation_unavailable} =
             DeliverInvitationWorker.perform(%Oban.Job{
               args: job.args,
               attempt: 1,
               max_attempts: 5
             })

    refute_receive {:email, _email}
  end

  test "a transient delivery failure keeps the invitation and its reserved seat" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)

    assert {:ok, invitation} =
             Workspaces.create_invitation(workspace, owner, "transient@example.com", "member")

    job = latest_job()
    Application.put_env(:storyarn, Storyarn.Mailer, adapter: Storyarn.FailingMailerAdapter)

    assert {:error, :simulated_delivery_failure} =
             DeliverInvitationWorker.perform(%Oban.Job{
               args: job.args,
               attempt: 2,
               max_attempts: 5
             })

    assert [pending_invitation] = Workspaces.list_pending_invitations(workspace.id)
    assert pending_invitation.id == invitation.id

    assert {:error, :limit_reached, %{used: 2, limit: 2}} =
             Workspaces.create_invitation(
               workspace,
               owner,
               "another-person@example.com",
               "member"
             )
  end

  test "the final delivery failure frees the seat for a new invitation" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)

    assert {:ok, _invitation} =
             Workspaces.create_invitation(workspace, owner, "retry@example.com", "member")

    job = latest_job()

    Application.put_env(:storyarn, Storyarn.Mailer, adapter: Storyarn.FailingMailerAdapter)

    assert {:cancel, :simulated_delivery_failure} =
             DeliverInvitationWorker.perform(%Oban.Job{
               args: job.args,
               attempt: 5,
               max_attempts: 5
             })

    assert Workspaces.list_pending_invitations(workspace.id) == []

    Application.put_env(:storyarn, Storyarn.Mailer, adapter: Swoosh.Adapters.Test)

    assert {:ok, _invitation} =
             Workspaces.create_invitation(workspace, owner, "retry@example.com", "member")
  end

  defp latest_job do
    Repo.one!(
      from(job in Oban.Job,
        where: job.worker == ^inspect(DeliverInvitationWorker),
        order_by: [desc: job.id],
        limit: 1
      )
    )
  end
end
