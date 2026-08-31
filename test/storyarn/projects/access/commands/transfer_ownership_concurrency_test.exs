defmodule Storyarn.Projects.Access.Commands.TransferOwnershipConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.VersioningFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Projects
  alias Storyarn.Projects.Access.Commands.TransferOwnership
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.ProjectSnapshotRestore
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @timeout 10_000

  test "two concurrent transfers of one project converge on exactly one canonical owner" do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture()
      project = project_fixture(owner)
      first_receiver = user_without_workspace()
      second_receiver = user_without_workspace()
      _first_membership = membership_fixture(project, first_receiver, "editor")
      _second_membership = membership_fixture(project, second_receiver, "viewer")

      try do
        tasks =
          run_concurrently([
            fn -> Projects.transfer_owner(Scope.for_user(owner), project.id, first_receiver.id) end,
            fn -> Projects.transfer_owner(Scope.for_user(owner), project.id, second_receiver.id) end
          ])

        results = Task.await_many(tasks, 5_000)

        assert Enum.count(results, &match?({:ok, %Project{}}, &1)) == 1
        assert Enum.count(results, &match?({:error, :unauthorized}, &1)) == 1

        persisted_project = Repo.get!(Project, project.id)
        owners = Enum.filter(Projects.list_project_members(project.id), &(&1.role == "owner"))

        assert [%{user_id: owner_id}] = owners
        assert owner_id == persisted_project.owner_id
      after
        cleanup(project, [owner.id, first_receiver.id, second_receiver.id])
      end
    end)
  end

  test "a restore request waits for transfer and reauthorizes the former owner" do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture()
      owner_scope = Scope.for_user(owner)
      project = project_fixture(owner)
      snapshot = full_project_snapshot_fixture(project)
      receiver = user_without_workspace()
      _receiver_membership = membership_fixture(project, receiver, "editor")
      parent = self()
      barrier = make_ref()

      try do
        transfer =
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              TransferOwnership.transfer(owner_scope, project.id, receiver.id,
                after_owner_demotion: fn ->
                  send(parent, {barrier, :transfer_paused, self()})

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
          assert_receive {^barrier, :transfer_paused, transfer_pid}, @timeout

          request =
            Task.async(fn ->
              Sandbox.unboxed_run(Repo, fn ->
                [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
                send(parent, {barrier, :request_ready, self(), backend_pid})

                receive do
                  {^barrier, :start_request} -> :ok
                after
                  @timeout -> raise "restore request start timeout"
                end

                Versioning.request_project_snapshot_restore(owner_scope, project, snapshot, %{
                  idempotency_key: Ecto.UUID.generate()
                })
              end)
            end)

          try do
            assert_receive {^barrier, :request_ready, request_pid, backend_pid}, @timeout
            send(request_pid, {barrier, :start_request})
            assert_connection_waiting_on_lock(backend_pid)

            send(transfer_pid, {barrier, :finish_transfer})

            assert {:ok, %Project{owner_id: receiver_id}} = Task.await(transfer, @timeout)
            assert receiver_id == receiver.id
            assert {:error, :unauthorized} = Task.await(request, @timeout)

            refute Repo.exists?(
                     from restore in ProjectSnapshotRestore,
                       where: restore.project_id == ^project.id
                   )
          after
            send(request.pid, {barrier, :start_request})
            send(transfer.pid, {barrier, :finish_transfer})
            finish_task(request)
          end
        after
          send(transfer.pid, {barrier, :finish_transfer})
          finish_task(transfer)
        end
      after
        cleanup(project, [owner.id, receiver.id])
      end
    end)
  end

  defp run_concurrently(operations) do
    parent = self()

    tasks =
      Enum.map(operations, fn operation ->
        start_concurrent_operation(parent, operation)
      end)

    ready_pids =
      Enum.map(tasks, fn _task ->
        assert_receive {:operation_ready, task_pid}, 1_000
        task_pid
      end)

    Enum.each(ready_pids, &send(&1, :start_operation))
    tasks
  end

  defp start_concurrent_operation(parent, operation) do
    Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> await_operation_start(parent, operation) end) end)
  end

  defp await_operation_start(parent, operation) do
    send(parent, {:operation_ready, self()})

    receive do
      :start_operation -> operation.()
    end
  end

  defp assert_connection_waiting_on_lock(backend_pid, attempts \\ 100)

  defp assert_connection_waiting_on_lock(_backend_pid, 0) do
    flunk("restore request did not block on the project ownership lock")
  end

  defp assert_connection_waiting_on_lock(backend_pid, attempts) do
    if Repo.query!("SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [backend_pid]).rows == [["Lock"]] do
      :ok
    else
      Process.sleep(10)
      assert_connection_waiting_on_lock(backend_pid, attempts - 1)
    end
  end

  defp finish_task(%Task{} = task) do
    if Process.alive?(task.pid) do
      Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill)
    end

    :ok
  end

  defp cleanup(project, user_ids) do
    Repo.delete_all(from(candidate in Project, where: candidate.id == ^project.id))
    Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
    Repo.delete_all(from(user in User, where: user.id in ^user_ids))
  end

  defp user_without_workspace do
    %User{}
    |> User.email_changeset(%{email: unique_user_email()})
    |> User.confirm_changeset()
    |> Repo.insert!()
  end
end
