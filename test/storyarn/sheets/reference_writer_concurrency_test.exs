defmodule Storyarn.Sheets.ReferenceWriterConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.EntityReference
  alias Storyarn.Sheets.ReferenceTracker
  alias Storyarn.Workspaces.Workspace

  @barrier_timeout 15_000

  test "two reference rebuilds do not upgrade their shared target locks" do
    unboxed_scenario(fn %{project: project} ->
      target = sheet_fixture(project, %{name: "Shared target"})
      first = reference_block_fixture(project, "First source")
      second = reference_block_fixture(project, "Second source")
      barrier = make_ref()

      tasks =
        Enum.map([first, second], fn block ->
          rebuild_after_target_lock(self(), barrier, project.id, block.id, target.id)
        end)

      locked_pids =
        Enum.map(tasks, fn _task ->
          assert_receive {^barrier, :target_locked, task_pid}, @barrier_timeout
          task_pid
        end)

      assert MapSet.new(locked_pids) == MapSet.new(Enum.map(tasks, & &1.pid))

      Enum.each(tasks, &send(&1.pid, {barrier, :rebuild}))

      assert Enum.map(tasks, &Task.await(&1, @barrier_timeout)) ==
               [{:ok, :ok}, {:ok, :ok}]

      assert Repo.aggregate(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "block" and
                     reference.source_id in ^[first.id, second.id] and
                     reference.target_type == "sheet" and
                     reference.target_id == ^target.id
               ),
               :count
             ) == 2
    end)
  end

  test "reciprocal block references serialize instead of deadlocking" do
    unboxed_scenario(fn %{project: project} ->
      first_sheet = sheet_fixture(project, %{name: "First"})
      second_sheet = sheet_fixture(project, %{name: "Second"})
      first = blank_reference_block(first_sheet)
      second = blank_reference_block(second_sheet)

      Enum.each(1..4, fn _attempt ->
        barrier = make_ref()

        first_writer =
          concurrent_writer(self(), barrier, fn ->
            Sheets.update_block_value(first, %{
              "target_type" => "sheet",
              "target_id" => second_sheet.id
            })
          end)

        second_writer =
          concurrent_writer(self(), barrier, fn ->
            Sheets.update_block_value(second, %{
              "target_type" => "sheet",
              "target_id" => first_sheet.id
            })
          end)

        assert_receive {^barrier, :ready, first_pid}, @barrier_timeout
        assert_receive {^barrier, :ready, second_pid}, @barrier_timeout
        assert MapSet.new([first_pid, second_pid]) == MapSet.new([first_writer.pid, second_writer.pid])

        send(first_writer.pid, {barrier, :write})
        send(second_writer.pid, {barrier, :write})

        assert {:ok, %Block{}} = Task.await(first_writer, @barrier_timeout)
        assert {:ok, %Block{}} = Task.await(second_writer, @barrier_timeout)
      end)
    end)
  end

  defp rebuild_after_target_lock(parent, barrier, project_id, block_id, target_id) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        rebuild_locked_reference(parent, barrier, project_id, block_id, target_id)
      end)
    end)
  end

  defp rebuild_locked_reference(parent, barrier, project_id, block_id, target_id) do
    Repo.transaction(fn ->
      assert {:ok, _project} =
               ProjectReferenceIntegrity.lock_active_project(project_id)

      assert {:ok, [^target_id]} =
               ProjectReferenceIntegrity.lock_active_references(project_id, [
                 {:sheet, :concurrent_rebuild_target, target_id}
               ])

      send(parent, {barrier, :target_locked, self()})

      receive do
        {^barrier, :rebuild} -> :ok
      after
        @barrier_timeout -> exit(:rebuild_barrier_timeout)
      end

      block =
        Block
        |> Repo.get!(block_id)
        |> Map.put(:value, %{"target_type" => "sheet", "target_id" => target_id})

      assert :ok =
               ReferenceTracker.update_block_references(block,
                 project_id: project_id
               )

      :ok
    end)
  end

  defp concurrent_writer(parent, barrier, writer) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        send(parent, {barrier, :ready, self()})

        receive do
          {^barrier, :write} -> writer.()
        after
          @barrier_timeout -> exit(:writer_barrier_timeout)
        end
      end)
    end)
  end

  defp reference_block_fixture(project, sheet_name) do
    project
    |> sheet_fixture(%{name: sheet_name})
    |> blank_reference_block()
  end

  defp blank_reference_block(sheet) do
    block_fixture(sheet, %{
      type: "reference",
      value: %{"target_type" => nil, "target_id" => nil}
    })
  end

  defp unboxed_scenario(test_fun) do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "reference-writer-concurrency-#{Ecto.UUID.generate()}@example.com"
        })

      project = project_fixture(user)

      try do
        test_fun.(%{
          user: user,
          project: project,
          workspace_id: project.workspace_id
        })
      after
        cleanup_scenario(project.workspace_id, user.id)
      end
    end)
  end

  defp cleanup_scenario(workspace_id, user_id) do
    Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^workspace_id))
    Repo.delete_all(from(user in User, where: user.id == ^user_id))
  end
end
