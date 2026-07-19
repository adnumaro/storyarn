defmodule Storyarn.Versioning.VersionConcurrencyTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Versioning
  alias Storyarn.Versioning.SnapshotStorage

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
    sheet = Repo.preload(sheet, :blocks, force: true)

    flow = flow_fixture(project)
    _node = node_fixture(flow, %{type: "dialogue"})

    %{user: user, project: project, sheet: sheet}
  end

  test "concurrent entity version creation keeps every stored snapshot", %{
    project: project,
    sheet: sheet,
    user: user
  } do
    versions =
      5
      |> run_concurrently(fn ->
        Versioning.create_version("sheet", sheet, project.id, user.id, title: "Concurrent")
      end)
      |> unwrap_ok()

    assert versions |> Enum.map(& &1.version_number) |> Enum.sort() == [1, 2, 3, 4, 5]
    assert versions |> Enum.map(& &1.storage_key) |> Enum.uniq() |> length() == 5
    assert Versioning.count_versions("sheet", sheet.id) == 5

    for version <- versions do
      assert {:ok, snapshot} = Versioning.load_version_snapshot(version)
      assert snapshot["name"] == sheet.name
    end
  end

  test "concurrent project snapshot creation keeps every stored snapshot", %{
    project: project,
    user: user
  } do
    snapshots =
      5
      |> run_concurrently(fn ->
        Versioning.create_project_snapshot(project.id, user.id, title: "Concurrent")
      end)
      |> unwrap_ok()

    assert snapshots |> Enum.map(& &1.version_number) |> Enum.sort() == [1, 2, 3, 4, 5]
    assert snapshots |> Enum.map(& &1.storage_key) |> Enum.uniq() |> length() == 5
    assert Versioning.count_project_snapshots(project.id) == 5

    for snapshot <- snapshots do
      assert {:ok, data} = SnapshotStorage.load_snapshot(snapshot.storage_key)
      assert data["entity_counts"]["sheets"] >= 1
    end
  end

  test "project snapshot versions preserve serialized capture order", %{
    project: project,
    sheet: sheet,
    user: user
  } do
    parent = self()
    {:ok, first_state_sheet} = Storyarn.Sheets.update_sheet(sheet, %{name: "State S1"})

    first_task =
      Task.async(fn ->
        Versioning.create_project_snapshot(project.id, user.id,
          title: "First capture",
          __snapshot_captured_hook: fn snapshot ->
            send(parent, {:snapshot_captured, :first, snapshot_sheet_name(snapshot, sheet.id)})

            receive do
              :write_second_state ->
                {:ok, _second_state_sheet} =
                  Storyarn.Sheets.update_sheet(first_state_sheet, %{name: "State S2"})

                send(parent, :second_state_written)
            after
              5_000 -> raise "timed out waiting to write the second state"
            end

            receive do
              :release_first_snapshot -> :ok
            after
              5_000 -> raise "timed out waiting to release the first snapshot"
            end
          end
        )
      end)

    assert_receive {:snapshot_captured, :first, "State S1"}, 5_000
    send(first_task.pid, :write_second_state)
    assert_receive :second_state_written, 5_000

    second_task =
      Task.async(fn ->
        send(parent, {:second_snapshot_requested, self()})

        Versioning.create_project_snapshot(project.id, user.id,
          title: "Second capture",
          __snapshot_captured_hook: fn snapshot ->
            send(parent, {:snapshot_captured, :second, snapshot_sheet_name(snapshot, sheet.id)})
          end
        )
      end)

    assert_receive {:second_snapshot_requested, second_pid}, 5_000
    assert second_pid == second_task.pid
    refute_receive {:snapshot_captured, :second, _name}, 250
    assert Task.yield(second_task, 0) == nil

    send(first_task.pid, :release_first_snapshot)

    assert {:ok, first_snapshot} = Task.await(first_task, 10_000)
    assert_receive {:snapshot_captured, :second, "State S2"}, 5_000
    assert {:ok, second_snapshot} = Task.await(second_task, 10_000)

    assert first_snapshot.version_number == 1
    assert second_snapshot.version_number == 2

    assert {:ok, first_data} =
             SnapshotStorage.load_snapshot(first_snapshot.storage_key)

    assert {:ok, second_data} =
             SnapshotStorage.load_snapshot(second_snapshot.storage_key)

    assert snapshot_sheet_name(first_data, sheet.id) == "State S1"
    assert snapshot_sheet_name(second_data, sheet.id) == "State S2"
  end

  defp run_concurrently(count, fun) do
    parent = self()

    tasks =
      for _ <- 1..count do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> fun.()
          after
            5_000 -> {:error, :timeout}
          end
        end)
      end

    pids =
      for _ <- 1..count do
        assert_receive {:ready, pid}, 5_000
        pid
      end

    Enum.each(pids, &send(&1, :go))
    Enum.map(tasks, &Task.await(&1, 15_000))
  end

  defp unwrap_ok(results) do
    Enum.map(results, fn
      {:ok, value} -> value
      other -> flunk("expected {:ok, value}, got: #{inspect(other)}")
    end)
  end

  defp snapshot_sheet_name(snapshot, sheet_id) do
    snapshot
    |> Map.fetch!("sheets")
    |> Enum.find_value(fn
      %{"id" => ^sheet_id, "snapshot" => sheet_snapshot} ->
        Map.fetch!(sheet_snapshot, "name")

      _other_sheet ->
        nil
    end)
  end
end
