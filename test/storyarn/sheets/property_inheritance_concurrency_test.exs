defmodule Storyarn.Sheets.PropertyInheritanceConcurrencyTest do
  use Storyarn.DataCase, async: false

  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.PropertyInheritance
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow

  test "inherited propagation and direct creation allocate distinct child positions" do
    project = project_fixture()
    parent = sheet_fixture(project, %{name: "Parent"})
    child = child_sheet_fixture(project, parent, %{name: "Child"})

    operations = [
      fn ->
        Sheets.create_block(parent, %{
          type: "text",
          scope: "children",
          config: %{"label" => "Inherited"},
          value: %{"content" => ""}
        })
      end,
      fn ->
        Sheets.create_block(child, %{
          type: "text",
          config: %{"label" => "Local"},
          value: %{"content" => ""}
        })
      end
    ]

    results =
      operations
      |> Task.async_stream(& &1.(), max_concurrency: 2, ordered: false, timeout: :infinity)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _block}, &1))

    child_blocks = Sheets.list_blocks(child.id)
    assert length(child_blocks) == 2
    assert child_blocks |> Enum.map(& &1.position) |> Enum.uniq() |> length() == 2
  end

  test "concurrent moves share project position allocation" do
    project = project_fixture()
    target = sheet_fixture(project, %{name: "Target"})
    first = sheet_fixture(project, %{name: "First"})
    second = sheet_fixture(project, %{name: "Second"})

    moved =
      [first, second]
      |> Task.async_stream(&Sheets.move_sheet(&1, target.id),
        max_concurrency: 2,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, {:ok, sheet}} -> sheet end)

    assert moved |> Enum.map(& &1.position) |> Enum.uniq() |> length() == 2
  end

  test "opposite moves revalidate parentage after taking the project lock" do
    project = project_fixture()
    first = sheet_fixture(project, %{name: "First"})
    second = sheet_fixture(project, %{name: "Second"})
    holder = hold_project_lock(project.id)
    parent = self()

    movers =
      Enum.map([{first, second.id}, {second, first.id}], fn {sheet, parent_id} ->
        Task.async(fn ->
          send(parent, {:move_started, self()})
          Sheets.move_sheet(sheet, parent_id)
        end)
      end)

    assert_receive {:move_started, _pid}
    assert_receive {:move_started, _pid}
    Process.sleep(100)
    release_project_lock(holder)

    results = Enum.map(movers, &Task.await(&1, 5_000))

    assert Enum.count(results, &match?({:ok, _sheet}, &1)) == 1
    assert {:error, :would_create_cycle} in results
  end

  test "positioned moves and reorders wait for the project serialization lock" do
    project = project_fixture()
    target = sheet_fixture(project, %{name: "Target"})
    moving = sheet_fixture(project, %{name: "Moving"})
    sibling = sheet_fixture(project, %{name: "Sibling"})
    parent = self()

    move_holder = hold_project_lock(project.id)

    move_task =
      Task.async(fn ->
        send(parent, :positioned_move_started)
        result = Sheets.move_sheet_to_position(moving, target.id, 0)
        send(parent, {:positioned_move_finished, result})
        result
      end)

    assert_receive :positioned_move_started
    refute_receive {:positioned_move_finished, _result}, 100
    release_project_lock(move_holder)
    assert {:ok, _moved} = Task.await(move_task, 5_000)
    assert_receive {:positioned_move_finished, {:ok, _moved}}

    reorder_holder = hold_project_lock(project.id)

    reorder_task =
      Task.async(fn ->
        send(parent, :reorder_started)
        result = Sheets.reorder_sheets(project.id, nil, [sibling.id, target.id])
        send(parent, {:reorder_finished, result})
        result
      end)

    assert_receive :reorder_started
    refute_receive {:reorder_finished, _result}, 100
    release_project_lock(reorder_holder)
    assert {:ok, _sheets} = Task.await(reorder_task, 5_000)
    assert_receive {:reorder_finished, {:ok, _sheets}}
  end

  test "nested propagation locks sheets in hierarchy order even when ids run backwards" do
    project = project_fixture()
    leaf = sheet_fixture(project, %{name: "Leaf"})
    middle = sheet_fixture(project, %{name: "Middle"})
    {:ok, leaf} = Sheets.move_sheet(leaf, middle.id)
    root = sheet_fixture(project, %{name: "Root"})
    {:ok, middle} = Sheets.move_sheet(middle, root.id)

    assert root.id > middle.id
    assert middle.id > leaf.id

    attrs = fn label ->
      %{
        type: "text",
        scope: "children",
        config: %{"label" => label},
        value: %{"content" => ""}
      }
    end

    results =
      [{root, attrs.("Root field")}, {middle, attrs.("Middle field")}]
      |> Task.async_stream(fn {sheet, block_attrs} -> Sheets.create_block(sheet, block_attrs) end,
        max_concurrency: 2,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, %Block{}}, &1))
  end

  test "propagation reloads the locked table source before copying structure" do
    project = project_fixture()
    parent = sheet_fixture(project, %{name: "Parent"})
    child = child_sheet_fixture(project, parent, %{name: "Child"})
    table = table_block_fixture(parent)
    stale_parent = %{table | type: "text"}

    assert {:ok, 1} = PropertyInheritance.create_inherited_instances(stale_parent, [child.id])

    instance =
      Repo.one!(
        from(b in Block,
          where: b.sheet_id == ^child.id and b.inherited_from_block_id == ^table.id
        )
      )

    assert instance.type == "table"

    assert Repo.aggregate(from(c in TableColumn, where: c.block_id == ^instance.id), :count) ==
             length(table.table_columns)

    assert Repo.aggregate(from(r in TableRow, where: r.block_id == ^instance.id), :count) ==
             length(table.table_rows)
  end

  defp hold_project_lock(project_id) do
    parent = self()

    holder =
      Task.async(fn ->
        Repo.transaction(fn ->
          Repo.one!(from(p in Storyarn.Projects.Project, where: p.id == ^project_id, lock: "FOR UPDATE"))
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
