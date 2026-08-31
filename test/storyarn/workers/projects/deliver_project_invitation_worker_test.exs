defmodule Storyarn.Workers.DeliverProjectInvitationWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Platform.Mailer
  alias Storyarn.Platform.Shared.EncryptedBinary
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Workers.DeliverProjectInvitationWorker

  setup do
    mailer_config = Application.get_env(:storyarn, Mailer)
    locale = Gettext.get_locale(Storyarn.Gettext)

    on_exit(fn ->
      Application.put_env(:storyarn, Mailer, mailer_config)
      Gettext.put_locale(Storyarn.Gettext, locale)
    end)

    :ok
  end

  test "uses the Project-owned worker identity and delivery queue" do
    opts = DeliverProjectInvitationWorker.__opts__()

    assert opts[:queue] == :invitation_delivery
    assert opts[:max_attempts] == 5
    assert opts[:worker] == inspect(DeliverProjectInvitationWorker)
  end

  test "queues the exact encrypted Project payload and delivers its acceptance URL" do
    owner = user_fixture()
    project = project_fixture(owner)
    test_process = self()
    Gettext.put_locale(Storyarn.Gettext, "es")

    queue_notifier = fn payload ->
      job = latest_job()
      send(test_process, {:project_invitation_queue_wakeup, payload, job.id})
      :ok
    end

    assert {:ok, invitation} =
             Projects.create_admin_invitation(
               project,
               "project-invitee@example.com",
               "viewer",
               inviter_name: "Ada",
               queue_notifier: queue_notifier
             )

    job = latest_job()
    encrypted_token = job.args["encrypted_token"]

    assert_receive {:project_invitation_queue_wakeup, %{queue: "invitation_delivery"}, job_id}
    assert job_id == job.id

    assert job.worker == inspect(DeliverProjectInvitationWorker)
    assert job.queue == "invitation_delivery"

    assert Map.delete(job.args, "encrypted_token") == %{
             "context" => "project",
             "inviter_name" => "Ada",
             "locale" => "es"
           }

    assert job.args |> Map.keys() |> Enum.sort() ==
             ~w(context encrypted_token inviter_name locale)

    assert {:ok, encrypted_binary} = Base.decode64(encrypted_token)
    assert {:ok, token} = EncryptedBinary.load(encrypted_binary)
    assert is_binary(token)
    refute encrypted_token == token

    assert :ok = perform_job(DeliverProjectInvitationWorker, job.args)
    assert_receive {:email, email}
    assert email.to == [{"", invitation.email}]
    assert email.text_body =~ "Ada"
    assert email.text_body =~ "/projects/invitations/"
  end

  test "cancels a payload owned by another invitation context" do
    assert {:cancel, :invalid_invitation_context} =
             DeliverProjectInvitationWorker.perform(%Oban.Job{
               args: %{
                 "context" => "workspace",
                 "encrypted_token" => "opaque",
                 "locale" => "en"
               },
               attempt: 1,
               max_attempts: 5
             })

    refute_receive {:email, _email}
  end

  test "cancels a payload whose encrypted token cannot be decoded" do
    assert {:cancel, :invalid_invitation_token} =
             DeliverProjectInvitationWorker.perform(%Oban.Job{
               args: %{
                 "context" => "project",
                 "encrypted_token" => "not-base64",
                 "locale" => "en"
               },
               attempt: 1,
               max_attempts: 5
             })

    refute_receive {:email, _email}
  end

  test "cancels delivery when the invitation was revoked" do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    project = project_fixture(owner)

    assert {:ok, invitation} =
             Projects.create_invitation(scope, project.id, "revoked@example.com", "editor")

    job = latest_job()
    assert {:ok, _invitation} = Projects.revoke_invitation(scope, project.id, invitation.id)

    assert {:cancel, :invitation_unavailable} =
             DeliverProjectInvitationWorker.perform(%Oban.Job{
               args: job.args,
               attempt: 1,
               max_attempts: 5
             })

    refute_receive {:email, _email}
  end

  test "cancels a queued email after the Project is deleted" do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    project = project_fixture(owner)

    assert {:ok, invitation} =
             Projects.create_invitation(scope, project.id, "deleted-project@example.com", "viewer")

    job = latest_job()
    assert {:ok, _deleted_project} = Projects.delete_project(scope, project.id)
    refute Repo.get(invitation.__struct__, invitation.id)

    assert {:cancel, :invitation_unavailable} =
             DeliverProjectInvitationWorker.perform(%Oban.Job{
               args: job.args,
               attempt: 1,
               max_attempts: 5
             })

    refute_receive {:email, _email}
  end

  test "a transient delivery failure keeps the Project invitation and its reserved seat" do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    project = project_fixture(owner)

    assert {:ok, invitation} =
             Projects.create_invitation(scope, project.id, "transient-project@example.com", "editor")

    job = latest_job()
    Application.put_env(:storyarn, Mailer, adapter: Storyarn.FailingMailerAdapter)

    assert {:error, :simulated_delivery_failure} =
             DeliverProjectInvitationWorker.perform(%Oban.Job{
               args: job.args,
               attempt: 2,
               max_attempts: 5
             })

    assert [pending_invitation] = Projects.list_pending_invitations(project.id)
    assert pending_invitation.id == invitation.id

    assert {:error, :limit_reached, %{used: 2, limit: 2}} =
             Projects.create_invitation(
               scope,
               project.id,
               "another-project-member@example.com",
               "viewer"
             )
  end

  test "the final Project delivery failure frees the seat for a new invitation" do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    project = project_fixture(owner)

    assert {:ok, _invitation} =
             Projects.create_invitation(scope, project.id, "retry-project@example.com", "editor")

    job = latest_job()
    Application.put_env(:storyarn, Mailer, adapter: Storyarn.FailingMailerAdapter)

    assert {:cancel, :simulated_delivery_failure} =
             DeliverProjectInvitationWorker.perform(%Oban.Job{
               args: job.args,
               attempt: 5,
               max_attempts: 5
             })

    assert Projects.list_pending_invitations(project.id) == []

    Application.put_env(:storyarn, Mailer, adapter: Swoosh.Adapters.Test)

    assert {:ok, _invitation} =
             Projects.create_invitation(scope, project.id, "retry-project@example.com", "editor")
  end

  defp latest_job do
    Repo.one!(
      from(job in Oban.Job,
        where: job.worker == ^inspect(DeliverProjectInvitationWorker),
        order_by: [desc: job.id],
        limit: 1
      )
    )
  end
end
