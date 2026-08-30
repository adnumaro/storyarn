defmodule Storyarn.Flows.References.Commands.EntityReferenceTrackerConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.References
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Workspaces.Workspace

  @barrier_timeout 15_000
  @blocked_timeout 5_000

  test "Flow-node reference rebuild serializes with deleting its owning Flow" do
    unboxed_scenario(fn %{project: project} ->
      target = sheet_fixture(project, %{name: "Dialogue target"})
      flow = flow_fixture(project, %{name: "Rebuild source"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => target.id, "text" => "Hello"}
        })

      assert Sheets.count_backlinks("sheet", target.id) == 1

      parent = self()
      barrier = make_ref()

      flow_gate =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            hold_flow_lock(flow.id, parent, barrier)
          end)
        end)

      assert_receive {^barrier, :flow_locked, gate_backend_pid}, @barrier_timeout

      rebuilder =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
            send(parent, {barrier, :rebuilder_ready, backend_pid})

            References.update_entity_references(node,
              project_id: project.id
            )
          end)
        end)

      assert_receive {^barrier, :rebuilder_ready, rebuilder_backend_pid}, @barrier_timeout
      assert wait_until_blocked_by(rebuilder_backend_pid, gate_backend_pid)

      deleter =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
            send(parent, {barrier, :deleter_ready, backend_pid})
            Flows.delete_flow(flow)
          end)
        end)

      assert_receive {^barrier, :deleter_ready, deleter_backend_pid}, @barrier_timeout
      assert wait_until_blocked_by(deleter_backend_pid, rebuilder_backend_pid)

      send(flow_gate.pid, {barrier, :release_gate})

      assert :ok = Task.await(rebuilder, @barrier_timeout)
      assert {:ok, deleted_flow} = Task.await(deleter, @barrier_timeout)
      assert deleted_flow.id == flow.id
      assert deleted_flow.deleted_at
      assert {:ok, :released} = Task.await(flow_gate, @barrier_timeout)
      assert Sheets.count_backlinks("sheet", target.id) == 1
    end)
  end

  defp hold_flow_lock(flow_id, parent, barrier) do
    Repo.transaction(fn ->
      [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows

      Repo.one!(
        from(flow in Flow,
          where: flow.id == ^flow_id,
          select: flow.id,
          lock: "FOR UPDATE"
        )
      )

      send(parent, {barrier, :flow_locked, backend_pid})

      receive do
        {^barrier, :release_gate} -> :released
      after
        @barrier_timeout -> exit(:gate_release_timeout)
      end
    end)
  end

  defp wait_until_blocked_by(backend_pid, blocker_pid) do
    deadline = System.monotonic_time(:millisecond) + @blocked_timeout
    do_wait_until_blocked_by(backend_pid, blocker_pid, deadline)
  end

  defp do_wait_until_blocked_by(backend_pid, blocker_pid, deadline) do
    [[blocking_pids]] =
      Repo.query!(
        "SELECT pg_blocking_pids($1)",
        [backend_pid]
      ).rows

    cond do
      blocker_pid in blocking_pids ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(10)
        do_wait_until_blocked_by(backend_pid, blocker_pid, deadline)
    end
  end

  defp unboxed_scenario(test_fun) do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "flow-reference-writer-concurrency-#{Ecto.UUID.generate()}@example.com"
        })

      project = project_fixture(user)

      try do
        test_fun.(%{user: user, project: project})
      after
        Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
        Repo.delete_all(from(user in User, where: user.id == ^user.id))
      end
    end)
  end
end
