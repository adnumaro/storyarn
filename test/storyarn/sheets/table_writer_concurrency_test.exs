defmodule Storyarn.Sheets.TableWriterConcurrencyTest do
  use Storyarn.DataCase, async: false

  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block

  test "TableCrud and BlockCrud serialize at Project before either locks the table block" do
    project = project_fixture()
    sheet = sheet_fixture(project)
    table = table_block_fixture(sheet)

    {:ok, removable_column} =
      Sheets.create_table_column(table, %{name: "Removable", type: "text"})

    holder = hold_project_lock(project.id)
    parent = self()

    block_task =
      Task.async(fn ->
        send(parent, :block_writer_started)
        Sheets.update_block_config(table, Map.put(table.config, "collapsed", true))
      end)

    assert_receive :block_writer_started
    refute Task.yield(block_task, 100)

    table_task =
      Task.async(fn ->
        send(parent, :table_writer_started)
        Sheets.delete_table_column(removable_column)
      end)

    assert_receive :table_writer_started
    refute Task.yield(table_task, 100)

    release_project_lock(holder)

    assert {:ok, %Block{}} = Task.await(block_task, 5_000)
    assert {:ok, _column} = Task.await(table_task, 5_000)
    assert length(Sheets.list_table_columns(table.id)) == 1
  end

  defp hold_project_lock(project_id) do
    parent = self()

    holder =
      Task.async(fn ->
        Repo.transaction(fn ->
          Repo.one!(
            from(project in Storyarn.Projects.Project,
              where: project.id == ^project_id,
              lock: "FOR UPDATE"
            )
          )

          send(parent, {:project_lock_held, self()})

          receive do
            :release_project_lock -> :ok
          end
        end)
      end)

    assert_receive {:project_lock_held, holder_pid}
    %{task: holder, pid: holder_pid}
  end

  defp release_project_lock(%{task: task, pid: pid}) do
    send(pid, :release_project_lock)
    assert {:ok, :ok} = Task.await(task, 5_000)
  end
end
