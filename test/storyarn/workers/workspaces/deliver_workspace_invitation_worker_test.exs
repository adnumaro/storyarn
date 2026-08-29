defmodule Storyarn.Workers.DeliverWorkspaceInvitationWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Platform.Mailer
  alias Storyarn.Platform.Shared.EncryptedBinary
  alias Storyarn.Repo
  alias Storyarn.Workers.DeliverWorkspaceInvitationWorker
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.WorkspaceInvitation

  setup do
    mailer_config = Application.get_env(:storyarn, Mailer)
    encryptor = Application.get_env(:storyarn, :invitation_token_encryptor)
    locale = Gettext.get_locale(Storyarn.Gettext)

    on_exit(fn ->
      Application.put_env(:storyarn, Mailer, mailer_config)
      restore_encryptor(encryptor)
      Gettext.put_locale(Storyarn.Gettext, locale)
    end)

    :ok
  end

  test "uses the Workspace-owned worker identity and delivery queue" do
    opts = DeliverWorkspaceInvitationWorker.__opts__()

    assert opts[:queue] == :invitation_delivery
    assert opts[:max_attempts] == 5
    assert opts[:worker] == inspect(DeliverWorkspaceInvitationWorker)
  end

  test "queues the exact encrypted Workspace payload and delivers in its locale" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    test_process = self()
    Gettext.put_locale(Storyarn.Gettext, "es")

    queue_notifier = fn payload ->
      job = latest_job()
      send(test_process, {:workspace_invitation_queue_wakeup, payload, job.id})
      :ok
    end

    assert {:ok, invitation} =
             Workspaces.create_admin_invitation(
               workspace,
               "invitee@example.com",
               "member",
               inviter_name: "Ada",
               queue_notifier: queue_notifier
             )

    job = latest_job()
    encrypted_token = job.args["encrypted_token"]

    assert_receive {:workspace_invitation_queue_wakeup, %{queue: "invitation_delivery"}, job_id}
    assert job_id == job.id

    assert job.worker == inspect(DeliverWorkspaceInvitationWorker)
    assert job.queue == "invitation_delivery"

    assert Map.delete(job.args, "encrypted_token") == %{
             "context" => "workspace",
             "inviter_name" => "Ada",
             "locale" => "es"
           }

    assert job.args |> Map.keys() |> Enum.sort() ==
             ~w(context encrypted_token inviter_name locale)

    assert {:ok, encrypted_binary} = Base.decode64(encrypted_token)
    assert {:ok, token} = EncryptedBinary.load(encrypted_binary)
    assert is_binary(token)
    refute encrypted_token == token

    assert :ok = perform_job(DeliverWorkspaceInvitationWorker, job.args)
    assert_receive {:email, email}
    assert email.to == [{"", invitation.email}]
    assert email.subject == "Has sido invitado a #{workspace.name}"
    assert email.text_body =~ "Ada"
  end

  test "cancels a payload owned by another invitation context" do
    assert {:cancel, :invalid_invitation_context} =
             DeliverWorkspaceInvitationWorker.perform(%Oban.Job{
               args: %{
                 "context" => "project",
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
             DeliverWorkspaceInvitationWorker.perform(%Oban.Job{
               args: %{
                 "context" => "workspace",
                 "encrypted_token" => "not-base64",
                 "locale" => "en"
               },
               attempt: 1,
               max_attempts: 5
             })

    refute_receive {:email, _email}
  end

  test "cancels delivery when the Workspace invitation was revoked" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)

    assert {:ok, invitation} =
             Workspaces.create_invitation(workspace, owner, "revoked-workspace@example.com", "member")

    job = latest_job()
    assert {:ok, _invitation} = Workspaces.revoke_invitation(invitation)

    assert {:cancel, :invitation_unavailable} =
             DeliverWorkspaceInvitationWorker.perform(%Oban.Job{
               args: job.args,
               attempt: 1,
               max_attempts: 5
             })

    refute_receive {:email, _email}
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

    assert :ok = perform_job(DeliverWorkspaceInvitationWorker, job.args)
    assert_receive {:email, email}
    assert email.text_body =~ "expires in 1 day."
    refute email.text_body =~ "expires in 1 days."
  end

  test "a transient delivery failure keeps the invitation and its reserved seat" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)

    assert {:ok, invitation} =
             Workspaces.create_invitation(workspace, owner, "transient@example.com", "member")

    job = latest_job()
    Application.put_env(:storyarn, Mailer, adapter: Storyarn.FailingMailerAdapter)

    assert {:error, :simulated_delivery_failure} =
             DeliverWorkspaceInvitationWorker.perform(%Oban.Job{
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
    Application.put_env(:storyarn, Mailer, adapter: Storyarn.FailingMailerAdapter)

    assert {:cancel, :simulated_delivery_failure} =
             DeliverWorkspaceInvitationWorker.perform(%Oban.Job{
               args: job.args,
               attempt: 5,
               max_attempts: 5
             })

    assert Workspaces.list_pending_invitations(workspace.id) == []

    Application.put_env(:storyarn, Mailer, adapter: Swoosh.Adapters.Test)

    assert {:ok, _invitation} =
             Workspaces.create_invitation(workspace, owner, "retry@example.com", "member")
  end

  test "rolls back Workspace invitation creation when token encryption is unavailable" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    email = "encryption-unavailable@example.com"

    Application.put_env(
      :storyarn,
      :invitation_token_encryptor,
      Storyarn.FailingInvitationEncryptor
    )

    assert {:error, :encryption_unavailable} =
             Workspaces.create_invitation(workspace, owner, email, "member")

    refute Repo.get_by(WorkspaceInvitation, workspace_id: workspace.id, email: email)

    refute Repo.exists?(
             from(job in Oban.Job,
               where: job.worker == ^inspect(DeliverWorkspaceInvitationWorker)
             )
           )
  end

  defp latest_job do
    Repo.one!(
      from(job in Oban.Job,
        where: job.worker == ^inspect(DeliverWorkspaceInvitationWorker),
        order_by: [desc: job.id],
        limit: 1
      )
    )
  end

  defp restore_encryptor(nil), do: Application.delete_env(:storyarn, :invitation_token_encryptor)

  defp restore_encryptor(encryptor) do
    Application.put_env(:storyarn, :invitation_token_encryptor, encryptor)
  end
end
