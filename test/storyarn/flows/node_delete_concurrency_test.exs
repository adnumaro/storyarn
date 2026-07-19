defmodule Storyarn.Flows.NodeDeleteConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @timeout 15_000

  test "concurrent exit deletes preserve exactly one active exit" do
    unboxed_scenario(fn %{flow: flow} ->
      original_exit =
        flow.id
        |> Flows.list_nodes()
        |> Enum.find(&(&1.type == "exit"))

      {:ok, extra_exit} =
        Flows.create_node(flow, %{
          type: "exit",
          data: %{"label" => "Extra", "exit_mode" => "terminal"}
        })

      results =
        run_concurrently([
          fn -> Flows.delete_node(original_exit) end,
          fn -> Flows.delete_node(extra_exit) end
        ])

      assert Enum.count(results, &match?({:ok, %FlowNode{}, _meta}, &1)) == 1
      assert {:error, :cannot_delete_last_exit} in results

      assert Repo.aggregate(
               from(node in FlowNode,
                 where:
                   node.flow_id == ^flow.id and node.type == "exit" and
                     is_nil(node.deleted_at)
               ),
               :count
             ) == 1
    end)
  end

  test "sequence delete and child reparent serialize without deadlock or dangling parent" do
    unboxed_scenario(fn %{flow: flow} ->
      {:ok, sequence} = Flows.create_sequence(flow.id, %{"name" => "Sequence"})
      child = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Child"}})

      [delete_result, reparent_result] =
        run_concurrently([
          fn -> Flows.delete_sequence(sequence) end,
          fn -> Flows.update_node_parent(child, sequence.id) end
        ])

      assert {:ok, %FlowNode{deleted_at: %DateTime{}}} = delete_result

      assert match?({:ok, %FlowNode{}}, reparent_result) or
               match?({:error, {:invalid_node_parent, _parent_id}}, reparent_result)

      assert Repo.get!(FlowNode, sequence.id).deleted_at
      assert Repo.get!(FlowNode, child.id).parent_id == nil
    end)
  end

  defp run_concurrently(operations) do
    parent = self()
    barrier = make_ref()

    tasks =
      Enum.map(operations, fn operation ->
        Task.async(fn -> run_after_barrier(operation, parent, barrier) end)
      end)

    Enum.each(tasks, fn _task ->
      assert_receive {^barrier, :ready, task_pid}, @timeout
      assert task_pid in Enum.map(tasks, & &1.pid)
    end)

    Enum.each(tasks, &send(&1.pid, {barrier, :run}))
    Enum.map(tasks, &Task.await(&1, @timeout))
  end

  defp run_after_barrier(operation, parent, barrier) do
    Sandbox.unboxed_run(Repo, fn ->
      send(parent, {barrier, :ready, self()})

      receive do
        {^barrier, :run} -> operation.()
      after
        @timeout -> exit(:writer_barrier_timeout)
      end
    end)
  end

  defp unboxed_scenario(test_fun) do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "node-delete-concurrency-#{Ecto.UUID.generate()}@example.com"
        })

      project = project_fixture(user)
      flow = flow_fixture(project)

      try do
        test_fun.(%{
          user: user,
          project: project,
          flow: flow,
          workspace_id: project.workspace_id
        })
      after
        Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
        Repo.delete_all(from(user_row in User, where: user_row.id == ^user.id))
      end
    end)
  end
end
