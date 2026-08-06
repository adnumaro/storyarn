defmodule Storyarn.ReleaseSnapshotMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Release
  alias Storyarn.Repo
  alias Storyarn.SnapshotMigrationGateRepo
  alias Storyarn.SnapshotResetStorage

  @environment_variable "STORYARN_DEPLOYMENT_ENVIRONMENT"
  @snapshot_lifecycle_migration 20_260_805_130_000

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
    Repo.query!("DELETE FROM schema_migrations WHERE version = $1", [@snapshot_lifecycle_migration])

    assert :ok =
             Release.ensure_project_snapshot_lifecycle_rollout_ready!(Repo,
               current_environment: "production",
               storage_adapter: SnapshotResetStorage,
               rollout_guard: fn _repo -> :ok end
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
    original_gate = Application.get_env(:storyarn, :enforce_snapshot_lifecycle_release_gate)
    Application.put_env(:storyarn, :enforce_snapshot_lifecycle_release_gate, true)

    on_exit(fn -> restore_application_env(:storyarn, :enforce_snapshot_lifecycle_release_gate, original_gate) end)

    assert_raise RuntimeError, ~r/must run through Storyarn.Release.migrate/, fn ->
      Release.assert_snapshot_lifecycle_migration_authorized!()
    end
  end

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)

  defp restore_application_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_application_env(app, key, value), do: Application.put_env(app, key, value)
end
