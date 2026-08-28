defmodule Storyarn.Sheets.VersioningConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Platform.ObjectStorage, as: Storage
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Workspaces.Workspace

  setup do
    fixtures =
      Sandbox.unboxed_run(Repo, fn ->
        user = user_fixture(%{email: "sheet-version-concurrency-#{Ecto.UUID.generate()}@example.com"})
        project = project_fixture(user)
        sheet = sheet_fixture(project)
        _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
        sheet = Repo.preload(sheet, :blocks, force: true)

        %{user: user, project: project, sheet: sheet}
      end)

    on_exit(fn -> cleanup_fixtures(fixtures) end)
    fixtures
  end

  test "concurrent entity version creation keeps every stored snapshot", %{
    sheet: sheet,
    user: user
  } do
    versions =
      5
      |> run_concurrently(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Sheets.create_version(sheet, user.id, title: "Concurrent")
        end)
      end)
      |> unwrap_ok()

    assert versions |> Enum.map(& &1.version_number) |> Enum.sort() == [1, 2, 3, 4, 5]
    assert versions |> Enum.map(& &1.storage_key) |> Enum.uniq() |> length() == 5
    assert Sandbox.unboxed_run(Repo, fn -> Sheets.count_versions(sheet.id) end) == 5

    for version <- versions do
      assert {:ok, snapshot} =
               Sandbox.unboxed_run(Repo, fn -> Sheets.load_version_snapshot(version) end)

      assert snapshot["name"] == sheet.name
    end
  end

  test "concurrent restores serialize without publishing mixed or duplicate state", %{
    sheet: sheet,
    user: user
  } do
    parent = self()
    barrier = make_ref()

    {:ok, target} =
      Sandbox.unboxed_run(Repo, fn ->
        Sheets.create_version(sheet, user.id, title: "Concurrent restore target")
      end)

    changed_sheet =
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, changed_sheet} = Sheets.update_sheet(sheet, %{name: "Changed before restore"})
        Repo.preload(changed_sheet, :blocks, force: true)
      end)

    results =
      run_concurrently(
        2,
        fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Sheets.restore_version(changed_sheet, target,
              user_id: user.id,
              __after_pre_restore_version_verified_hook: fn safety_version ->
                send(parent, {barrier, :safety_ready, self(), safety_version.id})

                receive do
                  {^barrier, :continue_restore} -> :ok
                after
                  15_000 -> exit(:restore_barrier_timeout)
                end
              end
            )
          end)
        end,
        fn task_pids ->
          safety_versions =
            for _ <- task_pids do
              assert_receive {^barrier, :safety_ready, pid, safety_version_id}, 15_000
              {pid, safety_version_id}
            end

          assert safety_versions |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 2
          Enum.each(safety_versions, fn {pid, _version_id} -> send(pid, {barrier, :continue_restore}) end)
        end
      )

    {successful, rejected} = Enum.split_with(results, &match?({:ok, %Sheet{}}, &1))

    assert [{:ok, %Sheet{}}] = successful
    assert [{:error, :sheet_changed_since_pre_restore_snapshot}] = rejected

    assert Sandbox.unboxed_run(Repo, fn -> Repo.get!(Sheet, sheet.id).name end) == sheet.name

    active_block_ids =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.all(
          from(block in Block,
            where: block.sheet_id == ^sheet.id and is_nil(block.deleted_at),
            select: block.id
          )
        )
      end)

    assert length(active_block_ids) == 1
    assert length(Enum.uniq(active_block_ids)) == 1

    versions = Sandbox.unboxed_run(Repo, fn -> Sheets.list_versions(sheet.id) end)
    successful_restores = Enum.count(results, &match?({:ok, %Sheet{}}, &1))

    assert length(versions) == 1 + 2 + successful_restores
    assert versions |> Enum.map(& &1.storage_key) |> Enum.uniq() |> length() == length(versions)

    assert Enum.all?(versions, fn version ->
             match?(
               {:ok, _snapshot},
               Sandbox.unboxed_run(Repo, fn -> Sheets.load_version_snapshot(version) end)
             )
           end)
  end

  defp run_concurrently(count, fun, after_start \\ fn _task_pids -> :ok end) do
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
    after_start.(pids)
    Enum.map(tasks, &Task.await(&1, 15_000))
  end

  defp unwrap_ok(results) do
    Enum.map(results, fn
      {:ok, value} -> value
      other -> flunk("expected {:ok, value}, got: #{inspect(other)}")
    end)
  end

  defp cleanup_fixtures(%{user: user, project: project}) do
    Sandbox.unboxed_run(Repo, fn ->
      storage_keys =
        Repo.all(
          from(version in Storyarn.Sheets.Versioning.EntityVersionRecord,
            where: version.project_id == ^project.id,
            select: version.storage_key
          )
        )

      Repo.delete_all(from(current in Project, where: current.id == ^project.id))
      Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
      Repo.delete_all(from(current in User, where: current.id == ^user.id))

      Enum.each(storage_keys, fn storage_key ->
        _ = Storage.delete(storage_key)
      end)
    end)
  end
end
