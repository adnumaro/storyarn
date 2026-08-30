defmodule Storyarn.Projects.ProjectTemplates.PublicationRequestOwnershipConcurrencyTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Oban.Job
  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Projects
  alias Storyarn.Projects.Access.Commands.TransferOwnership
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectTemplates
  alias Storyarn.Projects.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.Repo
  alias Storyarn.Workers.PublishProjectTemplateWorker
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.WorkspacesFixtures

  @timeout 10_000

  test "publication request waits for ownership transfer and rolls back the durable request and job" do
    Sandbox.unboxed_run(Repo, fn ->
      workspace_owner = user_fixture()
      project_owner = user_without_workspace()
      receiver = user_without_workspace()
      workspace = WorkspacesFixtures.workspace_fixture(workspace_owner)

      project =
        project_fixture(workspace_owner, %{
          workspace: workspace,
          name: "Publication Ownership Race"
        })

      _project_owner_membership = membership_fixture(project, project_owner, "editor")

      assert {:ok, %Project{owner_id: project_owner_id} = project} =
               Projects.transfer_owner(Scope.for_user(workspace_owner), project.id, project_owner.id)

      assert project_owner_id == project_owner.id

      _receiver_membership = membership_fixture(project, receiver, "editor")
      project_owner_scope = Scope.for_user(project_owner)
      existing_job_ids = publication_worker_job_ids()
      parent = self()
      barrier = make_ref()

      try do
        transfer =
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              TransferOwnership.transfer(project_owner_scope, project.id, receiver.id,
                after_owner_demotion: fn ->
                  [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
                  send(parent, {barrier, :transfer_paused, self(), backend_pid})

                  receive do
                    {^barrier, :finish_transfer} -> :ok
                  after
                    @timeout -> {:error, :transfer_pause_timeout}
                  end
                end
              )
            end)
          end)

        try do
          assert_receive {^barrier, :transfer_paused, transfer_pid, transfer_backend_pid}, @timeout
          assert transfer_pid == transfer.pid

          request =
            Task.async(fn ->
              Sandbox.unboxed_run(Repo, fn ->
                [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
                send(parent, {barrier, :request_ready, self(), backend_pid})

                receive do
                  {^barrier, :start_request} -> :ok
                after
                  @timeout -> raise "publication request start timeout"
                end

                ProjectTemplates.request_template_publication(project_owner_scope, project, %{
                  name: "Unauthorized Race Publication"
                })
              end)
            end)

          try do
            assert_receive {^barrier, :request_ready, request_pid, request_backend_pid}, @timeout
            assert request_pid == request.pid

            send(request_pid, {barrier, :start_request})
            assert_connection_blocked_by(request_backend_pid, transfer_backend_pid)

            send(transfer_pid, {barrier, :finish_transfer})

            assert {:ok, %Project{owner_id: receiver_id}} = Task.await(transfer, @timeout)
            assert receiver_id == receiver.id
            assert {:error, :unauthorized} = Task.await(request, @timeout)

            refute Repo.exists?(
                     from publication in ProjectTemplatePublication,
                       where: publication.source_project_id == ^project.id
                   )

            assert publication_worker_job_ids() == existing_job_ids
          after
            finish_task(request)
          end
        after
          send(transfer.pid, {barrier, :finish_transfer})
          finish_task(transfer)
        end
      after
        cleanup(project, workspace, [workspace_owner.id, project_owner.id, receiver.id], existing_job_ids)
      end
    end)
  end

  defp assert_connection_blocked_by(blocked_backend_pid, blocker_backend_pid, attempts \\ 1_000)

  defp assert_connection_blocked_by(_blocked_backend_pid, _blocker_backend_pid, 0) do
    flunk("publication request did not wait for the ownership transfer lock")
  end

  defp assert_connection_blocked_by(blocked_backend_pid, blocker_backend_pid, attempts) do
    case Repo.query!(
           """
           SELECT wait_event_type,
                  $2::integer = ANY(pg_blocking_pids(pid)) AS blocked_by_transfer
           FROM pg_stat_activity
           WHERE pid = $1::integer
           """,
           [blocked_backend_pid, blocker_backend_pid]
         ).rows do
      [["Lock", true]] ->
        :ok

      _other ->
        Process.sleep(10)
        assert_connection_blocked_by(blocked_backend_pid, blocker_backend_pid, attempts - 1)
    end
  end

  defp publication_worker_job_ids do
    worker = inspect(PublishProjectTemplateWorker)

    Repo.all(
      from job in Job,
        where: job.worker == ^worker,
        order_by: [asc: job.id],
        select: job.id
    )
  end

  defp finish_task(%Task{} = task) do
    if Process.alive?(task.pid) do
      Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill)
    end

    :ok
  end

  defp cleanup(project, workspace, user_ids, existing_job_ids) do
    leaked_job_ids = publication_worker_job_ids() -- existing_job_ids

    if leaked_job_ids != [] do
      Repo.delete_all(from job in Job, where: job.id in ^leaked_job_ids)
    end

    Repo.delete_all(from candidate in Project, where: candidate.id == ^project.id)
    Repo.delete_all(from candidate in Workspace, where: candidate.id == ^workspace.id)
    Repo.delete_all(from user in User, where: user.id in ^user_ids)
  end

  defp user_without_workspace do
    %User{}
    |> User.email_changeset(%{email: unique_user_email()})
    |> User.confirm_changeset()
    |> Repo.insert!()
  end
end
