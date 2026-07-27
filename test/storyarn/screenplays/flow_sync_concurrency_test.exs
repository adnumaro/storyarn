defmodule Storyarn.Screenplays.FlowSyncConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Screenplays
  alias Storyarn.Screenplays.Screenplay
  alias Storyarn.Workspaces.Workspace

  @timeout 10_000

  test "reads the screenplay tree only after acquiring the flow serialization locks" do
    state =
      Sandbox.unboxed_run(Repo, fn ->
        user =
          user_fixture(%{
            email: "flow-sync-lock-#{Ecto.UUID.generate()}@example.com"
          })

        project = project_fixture(user)
        screenplay = screenplay_fixture(project, %{name: "Concurrent sync"})

        {:ok, action} =
          Screenplays.create_element(screenplay, %{
            type: "action",
            content: "Serialized version"
          })

        {:ok, flow} = Screenplays.sync_to_flow(screenplay)

        assert Repo.reload!(action).linked_node_id

        %{
          user: user,
          project: project,
          screenplay: screenplay,
          flow: flow
        }
      end)

    on_exit(fn -> cleanup(state) end)

    parent = self()
    barrier = make_ref()
    gate = :atomics.new(1, signed: false)
    handler_id = "flow-sync-snapshot-lock-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        fn _event, _measurements, %{query: query}, {test_pid, ref, gate_ref} ->
          if String.contains?(query, ~s(FROM "screenplay_elements")) and
               Regex.match?(~r/WHERE .*"screenplay_id"\s*=/, query) and
               :atomics.compare_exchange(gate_ref, 1, 0, 1) == :ok do
            send(test_pid, {ref, :snapshot_read, self()})

            receive do
              {^ref, :continue} -> :ok
            after
              @timeout -> exit(:snapshot_gate_timeout)
            end
          end
        end,
        {parent, barrier, gate}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    syncer =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Screenplays.sync_to_flow(state.screenplay)
        end)
      end)

    assert_receive {^barrier, :snapshot_read, sync_pid}, @timeout

    project_locked? = row_locked?("projects", state.project.id)
    screenplay_locked? = row_locked?("screenplays", state.screenplay.id)
    flow_locked? = row_locked?("flows", state.flow.id)

    project_deleter =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {barrier, :project_delete_started, backend_pid})
          Projects.delete_project(state.project, state.user.id)
        end)
      end)

    assert_receive {^barrier, :project_delete_started, delete_backend_pid}, @timeout
    assert :blocked = wait_until_completed_or_blocked(project_deleter, delete_backend_pid)

    send(sync_pid, {barrier, :continue})

    assert {:ok, _flow} = Task.await(syncer, @timeout)
    assert {:ok, deleted_project} = Task.await(project_deleter, @timeout)
    assert deleted_project.deleted_at
    assert project_locked?
    assert screenplay_locked?
    assert flow_locked?
  end

  test "sync does not block an editor write in another flow from the same project" do
    state =
      Sandbox.unboxed_run(Repo, fn ->
        user =
          user_fixture(%{
            email: "flow-sync-independent-flow-#{Ecto.UUID.generate()}@example.com"
          })

        project = project_fixture(user)
        screenplay = screenplay_fixture(project, %{name: "Concurrent independent flow sync"})

        {:ok, _action} =
          Screenplays.create_element(screenplay, %{
            type: "action",
            content: "Opening action"
          })

        {:ok, flow} = Screenplays.sync_to_flow(screenplay)
        {:ok, other_flow} = Flows.create_flow(project, %{name: "Independent editor flow"})

        other_node =
          other_flow.id
          |> Flows.list_nodes()
          |> Enum.find(&(&1.type == "exit"))

        %{
          user: user,
          project: project,
          screenplay: screenplay,
          flow: flow,
          other_node: other_node
        }
      end)

    on_exit(fn -> cleanup(state) end)

    parent = self()
    barrier = make_ref()
    gate = :atomics.new(1, signed: false)
    handler_id = "flow-sync-independent-flow-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        fn _event, _measurements, %{query: query}, {test_pid, ref, gate_ref} ->
          if String.contains?(query, ~s(FROM "screenplay_elements")) and
               Regex.match?(~r/WHERE .*"screenplay_id"\s*=/, query) and
               :atomics.compare_exchange(gate_ref, 1, 0, 1) == :ok do
            send(test_pid, {ref, :snapshot_read, self()})

            receive do
              {^ref, :continue} -> :ok
            after
              @timeout -> exit(:snapshot_gate_timeout)
            end
          end
        end,
        {parent, barrier, gate}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    syncer =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Screenplays.sync_to_flow(state.screenplay)
        end)
      end)

    assert_receive {^barrier, :snapshot_read, sync_pid}, @timeout

    editor =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {barrier, :editor_started, backend_pid})

          Flows.update_node_position(state.other_node, %{
            position_x: state.other_node.position_x + 25
          })
        end)
      end)

    assert_receive {^barrier, :editor_started, editor_backend_pid}, @timeout
    editor_state = wait_until_completed_or_blocked(editor, editor_backend_pid)
    editor_blocking_details = blocking_details(editor_backend_pid)

    send(sync_pid, {barrier, :continue})

    assert {:ok, _flow} = Task.await(syncer, @timeout)

    editor_result =
      case editor_state do
        {:completed, result} -> result
        :blocked -> Task.await(editor, @timeout)
      end

    assert match?({:completed, _result}, editor_state),
           "editor flow=#{state.other_node.flow_id}, sync flow=#{state.flow.id}, " <>
             "node=#{state.other_node.id}; blocked by #{inspect(editor_blocking_details)}"

    assert {:ok, updated_node} = editor_result
    assert updated_node.position_x == state.other_node.position_x + 25
  end

  test "concurrent first syncs reuse the same linked flow" do
    state =
      Sandbox.unboxed_run(Repo, fn ->
        user =
          user_fixture(%{
            email: "flow-sync-first-link-#{Ecto.UUID.generate()}@example.com"
          })

        project = project_fixture(user)
        screenplay = screenplay_fixture(project, %{name: "Concurrent first sync"})

        {:ok, _action} =
          Screenplays.create_element(screenplay, %{
            type: "action",
            content: "Opening action"
          })

        %{user: user, project: project, screenplay: screenplay}
      end)

    on_exit(fn -> cleanup(state) end)

    parent = self()
    barrier = make_ref()
    gate = :atomics.new(1, signed: false)
    handler_id = "flow-sync-first-link-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        fn _event, _measurements, %{query: query}, {test_pid, ref, gate_ref} ->
          if String.contains?(query, ~s(FROM "screenplays")) and
               Regex.match?(~r/WHERE .*"id"\s*=/, query) and
               :atomics.compare_exchange(gate_ref, 1, 0, 1) == :ok do
            send(test_pid, {ref, :screenplay_read, self()})

            receive do
              {^ref, :continue} -> :ok
            after
              @timeout -> exit(:screenplay_gate_timeout)
            end
          end
        end,
        {parent, barrier, gate}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    first_sync =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Screenplays.sync_to_flow(state.screenplay)
        end)
      end)

    assert_receive {^barrier, :screenplay_read, first_sync_pid}, @timeout

    second_sync =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {barrier, :second_sync_started, backend_pid})
          Screenplays.sync_to_flow(state.screenplay)
        end)
      end)

    assert_receive {^barrier, :second_sync_started, second_backend_pid}, @timeout
    second_state = wait_until_completed_or_blocked(second_sync, second_backend_pid)

    send(first_sync_pid, {barrier, :continue})

    assert {:ok, first_flow} = Task.await(first_sync, @timeout)

    second_result =
      case second_state do
        {:completed, result} -> result
        :blocked -> Task.await(second_sync, @timeout)
      end

    assert {:ok, second_flow} = second_result
    assert first_flow.id == second_flow.id

    Sandbox.unboxed_run(Repo, fn ->
      screenplay = Repo.get!(Screenplay, state.screenplay.id)
      assert screenplay.linked_flow_id == first_flow.id

      assert Repo.aggregate(
               from(flow in Flow,
                 where:
                   flow.project_id == ^state.project.id and
                     is_nil(flow.deleted_at)
               ),
               :count,
               :id
             ) == 1
    end)
  end

  test "reverse sync does not recreate a flow after a concurrent unlink" do
    state =
      Sandbox.unboxed_run(Repo, fn ->
        user =
          user_fixture(%{
            email: "flow-sync-reverse-unlink-#{Ecto.UUID.generate()}@example.com"
          })

        project = project_fixture(user)
        screenplay = screenplay_fixture(project, %{name: "Concurrent reverse sync"})

        {:ok, _action} =
          Screenplays.create_element(screenplay, %{
            type: "action",
            content: "Opening action"
          })

        {:ok, flow} = Screenplays.sync_to_flow(screenplay)

        %{
          user: user,
          project: project,
          screenplay: screenplay,
          flow: flow
        }
      end)

    on_exit(fn -> cleanup(state) end)

    parent = self()
    barrier = make_ref()
    gate = :atomics.new(1, signed: false)
    handler_id = "flow-sync-reverse-unlink-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        fn _event, _measurements, %{query: query}, {test_pid, ref, gate_ref} ->
          if String.contains?(query, ~s(UPDATE "screenplays")) and
               String.contains?(query, ~s("linked_flow_id")) and
               :atomics.compare_exchange(gate_ref, 1, 0, 1) == :ok do
            send(test_pid, {ref, :screenplay_unlinked, self()})

            receive do
              {^ref, :continue} -> :ok
            after
              @timeout -> exit(:unlink_gate_timeout)
            end
          end
        end,
        {parent, barrier, gate}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    unlinker =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Screenplays.unlink_flow(state.screenplay)
        end)
      end)

    assert_receive {^barrier, :screenplay_unlinked, unlink_pid}, @timeout

    reverse_sync =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {barrier, :reverse_sync_started, backend_pid})
          Screenplays.sync_from_flow(state.screenplay)
        end)
      end)

    assert_receive {^barrier, :reverse_sync_started, reverse_backend_pid}, @timeout
    assert :blocked = wait_until_completed_or_blocked(reverse_sync, reverse_backend_pid)

    send(unlink_pid, {barrier, :continue})

    assert {:ok, %{linked_flow_id: nil}} = Task.await(unlinker, @timeout)
    assert {:error, :not_linked} = Task.await(reverse_sync, @timeout)

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.reload!(state.screenplay).linked_flow_id == nil

      assert Repo.aggregate(
               from(flow in Flow,
                 where:
                   flow.project_id == ^state.project.id and
                     is_nil(flow.deleted_at)
               ),
               :count,
               :id
             ) == 1
    end)
  end

  defp wait_until_completed_or_blocked(task, backend_pid) do
    deadline = System.monotonic_time(:millisecond) + @timeout
    do_wait_until_completed_or_blocked(task, backend_pid, deadline)
  end

  defp do_wait_until_completed_or_blocked(task, backend_pid, deadline) do
    case Task.yield(task, 0) do
      {:ok, result} ->
        {:completed, result}

      nil ->
        cond do
          backend_blocked?(backend_pid) ->
            :blocked

          System.monotonic_time(:millisecond) >= deadline ->
            flunk("second sync neither completed nor reached a database lock")

          true ->
            Process.sleep(10)
            do_wait_until_completed_or_blocked(task, backend_pid, deadline)
        end
    end
  end

  defp backend_blocked?(backend_pid) do
    [[blocking_count]] =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!(
          "SELECT cardinality(pg_blocking_pids($1))",
          [backend_pid]
        )
      end).rows

    blocking_count > 0
  end

  defp blocking_details(backend_pid) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!(
        """
        SELECT blocked.query, blocked.wait_event, blocker.pid, blocker.query
        FROM pg_stat_activity AS blocked
        JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) AS blocker_pid(pid) ON TRUE
        JOIN pg_stat_activity AS blocker ON blocker.pid = blocker_pid.pid
        WHERE blocked.pid = $1
        """,
        [backend_pid]
      ).rows
    end)
  end

  defp row_locked?(table, id) when table in ["projects", "screenplays", "flows"] do
    fn ->
      Sandbox.unboxed_run(Repo, fn ->
        try do
          Repo.transaction(fn ->
            Repo.query!("SELECT id FROM #{table} WHERE id = $1 FOR UPDATE NOWAIT", [id])
          end)

          false
        rescue
          error in Postgrex.Error ->
            error.postgres.code == :lock_not_available
        end
      end)
    end
    |> Task.async()
    |> Task.await(@timeout)
  end

  defp cleanup(%{user: user, project: project}) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.delete_all(from(current in Project, where: current.id == ^project.id))
      Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
      Repo.delete_all(from(current in User, where: current.id == ^user.id))
    end)
  end
end
