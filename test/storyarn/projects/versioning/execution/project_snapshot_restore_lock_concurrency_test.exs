defmodule Storyarn.Projects.Versioning.ProjectSnapshotRestoreLockConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.VersioningFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Commercial.Billing
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.ProjectSnapshotRestore
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @timeout 10_000
  @poll_interval 20

  test "restore request waits at Workspace before a storage writer takes Project" do
    context = setup_fixture()
    on_exit(fn -> cleanup_fixture(context) end)

    parent = self()
    barrier = make_ref()
    holder = workspace_lock_holder(context.workspace.id, context.project.id, parent, barrier)

    assert_receive {^barrier, :workspace_locked, holder_pid, holder_backend_pid}, @timeout

    requester = restore_requester(context, parent, barrier)

    assert_receive {^barrier, :requester_ready, requester_pid, requester_backend_pid}, @timeout
    send(requester_pid, {barrier, :request})

    assert_eventually_blocked_by(requester_backend_pid, holder_backend_pid)

    # With the old Project -> Workspace order, this step completed the inverse
    # wait cycle and PostgreSQL aborted one transaction with 40P01. A request
    # that waits for Workspace first owns no Project lock, so the storage writer
    # can finish its canonical Workspace -> Project critical section.
    send(holder_pid, {barrier, :lock_project})
    assert_receive {^barrier, :project_locked, ^holder_pid}, @timeout

    send(holder_pid, {barrier, :release})
    assert {:ok, :workspace_released} = Task.await(holder, @timeout)
    assert {:ok, %ProjectSnapshotRestore{project_id: project_id}} = Task.await(requester, @timeout)
    assert project_id == context.project.id
  end

  defp setup_fixture do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "restore-lock-order-#{Ecto.UUID.generate()}@example.com"
        })

      project = project_fixture(user)
      snapshot = full_project_snapshot_fixture(project)

      %{
        user: user,
        scope: user_scope_fixture(user),
        project: project,
        snapshot: snapshot,
        workspace: Repo.get!(Workspace, project.workspace_id)
      }
    end)
  end

  defp workspace_lock_holder(workspace_id, project_id, parent, barrier) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows

        Billing.transact_with_workspace_lock(workspace_id, fn _workspace ->
          send(parent, {barrier, :workspace_locked, self(), backend_pid})

          receive do
            {^barrier, :lock_project} ->
              Repo.one!(from project in Project, where: project.id == ^project_id, lock: "FOR UPDATE")
              send(parent, {barrier, :project_locked, self()})
          after
            @timeout -> exit(:project_lock_barrier_timeout)
          end

          receive do
            {^barrier, :release} -> {:ok, :workspace_released}
          after
            @timeout -> {:error, :workspace_release_barrier_timeout}
          end
        end)
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp restore_requester(context, parent, barrier) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
        send(parent, {barrier, :requester_ready, self(), backend_pid})

        receive do
          {^barrier, :request} ->
            Versioning.request_project_snapshot_restore(
              context.scope,
              context.project,
              context.snapshot,
              %{idempotency_key: Ecto.UUID.generate()}
            )
        after
          @timeout -> {:error, :restore_request_barrier_timeout}
        end
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp assert_eventually_blocked_by(waiter_backend_pid, holder_backend_pid, attempts \\ div(@timeout, @poll_interval))

  defp assert_eventually_blocked_by(_waiter_backend_pid, _holder_backend_pid, 0) do
    flunk("restore request never waited on the workspace lock")
  end

  defp assert_eventually_blocked_by(waiter_backend_pid, holder_backend_pid, attempts) do
    blocked? =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("SELECT $2 = ANY(pg_blocking_pids($1))", [waiter_backend_pid, holder_backend_pid]).rows == [[true]]
      end)

    if blocked? do
      :ok
    else
      Process.sleep(@poll_interval)
      assert_eventually_blocked_by(waiter_backend_pid, holder_backend_pid, attempts - 1)
    end
  end

  defp cleanup_fixture(context) do
    Sandbox.unboxed_run(Repo, fn ->
      job_ids =
        Repo.all(
          from restore in ProjectSnapshotRestore,
            where: restore.project_id == ^context.project.id,
            select: restore.oban_job_id
        )

      Repo.delete_all(from project in Project, where: project.id == ^context.project.id)
      Repo.delete_all(from job in Oban.Job, where: job.id in ^job_ids)
      Repo.delete_all(from workspace in Workspace, where: workspace.id == ^context.workspace.id)
      Repo.delete_all(from user in User, where: user.id == ^context.user.id)
    end)
  end
end
