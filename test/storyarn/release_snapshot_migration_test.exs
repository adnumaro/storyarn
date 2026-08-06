defmodule Storyarn.ReleaseSnapshotMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Release
  alias Storyarn.Repo
  alias Storyarn.SnapshotMigrationGateRepo
  alias Storyarn.SnapshotResetStorage

  @environment_variable "STORYARN_DEPLOYMENT_ENVIRONMENT"
  @snapshot_lifecycle_migration 20_260_805_130_000
  @snapshot_lifecycle_migration_authorization_key {
    Release,
    :snapshot_lifecycle_migration_authorized
  }

  setup do
    original_environment = System.get_env(@environment_variable)

    on_exit(fn -> restore_system_env(@environment_variable, original_environment) end)

    :ok
  end

  test "an already-applied lifecycle migration bypasses the one-time rollout gate" do
    System.delete_env(@environment_variable)
    :ok = SnapshotMigrationGateRepo.configure({:ok, %{rows: [[true]]}})

    assert :ok = Release.ensure_project_snapshot_lifecycle_rollout_ready!(SnapshotMigrationGateRepo)
  end

  test "a pending lifecycle migration fails closed without an explicit environment" do
    System.delete_env(@environment_variable)
    :ok = SnapshotMigrationGateRepo.configure({:ok, %{rows: [[false]]}})

    assert_raise System.EnvError, fn ->
      Release.ensure_project_snapshot_lifecycle_rollout_ready!(SnapshotMigrationGateRepo)
    end
  end

  test "a pending lifecycle migration accepts only complete reset readiness" do
    System.put_env(@environment_variable, "production")

    :ok =
      SnapshotMigrationGateRepo.configure(
        {:ok, %{rows: [[false]]}},
        {:ok, %{rows: [[true, true, true, 0, 0, true, []]]}}
      )

    assert :ok = Release.ensure_project_snapshot_lifecycle_rollout_ready!(SnapshotMigrationGateRepo)
  end

  test "a pending lifecycle migration rejects incomplete reset readiness" do
    System.put_env(@environment_variable, "production")

    :ok =
      SnapshotMigrationGateRepo.configure(
        {:ok, %{rows: [[false]]}},
        {:ok, %{rows: [[true, true, true, 1, 0, false, []]]}}
      )

    assert_raise RuntimeError, ~r/snapshot_reset_rollout_receipts_incomplete/, fn ->
      Release.ensure_project_snapshot_lifecycle_rollout_ready!(SnapshotMigrationGateRepo)
    end
  end

  test "a pending lifecycle migration bootstraps an exactly pristine deployment" do
    System.put_env(@environment_variable, "production")
    :ok = SnapshotResetStorage.put_objects(%{})
    Repo.query!("DELETE FROM schema_migrations WHERE version >= $1", [@snapshot_lifecycle_migration])

    assert :ok =
             Release.ensure_project_snapshot_lifecycle_rollout_ready!(Repo,
               current_environment: "production",
               storage_adapter: SnapshotResetStorage
             )

    assert [["production", [], 0, 0]] =
             Repo.query!("""
             SELECT environment, workspace_receipt_ids, object_count, scanned_object_count
             FROM project_snapshot_provider_reset_receipts
             """).rows
  end

  test "a malformed migration-state response fails closed" do
    :ok = SnapshotMigrationGateRepo.configure({:ok, %{rows: [["invalid"]]}})

    assert_raise RuntimeError, ~r/Could not verify snapshot lifecycle migration state/, fn ->
      Release.ensure_project_snapshot_lifecycle_rollout_ready!(SnapshotMigrationGateRepo)
    end
  end

  test "production lifecycle migration rejects a direct migration entrypoint" do
    enforce_snapshot_lifecycle_release_gate()

    assert_raise RuntimeError, ~r/must run through Storyarn.Release.migrate/, fn ->
      Release.assert_snapshot_lifecycle_migration_authorized!()
    end
  end

  test "production lifecycle migration accepts the authorizing Ecto task descendant" do
    enforce_snapshot_lifecycle_release_gate()

    previous = Process.get(@snapshot_lifecycle_migration_authorization_key, :missing)
    Process.put(@snapshot_lifecycle_migration_authorization_key, true)

    try do
      assert :ok =
               (&Release.assert_snapshot_lifecycle_migration_authorized!/0)
               |> Task.async()
               |> Task.await()
    after
      restore_process_dictionary(
        @snapshot_lifecycle_migration_authorization_key,
        previous
      )
    end
  end

  test "production lifecycle migration rejects authorization owned by an unrelated process" do
    enforce_snapshot_lifecycle_release_gate()
    test_pid = self()

    owner =
      spawn(fn ->
        Process.put(@snapshot_lifecycle_migration_authorization_key, true)
        send(test_pid, {:snapshot_migration_authorization_ready, self()})
        receive do: (:stop -> :ok)
      end)

    assert_receive {:snapshot_migration_authorization_ready, ^owner}

    try do
      assert_raise RuntimeError, ~r/must run through Storyarn.Release.migrate/, fn ->
        Release.assert_snapshot_lifecycle_migration_authorized!()
      end
    after
      send(owner, :stop)
    end
  end

  test "a killed authorization owner cannot leave the production gate enabled" do
    enforce_snapshot_lifecycle_release_gate()
    test_pid = self()

    owner =
      spawn(fn ->
        Process.put(@snapshot_lifecycle_migration_authorization_key, true)
        send(test_pid, {:snapshot_migration_authorization_ready, self()})
        Process.sleep(:infinity)
      end)

    owner_ref = Process.monitor(owner)
    assert_receive {:snapshot_migration_authorization_ready, ^owner}
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, ^owner, :killed}

    previous_callers = Process.get(:"$callers", :missing)
    Process.put(:"$callers", [owner])

    try do
      assert_raise RuntimeError, ~r/must run through Storyarn.Release.migrate/, fn ->
        Release.assert_snapshot_lifecycle_migration_authorized!()
      end
    after
      restore_process_dictionary(:"$callers", previous_callers)
    end
  end

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)

  defp enforce_snapshot_lifecycle_release_gate do
    original_gate = Application.get_env(:storyarn, :enforce_snapshot_lifecycle_release_gate)
    Application.put_env(:storyarn, :enforce_snapshot_lifecycle_release_gate, true)

    on_exit(fn -> restore_application_env(:storyarn, :enforce_snapshot_lifecycle_release_gate, original_gate) end)
  end

  defp restore_process_dictionary(key, :missing), do: Process.delete(key)
  defp restore_process_dictionary(key, previous), do: Process.put(key, previous)

  defp restore_application_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_application_env(app, key, value), do: Application.put_env(app, key, value)
end
