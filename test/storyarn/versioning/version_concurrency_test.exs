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
end
