defmodule Storyarn.Flows.StaleVariableReferenceRepairConcurrencyTest do
  @moduledoc """
  Exercises stale variable repair against real PostgreSQL concurrency.

  Independent unboxed connections are required here: a shared SQL sandbox
  connection would serialize the calls before PostgreSQL can exercise the
  Project and Flow-node lock protocol.
  """
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Workspaces.Workspace

  @timeout 15_000

  test "an ordinary node edit and stale-reference repair preserve both changes" do
    unboxed_scenario(fn state ->
      [repair_result, edit_result] =
        run_concurrently([
          fn -> Flows.repair_stale_variable_references(state.project.id) end,
          fn ->
            Flows.edit_node(state.flow.id, state.node.id, :put_field, %{
              field: "description",
              value: "Concurrent edit"
            })
          end
        ])

      # If the ordinary edit acquires the lock first, its regular reference
      # normalization fixes the stale identity and the explicit repair becomes
      # a no-op. If repair wins first it reports one. Both serializations must
      # preserve the edited field and the repaired variable identity.
      assert repair_result in [{:ok, 0}, {:ok, 1}]
      assert {:ok, %{node: edited_node}} = edit_result
      assert edited_node.id == state.node.id

      persisted = Flows.get_node!(state.flow.id, state.node.id)

      persisted_references =
        Repo.all(
          from(reference in VariableReference,
            where:
              reference.source_type == "flow_node" and
                reference.source_id == ^state.node.id
          )
        )

      assert persisted.data["description"] == "Concurrent edit"

      assert hd(persisted.data["assignments"])["sheet"] == state.renamed_shortcut,
             "repair=#{inspect(repair_result)} edit=#{inspect(edit_result)} " <>
               "persisted=#{inspect(persisted.data)} references=#{inspect(persisted_references)}"

      assert hd(persisted.data["assignments"])["variable"] == state.block.variable_name
    end)
  end

  test "two concurrent repairs serialize into one repair and one no-op" do
    unboxed_scenario(fn state ->
      results =
        run_concurrently([
          fn -> Flows.repair_stale_variable_references(state.project.id) end,
          fn -> Flows.repair_stale_variable_references(state.project.id) end
        ])

      assert Enum.sort(results) == [{:ok, 0}, {:ok, 1}]

      persisted = Flows.get_node!(state.flow.id, state.node.id)
      assert hd(persisted.data["assignments"])["sheet"] == state.renamed_shortcut
      assert hd(persisted.data["assignments"])["variable"] == state.block.variable_name
    end)
  end

  test "a hard delete after candidate discovery remains a successful no-op" do
    unboxed_scenario(fn state ->
      parent = self()
      release_delete = make_ref()

      delete_task =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Repo.transaction(fn ->
              locked_node =
                Repo.one!(
                  from(node in FlowNode,
                    where: node.id == ^state.node.id,
                    lock: "FOR UPDATE"
                  )
                )

              send(parent, {:hard_delete_lock_held, self()})

              receive do
                {^release_delete, :continue} -> Repo.delete!(locked_node)
              after
                @timeout -> exit(:hard_delete_release_timeout)
              end
            end)
          end)
        end)

      assert_receive {:hard_delete_lock_held, delete_pid}, @timeout
      assert delete_pid == delete_task.pid

      repair_task =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            %{rows: [[backend_pid]]} = Repo.query!("SELECT pg_backend_pid()")
            send(parent, {:repair_backend, backend_pid})
            Flows.repair_stale_variable_references(state.project.id)
          end)
        end)

      assert_receive {:repair_backend, backend_pid}, @timeout
      assert :waiting_for_lock = wait_for_lock_or_completion(repair_task, backend_pid)

      send(delete_task.pid, {release_delete, :continue})
      assert {:ok, %FlowNode{id: deleted_id}} = Task.await(delete_task, @timeout)
      assert deleted_id == state.node.id
      assert {:ok, 0} = Task.await(repair_task, @timeout)
      assert is_nil(Repo.get(FlowNode, state.node.id))
    end)
  end

  defp run_concurrently(operations) do
    parent = self()
    barrier = make_ref()

    tasks =
      Enum.map(operations, fn operation ->
        Task.async(fn -> run_unboxed_operation(parent, barrier, operation) end)
      end)

    task_pids = Enum.map(tasks, & &1.pid)

    Enum.each(tasks, fn _task ->
      assert_receive {^barrier, :ready, task_pid}, @timeout
      assert task_pid in task_pids
    end)

    Enum.each(tasks, &send(&1.pid, {barrier, :run}))
    Enum.map(tasks, &Task.await(&1, @timeout))
  end

  defp run_unboxed_operation(parent, barrier, operation) do
    Sandbox.unboxed_run(Repo, fn ->
      send(parent, {barrier, :ready, self()})

      receive do
        {^barrier, :run} -> operation.()
      after
        @timeout -> exit(:stale_variable_reference_repair_barrier_timeout)
      end
    end)
  end

  defp wait_for_lock_or_completion(task, backend_pid) do
    deadline = System.monotonic_time(:millisecond) + @timeout
    wait_for_lock_or_completion(task, backend_pid, deadline)
  end

  defp wait_for_lock_or_completion(task, backend_pid, deadline) do
    case Task.yield(task, 0) do
      {:ok, result} ->
        {:completed_without_waiting, result}

      {:exit, reason} ->
        {:exited_without_waiting, reason}

      nil ->
        %{rows: rows} =
          Repo.query!(
            "SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1",
            [backend_pid]
          )

        cond do
          rows == [["Lock"]] ->
            :waiting_for_lock

          System.monotonic_time(:millisecond) >= deadline ->
            :lock_wait_timeout

          true ->
            Process.sleep(10)
            wait_for_lock_or_completion(task, backend_pid, deadline)
        end
    end
  end

  defp unboxed_scenario(test_fun) do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "flow-variable-repair-concurrency-#{Ecto.UUID.generate()}@example.com"
        })

      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "Variables", shortcut: "variables"})

      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      flow = flow_fixture(project, %{name: "Repair race"})

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "description" => "Original description",
            "assignments" => [
              %{
                "id" => "assignment-1",
                "sheet" => sheet.shortcut,
                "variable" => block.variable_name,
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      renamed_shortcut = "renamed-variables"
      assert {:ok, _sheet} = Sheets.update_sheet(sheet, %{shortcut: renamed_shortcut})

      try do
        test_fun.(%{
          user: user,
          project: project,
          flow: flow,
          node: node,
          block: block,
          renamed_shortcut: renamed_shortcut
        })
      after
        Repo.delete_all(from(current in Project, where: current.id == ^project.id))
        Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
        Repo.delete_all(from(current in User, where: current.id == ^user.id))
      end
    end)
  end
end
