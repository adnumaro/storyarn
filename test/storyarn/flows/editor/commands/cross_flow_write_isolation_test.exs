defmodule Storyarn.Flows.CrossFlowWriteIsolationTest do
  @moduledoc """
  Editing one flow must not stall editors working on a sibling flow.

  Every flow write locks the project row before the flow and node rows.
  That project lock is the shared choke point: taken as `FOR UPDATE` it
  would serialize every editor in the project behind whichever write got
  there first, which is invisible in single-connection tests and shows up
  in production as the canvas freezing while a colleague saves.

  This property used to be covered end-to-end by the Screenplays flow-sync
  concurrency suite, which was deleted with that feature. The guarantee is
  a Flows one, so it is asserted here directly against two flows instead.
  """
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Flows
  alias Storyarn.Flows.ReferenceIntegrity
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @timeout 10_000

  test "a held write on one flow does not block a write on a sibling flow" do
    state =
      Sandbox.unboxed_run(Repo, fn ->
        user = user_fixture(%{email: "cross-flow-isolation-#{Ecto.UUID.generate()}@example.com"})
        project = project_fixture(user)

        {:ok, flow_a} = Flows.create_flow(project, %{name: "Flow A"})
        {:ok, flow_b} = Flows.create_flow(project, %{name: "Flow B"})

        %{
          user: user,
          project: project,
          node_a: exit_node(flow_a),
          node_b: exit_node(flow_b)
        }
      end)

    on_exit(fn -> cleanup(state) end)

    parent = self()
    barrier = make_ref()

    # Holder: takes the same project → flow → node lock chain an editor
    # write takes, then sits on it until released.
    holder =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            {:ok, _locked} = ReferenceIntegrity.lock_active_node_for_write(state.node_a, :key_share)
            send(parent, {barrier, :holding})

            receive do
              {^barrier, :release} -> :ok
            after
              @timeout -> exit(:holder_gate_timeout)
            end
          end)
        end)
      end)

    assert_receive {^barrier, :holding}, @timeout

    editor =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {barrier, :editor_started, backend_pid})

          Flows.update_node_position(state.node_b, %{position_x: state.node_b.position_x + 25})
        end)
      end)

    assert_receive {^barrier, :editor_started, editor_backend_pid}, @timeout
    editor_state = wait_until_completed_or_blocked(editor, editor_backend_pid)
    blocking = blocking_details(editor_backend_pid)

    send(holder.pid, {barrier, :release})
    assert {:ok, _} = Task.await(holder, @timeout)

    editor_result =
      case editor_state do
        {:completed, result} -> result
        :blocked -> Task.await(editor, @timeout)
      end

    assert match?({:completed, _}, editor_state),
           "a write on flow #{state.node_b.flow_id} blocked behind a write on flow " <>
             "#{state.node_a.flow_id} of the same project; blocked by #{inspect(blocking)}"

    assert {:ok, updated} = editor_result
    assert updated.position_x == state.node_b.position_x + 25
  end

  defp exit_node(flow) do
    flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "exit"))
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
            flunk("the sibling-flow write neither completed nor reached a database lock")

          true ->
            Process.sleep(10)
            do_wait_until_completed_or_blocked(task, backend_pid, deadline)
        end
    end
  end

  defp backend_blocked?(backend_pid) do
    [[blocking_count]] =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("SELECT cardinality(pg_blocking_pids($1))", [backend_pid])
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

  defp cleanup(%{user: user, project: project}) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.delete_all(from(current in Project, where: current.id == ^project.id))
      Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
      Repo.delete_all(from(current in User, where: current.id == ^user.id))
    end)
  end
end
