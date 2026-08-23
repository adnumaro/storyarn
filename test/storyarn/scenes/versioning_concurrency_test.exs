defmodule Storyarn.Scenes.VersioningConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Versioning.EntityVersionRecord
  alias Storyarn.Scenes.Versioning.SnapshotStorage
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Workspaces.Workspace

  setup do
    fixtures =
      Sandbox.unboxed_run(Repo, fn ->
        user = user_fixture(%{email: "scene-version-concurrency-#{Ecto.UUID.generate()}@example.com"})
        project = project_fixture(user)
        scene = scene_fixture(project)

        for version_number <- 1..9 do
          insert_version!(scene, version_number, %{
            title: "Checkpoint #{version_number}"
          })
        end

        automatic_versions = [
          insert_version!(scene, 10, %{is_auto: true}),
          insert_version!(scene, 11, %{is_auto: true})
        ]

        %{
          user: user,
          project: project,
          scene: scene,
          automatic_versions: automatic_versions
        }
      end)

    on_exit(fn -> cleanup_fixtures(fixtures) end)
    fixtures
  end

  test "concurrent promotions consume the final named-version slot atomically", %{
    project: project,
    automatic_versions: automatic_versions
  } do
    results =
      run_concurrently(automatic_versions, fn version ->
        Sandbox.unboxed_run(Repo, fn ->
          Scenes.update_version(version, %{title: "Promoted #{version.version_number}"})
        end)
      end)

    assert Enum.count(results, &match?({:ok, %EntityVersionRecord{}}, &1)) == 1

    assert Enum.count(results, fn
             {:error, :limit_reached, %{resource: :named_versions_per_project, used: 10, limit: 10}} ->
               true

             _result ->
               false
           end) == 1

    persisted =
      Sandbox.unboxed_run(Repo, fn ->
        ids = Enum.map(automatic_versions, & &1.id)

        Repo.all(
          from(version in EntityVersionRecord,
            where: version.id in ^ids,
            order_by: [asc: version.version_number]
          )
        )
      end)

    assert Enum.count(persisted, &(not &1.is_auto and not is_nil(&1.title))) == 1
    assert Enum.count(persisted, &(&1.is_auto and is_nil(&1.title))) == 1
    assert Sandbox.unboxed_run(Repo, fn -> named_version_count(project.id) end) == 10
  end

  test "concurrent automatic checks create exactly one version after the interval", %{
    user: user,
    scene: scene,
    automatic_versions: automatic_versions
  } do
    latest = List.last(automatic_versions)
    expired_at = DateTime.add(TimeHelpers.now(), -601, :second)

    Sandbox.unboxed_run(Repo, fn ->
      Repo.update_all(
        from(version in EntityVersionRecord, where: version.id == ^latest.id),
        set: [inserted_at: expired_at]
      )
    end)

    results =
      run_concurrently([:first, :second], fn _attempt ->
        Sandbox.unboxed_run(Repo, fn ->
          Scenes.maybe_create_version(scene, user.id,
            min_interval: 600,
            skip_diff: true
          )
        end)
      end)

    assert Enum.count(results, &match?({:ok, %EntityVersionRecord{is_auto: true}}, &1)) == 1
    assert Enum.count(results, &match?({:skipped, :too_recent}, &1)) == 1

    successful =
      Enum.find_value(results, fn
        {:ok, version} -> version
        _result -> nil
      end)

    latest = Sandbox.unboxed_run(Repo, fn -> Scenes.get_latest_version(scene.id) end)

    assert latest.id == successful.id
    assert latest.version_number == 12
    assert latest.is_auto
    assert Sandbox.unboxed_run(Repo, fn -> Scenes.count_versions(scene.id) end) == 12
  end

  test "concurrent explicit versions receive distinct monotonic numbers", %{
    user: user,
    project: project
  } do
    empty_scene = Sandbox.unboxed_run(Repo, fn -> scene_fixture(project) end)

    results =
      run_concurrently([:first, :second], fn _attempt ->
        Sandbox.unboxed_run(Repo, fn ->
          Scenes.create_version(empty_scene, user.id, skip_diff: true)
        end)
      end)

    assert Enum.all?(results, &match?({:ok, %EntityVersionRecord{}}, &1))

    assert results
           |> Enum.map(fn {:ok, version} -> version.version_number end)
           |> Enum.sort() == [1, 2]

    assert Sandbox.unboxed_run(Repo, fn -> Scenes.count_versions(empty_scene.id) end) == 2
  end

  test "concurrent restores serialize without deadlock and reject the stale safety snapshot", %{
    user: user,
    project: project
  } do
    restore_scene = Sandbox.unboxed_run(Repo, fn -> scene_fixture(project, %{name: "Restore target"}) end)

    target =
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, target} = Scenes.create_version(restore_scene, user.id)
        {:ok, _current} = Scenes.update_scene(restore_scene, %{name: "Concurrent current"})
        target
      end)

    results = run_restore_concurrently(restore_scene, target, user.id)

    assert Enum.count(results, &match?({:ok, _scene}, &1)) == 1

    assert Enum.count(
             results,
             &match?({:error, :scene_changed_since_pre_restore_snapshot}, &1)
           ) == 1

    Sandbox.unboxed_run(Repo, fn ->
      assert Scenes.get_scene(project.id, restore_scene.id).name == "Restore target"

      versions = Scenes.list_versions(restore_scene.id)
      assert length(versions) == 4
      assert Enum.count(versions, &(&1.title == "Before restore to v1")) == 2
      assert Enum.count(versions, &(&1.title == "Restored from v1")) == 1
    end)
  end

  defp run_concurrently(values, fun) do
    parent = self()

    tasks =
      Enum.map(values, fn value ->
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> fun.(value)
          after
            5_000 -> {:error, :timeout}
          end
        end)
      end)

    pids =
      for _value <- values do
        assert_receive {:ready, pid}, 5_000
        pid
      end

    Enum.each(pids, &send(&1, :go))
    Enum.map(tasks, &Task.await(&1, 30_000))
  end

  defp run_restore_concurrently(scene, target, user_id) do
    parent = self()

    tasks =
      for _attempt <- 1..2 do
        Task.async(fn -> execute_restore_attempt(scene, target, user_id, parent) end)
      end

    task_pids =
      for _attempt <- 1..2 do
        assert_receive {:restore_safety_verified, task_pid, _safety_id}, 10_000
        task_pid
      end

    Enum.each(task_pids, &send(&1, :continue_restore))
    Enum.map(tasks, &Task.await(&1, 30_000))
  end

  defp execute_restore_attempt(scene, target, user_id, parent) do
    Sandbox.unboxed_run(Repo, fn ->
      current = Scenes.get_scene(scene.project_id, scene.id)
      hook = &await_restore_release(&1, parent)

      Scenes.restore_version(current, target,
        user_id: user_id,
        __after_pre_restore_version_verified_hook: hook
      )
    end)
  end

  defp await_restore_release(safety_version, parent) do
    send(parent, {:restore_safety_verified, self(), safety_version.id})

    receive do
      :continue_restore -> :ok
    after
      10_000 -> raise "timed out waiting to continue concurrent Scene restore"
    end
  end

  defp insert_version!(scene, version_number, attrs) do
    base_attrs = %{
      entity_type: "scene",
      entity_id: scene.id,
      project_id: scene.project_id,
      version_number: version_number,
      title: nil,
      storage_key: "projects/#{scene.project_id}/snapshots/scene/#{scene.id}/test-#{version_number}.json.gz",
      snapshot_size_bytes: 0,
      checksum: String.duplicate("b", 64),
      is_auto: false
    }

    %EntityVersionRecord{}
    |> EntityVersionRecord.create_changeset(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end

  defp named_version_count(project_id) do
    Repo.aggregate(
      from(version in EntityVersionRecord,
        where:
          version.project_id == ^project_id and not is_nil(version.title) and
            version.is_auto == false
      ),
      :count
    )
  end

  defp cleanup_fixtures(%{user: user, project: project}) do
    Sandbox.unboxed_run(Repo, fn ->
      storage_keys =
        Repo.all(
          from(version in EntityVersionRecord,
            where: version.project_id == ^project.id,
            select: version.storage_key
          )
        )

      Repo.delete_all(from(version in EntityVersionRecord, where: version.project_id == ^project.id))
      Repo.delete_all(from(current in Project, where: current.id == ^project.id))
      Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
      Repo.delete_all(from(current in User, where: current.id == ^user.id))

      Enum.each(storage_keys, fn storage_key ->
        _cleanup_result = SnapshotStorage.delete(storage_key)
      end)
    end)
  end
end
