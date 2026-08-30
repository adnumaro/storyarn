defmodule Storyarn.Flows.Versioning.FlowSnapshotLockOrderConcurrencyTest do
  use ExUnit.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Flows.Versioning.FlowSnapshot
  alias Storyarn.Repo

  @timeout 15_000

  # This is deliberately a smoke test for independent Flows. It does not prove
  # safety when one Flow references the other, because reference validation
  # acquires additional Flow locks after the localization inventory lock. That
  # inherited lock-order problem needs its own concurrency design and test.
  test "snapshots of independent flows coexist under the shared project lock" do
    %{user: user, project: project, first_flow: first_flow, second_flow: second_flow} =
      setup_fixture()

    on_exit(fn -> cleanup_fixture(user.id, project.workspace_id) end)

    parent = self()
    barrier = make_ref()

    first = snapshot_after_shared_project_lock(first_flow, parent, barrier)
    second = snapshot_after_shared_project_lock(second_flow, parent, barrier)

    tasks = [first, second]

    results =
      try do
        locked_pids =
          for _task <- tasks do
            assert_receive {^barrier, :project_share_locked, pid}, @timeout
            pid
          end

        assert MapSet.new(locked_pids) == MapSet.new(Enum.map(tasks, & &1.pid))
        Enum.each(tasks, &send(&1.pid, {barrier, :build_snapshot}))
        Enum.map(tasks, &Task.await(&1, @timeout))
      after
        release_or_stop_tasks(tasks, barrier)
      end

    assert [{:ok, %{"original_id" => first_id}}, {:ok, %{"original_id" => second_id}}] =
             results

    assert first_id == first_flow.id
    assert second_id == second_flow.id
  end

  defp setup_fixture do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "flow-snapshot-lock-order-#{Ecto.UUID.generate()}@example.com"
        })

      project = project_fixture(user)

      %{
        user: user,
        project: project,
        first_flow: flow_fixture(project),
        second_flow: flow_fixture(project)
      }
    end)
  end

  defp snapshot_after_shared_project_lock(flow, parent, barrier) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        case Repo.transaction(
               fn ->
                 Repo.query!("SELECT id FROM projects WHERE id = $1 FOR SHARE", [
                   flow.project_id
                 ])

                 send(parent, {barrier, :project_share_locked, self()})

                 receive do
                   {^barrier, :build_snapshot} -> FlowSnapshot.build(flow)
                 after
                   @timeout -> Repo.rollback(:snapshot_barrier_timeout)
                 end
               end,
               isolation: :repeatable_read
             ) do
          {:ok, snapshot} -> {:ok, snapshot}
          {:error, reason} -> {:error, reason}
        end
      rescue
        error -> {:raised, error}
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp cleanup_fixture(user_id, workspace_id) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!("DELETE FROM workspaces WHERE id = $1", [workspace_id])
      Repo.query!("DELETE FROM users WHERE id = $1", [user_id])
    end)
  end

  defp release_or_stop_tasks(tasks, barrier) do
    unfinished = Enum.filter(tasks, &Process.alive?(&1.pid))

    Enum.each(unfinished, &send(&1.pid, {barrier, :build_snapshot}))

    Enum.each(unfinished, fn task ->
      if Task.yield(task, @timeout) == nil do
        _shutdown_result = Task.shutdown(task, :brutal_kill)
      end
    end)
  end
end
