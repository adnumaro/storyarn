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

  test "content writers wait at Project before a referencing snapshot and both commit" do
    %{user: user, project: project, first_flow: snapshot_flow} =
      fixture = setup_fixture()

    on_exit(fn -> cleanup_fixture(user.id, project.workspace_id) end)
    edited_node = add_snapshot_target(fixture)

    for {command, text} <- [
          {:update_node, "Updated through the full-node command"},
          {:update_node_data, "Updated through the data command"},
          {:edit_node, "Updated through the canonical editor command"}
        ] do
      assert_snapshot_and_content_write_commit(snapshot_flow, edited_node, command, text)
    end

    persisted_node = Sandbox.unboxed_run(Repo, fn -> Repo.get!(FlowNode, edited_node.id) end)
    assert persisted_node.data["text"] == "Updated through the canonical editor command"
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

  defp add_snapshot_target(%{first_flow: snapshot_flow, second_flow: edited_flow}) do
    Sandbox.unboxed_run(Repo, fn ->
      node_fixture(snapshot_flow, %{
        type: "subflow",
        data: %{"referenced_flow_id" => edited_flow.id}
      })

      node_fixture(edited_flow, %{
        type: "dialogue",
        data: %{"text" => "Before the concurrent write"}
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

  defp write_content_node(node, command, text, parent, barrier) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
        send(parent, {barrier, :writer_backend_ready, self(), backend_pid})

        node
        |> run_content_write(command, text)
        |> normalize_content_write_result()
      rescue
        error -> {:raised, error}
      catch
        kind, reason -> {kind, reason}
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp run_content_write(node, :update_node, text) do
    Flows.update_node_without_dashboard_broadcast(node, %{
      data: Map.put(node.data, "text", text)
    })
  end

  defp run_content_write(node, :update_node_data, text) do
    Flows.update_node_data_without_dashboard_broadcast(
      node,
      Map.put(node.data, "text", text)
    )
  end

  defp run_content_write(node, :edit_node, text) do
    Flows.edit_node(node.flow_id, node.id, :put_field, %{
      field: "text",
      value: text
    })
  end

  defp normalize_content_write_result({:ok, %FlowNode{} = node}), do: {:ok, node}
  defp normalize_content_write_result({:ok, %FlowNode{} = node, _meta}), do: {:ok, node}
  defp normalize_content_write_result({:ok, %{node: %FlowNode{} = node}}), do: {:ok, node}
  defp normalize_content_write_result(other), do: other

  defp assert_snapshot_and_content_write_commit(snapshot_flow, edited_node, command, text) do
    parent = self()
    barrier = make_ref()
    snapshot_flow_id = snapshot_flow.id
    handler_id = attach_source_lock_barrier([snapshot_flow_id], parent, barrier)
    snapshot_task = snapshot(snapshot_flow)

    try do
      assert_receive {
                       ^barrier,
                       :snapshot_source_locked,
                       snapshot_pid,
                       ^snapshot_flow_id,
                       snapshot_backend_pid
                     },
                     @timeout

      writer_task = write_content_node(edited_node, command, text, parent, barrier)

      try do
        assert_receive {
                         ^barrier,
                         :writer_backend_ready,
                         writer_pid,
                         writer_backend_pid
                       },
                       @timeout

        assert writer_pid == writer_task.pid
        assert_blocked_by!(writer_backend_pid, snapshot_backend_pid)
        send(snapshot_pid, {barrier, :continue})

        assert {:ok, %{"original_id" => ^snapshot_flow_id}} =
                 Task.await(snapshot_task, @timeout)

        assert {:ok, %FlowNode{data: %{"text" => ^text}}} =
                 Task.await(writer_task, @timeout)
      after
        release_or_stop_tasks([snapshot_task, writer_task], barrier)
      end
    after
      :telemetry.detach(handler_id)
      release_or_stop_tasks([snapshot_task], barrier)
    end
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
        flunk("backend #{blocked_backend_pid} never waited for backend #{blocker_backend_pid}")

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
