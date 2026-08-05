defmodule Storyarn.ReleaseSnapshotMigrationTest do
  use ExUnit.Case, async: false

  alias Storyarn.Release
  alias Storyarn.SnapshotMigrationGateRepo

  @environment_variable "STORYARN_DEPLOYMENT_ENVIRONMENT"

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
        {:ok, %{rows: [[true, true, true, 0, 0, false, []]]}}
      )

    assert_raise RuntimeError, ~r/snapshot_reset_rollout_provider_receipt_missing/, fn ->
      Release.ensure_project_snapshot_lifecycle_rollout_ready!(SnapshotMigrationGateRepo)
    end
  end

  test "a malformed migration-state response fails closed" do
    :ok = SnapshotMigrationGateRepo.configure({:ok, %{rows: [["invalid"]]}})

    assert_raise RuntimeError, ~r/Could not verify snapshot lifecycle migration state/, fn ->
      Release.ensure_project_snapshot_lifecycle_rollout_ready!(SnapshotMigrationGateRepo)
    end
  end

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)
end
