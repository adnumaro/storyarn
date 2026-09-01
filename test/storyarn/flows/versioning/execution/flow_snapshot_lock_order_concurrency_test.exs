defmodule Storyarn.Flows.Versioning.FlowSnapshotLockOrderConcurrencyTest do
  use ExUnit.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeTypes
  alias Storyarn.Flows.Versioning.FlowSnapshot
  alias Storyarn.Repo

  @timeout 15_000
  @source_locked_event [:storyarn, :flows, :flow_snapshot, :source_locked]
  @writer_source_locked_event [:storyarn, :flows, :node_update, :source_locked]

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

  test "snapshots with reciprocal validation targets do not deadlock" do
    %{user: user, project: project, first_flow: first_flow, second_flow: second_flow} =
      fixture = setup_fixture()

    on_exit(fn -> cleanup_fixture(user.id, project.workspace_id) end)
    add_reciprocal_snapshot_targets(fixture)

    parent = self()
    barrier = make_ref()
    handler_id = attach_source_lock_barrier([first_flow.id, second_flow.id], parent, barrier)

    tasks = [snapshot(first_flow), snapshot(second_flow)]

    results =
      try do
        locked = receive_source_locks(barrier, tasks)
        assert MapSet.new(Enum.map(locked, &elem(&1, 1))) == MapSet.new([first_flow.id, second_flow.id])

        Enum.each(locked, fn {pid, _flow_id, _backend_pid} ->
          send(pid, {barrier, :continue})
        end)

        Enum.map(tasks, &Task.await(&1, @timeout))
      after
        :telemetry.detach(handler_id)
        release_or_stop_tasks(tasks, barrier)
      end

    assert [{:ok, %{"original_id" => first_id}}, {:ok, %{"original_id" => second_id}}] =
             results

    assert first_id == first_flow.id
    assert second_id == second_flow.id
  end

  test "a snapshot referencing a concurrently edited Flow waits without a deadlock" do
    %{user: user, project: project, first_flow: snapshot_flow, second_flow: edited_flow} =
      fixture = setup_fixture()

    on_exit(fn -> cleanup_fixture(user.id, project.workspace_id) end)
    edited_node = add_snapshot_and_writer_cycle(fixture)

    parent = self()
    barrier = make_ref()

    snapshot_handler_id =
      attach_source_lock_barrier([snapshot_flow.id], parent, barrier)

    writer_handler_id =
      attach_writer_lock_barrier([edited_node.id], parent, barrier)

    writer =
      write_node_data(
        edited_node,
        %{"referenced_flow_id" => snapshot_flow.id},
        edited_flow.id
      )

    snapshot = snapshot(snapshot_flow)
    tasks = [snapshot, writer]
    snapshot_flow_id = snapshot_flow.id

    {snapshot_result, writer_result} =
      try do
        assert_receive {
                         ^barrier,
                         :writer_source_locked,
                         writer_pid,
                         writer_backend_pid
                       },
                       @timeout

        assert_receive {
                         ^barrier,
                         :snapshot_source_locked,
                         snapshot_pid,
                         ^snapshot_flow_id,
                         snapshot_backend_pid
                       },
                       @timeout

        send(snapshot_pid, {barrier, :continue})
        assert_blocked_by!(snapshot_backend_pid, writer_backend_pid)
        send(writer_pid, {barrier, :continue})

        {Task.await(snapshot, @timeout), Task.await(writer, @timeout)}
      after
        :telemetry.detach(snapshot_handler_id)
        :telemetry.detach(writer_handler_id)
        release_or_stop_tasks(tasks, barrier)
      end

    assert {:ok, %{"original_id" => snapshot_flow_id}} = snapshot_result
    assert snapshot_flow_id == snapshot_flow.id
    assert {:error, :circular_reference} = writer_result

    persisted_node =
      Sandbox.unboxed_run(Repo, fn -> Repo.get!(FlowNode, edited_node.id) end)

    assert persisted_node.data["referenced_flow_id"] == nil
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

  defp add_reciprocal_snapshot_targets(%{first_flow: first_flow, second_flow: second_flow}) do
    Sandbox.unboxed_run(Repo, fn ->
      node_fixture(first_flow, %{
        type: "subflow",
        data: %{"referenced_flow_id" => second_flow.id}
      })

      node_fixture(second_flow, %{
        type: "exit",
        data:
          "exit"
          |> NodeTypes.default_data()
          |> Map.merge(%{
            "target_type" => "flow",
            "target_id" => first_flow.id
          })
      })
    end)
  end

  defp add_snapshot_and_writer_cycle(%{first_flow: snapshot_flow, second_flow: edited_flow}) do
    Sandbox.unboxed_run(Repo, fn ->
      node_fixture(snapshot_flow, %{
        type: "subflow",
        data: %{"referenced_flow_id" => edited_flow.id}
      })

      node_fixture(edited_flow, %{
        type: "subflow",
        data: %{"referenced_flow_id" => nil}
      })
    end)
  end

  defp attach_source_lock_barrier(flow_ids, parent, barrier) do
    handler_id = "flow-snapshot-source-lock-#{System.unique_integer([:positive])}"
    flow_ids = MapSet.new(flow_ids)

    :ok =
      :telemetry.attach(
        handler_id,
        @source_locked_event,
        fn _event, _measurements, %{flow_id: flow_id}, {test_pid, ref, expected_flow_ids} ->
          if MapSet.member?(expected_flow_ids, flow_id) do
            [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows

            send(test_pid, {
              ref,
              :snapshot_source_locked,
              self(),
              flow_id,
              backend_pid
            })

            receive do
              {^ref, :continue} -> :ok
            after
              @timeout -> exit(:snapshot_source_lock_barrier_timeout)
            end
          end
        end,
        {parent, barrier, flow_ids}
      )

    handler_id
  end

  defp attach_writer_lock_barrier(node_ids, parent, barrier) do
    handler_id = "flow-node-update-source-lock-#{System.unique_integer([:positive])}"
    node_ids = MapSet.new(node_ids)

    :ok =
      :telemetry.attach(
        handler_id,
        @writer_source_locked_event,
        fn _event, _measurements, %{node_id: node_id}, {test_pid, ref, expected_node_ids} ->
          if MapSet.member?(expected_node_ids, node_id) do
            [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows

            send(test_pid, {
              ref,
              :writer_source_locked,
              self(),
              backend_pid
            })

            receive do
              {^ref, :continue} -> :ok
            after
              @timeout -> exit(:writer_source_lock_barrier_timeout)
            end
          end
        end,
        {parent, barrier, node_ids}
      )

    handler_id
  end

  defp snapshot(flow) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        {:ok, FlowSnapshot.build(flow)}
      rescue
        error -> {:raised, error}
      catch
        kind, reason -> {kind, reason}
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp write_node_data(node, data, expected_flow_id) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        true = node.flow_id == expected_flow_id
        Flows.update_node_data_without_dashboard_broadcast(node, data)
      rescue
        error -> {:raised, error}
      catch
        kind, reason -> {kind, reason}
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp receive_source_locks(barrier, tasks) do
    task_pids = MapSet.new(tasks, & &1.pid)

    for _task <- tasks do
      assert_receive {
                       ^barrier,
                       :snapshot_source_locked,
                       task_pid,
                       flow_id,
                       backend_pid
                     },
                     @timeout

      assert MapSet.member?(task_pids, task_pid)
      {task_pid, flow_id, backend_pid}
    end
  end

  defp assert_blocked_by!(blocked_backend_pid, blocker_backend_pid) do
    deadline = System.monotonic_time(:millisecond) + @timeout
    do_assert_blocked_by!(blocked_backend_pid, blocker_backend_pid, deadline)
  end

  defp do_assert_blocked_by!(blocked_backend_pid, blocker_backend_pid, deadline) do
    [[blocking_pids]] =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("SELECT pg_blocking_pids($1)", [blocked_backend_pid])
      end).rows

    cond do
      blocker_backend_pid in blocking_pids ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("snapshot backend #{blocked_backend_pid} never waited for writer backend #{blocker_backend_pid}")

      true ->
        Process.sleep(10)
        do_assert_blocked_by!(blocked_backend_pid, blocker_backend_pid, deadline)
    end
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
    Enum.each(unfinished, &send(&1.pid, {barrier, :continue}))

    Enum.each(unfinished, fn task ->
      if Task.yield(task, @timeout) == nil do
        _shutdown_result = Task.shutdown(task, :brutal_kill)
      end
    end)
  end
end
