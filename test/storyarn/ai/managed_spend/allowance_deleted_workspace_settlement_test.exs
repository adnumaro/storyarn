defmodule Storyarn.AI.ManagedSpend.AllowanceDeletedWorkspaceSettlementTest do
  use ExUnit.Case, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.AI.ManagedSpend.Commands.Allowance, as: AllowanceCommands
  alias Storyarn.AI.Operation
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @timeout 15_000
  @blocked_timeout 5_000

  test "settlement waits for a concurrent workspace delete and then checks the durable reservation" do
    Sandbox.unboxed_run(Repo, fn ->
      owner =
        user_fixture(%{
          email: "ai-allowance-deleted-settlement-#{Ecto.UUID.generate()}@example.com"
        })

      workspace = workspace_fixture(owner)

      stale_operation = %Operation{
        id: 9_000_000_000_000 + System.unique_integer([:positive]),
        workspace_id: workspace.id,
        workspace_id_snapshot: workspace.id
      }

      parent = self()
      barrier = make_ref()
      deleter = start_workspace_delete(workspace.id, parent, barrier)

      try do
        assert_receive {^barrier, :workspace_delete_pending, deleter_backend_pid}, @timeout

        settlement = start_settlement(stale_operation, parent, barrier)

        try do
          assert_receive {^barrier, :settlement_ready, settlement_pid, settlement_backend_pid}, @timeout
          send(settlement_pid, {barrier, :start_settlement})

          assert wait_until_blocked_by(settlement_backend_pid, deleter_backend_pid),
                 "allowance settlement did not retain the Workspace snapshot before checking its reservation"

          send(deleter.pid, {barrier, :commit_workspace_delete})
          assert {:ok, :workspace_deleted} = Task.await(deleter, @timeout)

          assert {:ok, {:error, :allowance_reservation_missing}} = Task.await(settlement, @timeout)
        after
          finish_task(settlement)
        end
      after
        send(deleter.pid, {barrier, :commit_workspace_delete})
        finish_task(deleter)
        cleanup(workspace.id, owner.id)
      end
    end)
  end

  defp start_workspace_delete(workspace_id, parent, barrier) do
    Task.async(fn -> run_workspace_delete(workspace_id, parent, barrier) end)
  end

  defp run_workspace_delete(workspace_id, parent, barrier) do
    Sandbox.unboxed_run(Repo, fn -> hold_workspace_delete(workspace_id, parent, barrier) end)
  end

  defp hold_workspace_delete(workspace_id, parent, barrier) do
    Repo.transaction(fn ->
      [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
      {1, _deleted} = Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^workspace_id))
      send(parent, {barrier, :workspace_delete_pending, backend_pid})
      await_workspace_delete_commit(barrier)
    end)
  end

  defp await_workspace_delete_commit(barrier) do
    receive do
      {^barrier, :commit_workspace_delete} -> :workspace_deleted
    after
      @timeout -> exit(:workspace_delete_release_timeout)
    end
  end

  defp start_settlement(operation, parent, barrier) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
        send(parent, {barrier, :settlement_ready, self(), backend_pid})

        receive do
          {^barrier, :start_settlement} ->
            Repo.transaction(fn -> AllowanceCommands.commit(operation) end)
        after
          @timeout -> exit(:settlement_start_timeout)
        end
      end)
    end)
  end

  defp wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid) do
    deadline = System.monotonic_time(:millisecond) + @blocked_timeout
    do_wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid, deadline)
  end

  defp do_wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid, deadline) do
    cond do
      backend_blocked_by?(blocked_backend_pid, blocker_backend_pid) ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(10)
        do_wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid, deadline)
    end
  end

  defp backend_blocked_by?(blocked_backend_pid, blocker_backend_pid) do
    case Repo.query!(
           """
           SELECT wait_event_type,
                  $2::integer = ANY(pg_blocking_pids(pid)) AS blocked_by_delete
           FROM pg_stat_activity
           WHERE pid = $1::integer
           """,
           [blocked_backend_pid, blocker_backend_pid]
         ).rows do
      [["Lock", true]] -> true
      _other -> false
    end
  end

  defp finish_task(%Task{} = task) do
    if Process.alive?(task.pid) do
      Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill)
    end

    :ok
  end

  defp cleanup(workspace_id, user_id) do
    Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^workspace_id))
    Repo.delete_all(from(user in User, where: user.id == ^user_id))
  end
end
