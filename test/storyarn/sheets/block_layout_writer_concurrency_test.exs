defmodule Storyarn.Sheets.BlockLayoutWriterConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Workspaces.Workspace

  @barrier_timeout 15_000

  test "inverse layout payloads serialize without deadlocking or leaving a partial layout" do
    unboxed_scenario(fn %{project: project} ->
      sheet = sheet_fixture(project)
      first = block_fixture(sheet, %{config: %{"label" => "First"}, position: 0})
      second = block_fixture(sheet, %{config: %{"label" => "Second"}, position: 1})
      third = block_fixture(sheet, %{config: %{"label" => "Third"}, position: 2})

      Enum.each(1..4, fn _attempt ->
        [
          fn -> Sheets.reorder_blocks(sheet.id, [first.id, second.id, third.id]) end,
          fn -> Sheets.reorder_blocks(sheet.id, [third.id, second.id, first.id]) end
        ]
        |> run_concurrently()
        |> Enum.each(fn result ->
          assert {:ok, [_first, _second, _third]} = result
        end)

        blocks = Sheets.list_blocks(sheet.id)
        assert Enum.sort(Enum.map(blocks, & &1.id)) == Enum.sort([first.id, second.id, third.id])
        assert Enum.sort(Enum.map(blocks, & &1.position)) == [0, 1, 2]

        [
          fn -> Sheets.create_column_group(sheet.id, [first.id, second.id, third.id]) end,
          fn -> Sheets.create_column_group(sheet.id, [third.id, second.id, first.id]) end
        ]
        |> run_concurrently()
        |> Enum.each(fn result ->
          assert {:ok, group_id} = result
          assert is_binary(group_id)
        end)

        grouped = Sheets.list_blocks(sheet.id)
        assert grouped |> Enum.map(& &1.column_group_id) |> Enum.uniq() |> length() == 1
        assert Enum.sort(Enum.map(grouped, & &1.column_index)) == [0, 1, 2]
      end)
    end)
  end

  test "concurrent variable renames produce deterministic unique persisted names" do
    unboxed_scenario(fn %{project: project} ->
      sheet = sheet_fixture(project)
      first = block_fixture(sheet, %{config: %{"label" => "First"}})
      second = block_fixture(sheet, %{config: %{"label" => "Second"}})

      results =
        run_concurrently([
          fn -> Sheets.update_variable_name(first, "shared") end,
          fn -> Sheets.update_variable_name(second, "shared") end
        ])

      Enum.each(results, fn result ->
        assert {:ok, _block} = result
      end)

      assert sheet.id
             |> Sheets.list_blocks()
             |> Enum.map(& &1.variable_name)
             |> Enum.sort() == ["shared", "shared_2"]
    end)
  end

  defp run_concurrently(writers) do
    barrier = make_ref()
    owner = self()

    tasks =
      Enum.map(writers, &concurrent_writer_task(&1, owner, barrier))

    task_pids =
      Enum.map(tasks, fn _task ->
        assert_receive {^barrier, :ready, task_pid}, @barrier_timeout
        task_pid
      end)

    Enum.each(task_pids, &send(&1, {barrier, :write}))
    Enum.map(tasks, &Task.await(&1, @barrier_timeout))
  end

  defp concurrent_writer_task(writer, owner, barrier) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        await_concurrent_write(owner, barrier, writer)
      end)
    end)
  end

  defp await_concurrent_write(owner, barrier, writer) do
    send(owner, {barrier, :ready, self()})

    receive do
      {^barrier, :write} -> writer.()
    after
      @barrier_timeout -> exit(:writer_barrier_timeout)
    end
  end

  defp unboxed_scenario(test_fun) do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "block-layout-concurrency-#{Ecto.UUID.generate()}@example.com"
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
