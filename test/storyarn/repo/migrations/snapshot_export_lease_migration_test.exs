defmodule Storyarn.Repo.Migrations.SnapshotExportLeaseMigrationTest do
  use ExUnit.Case, async: true

  @migration_path Path.expand(
                    "../../../../priv/repo/migrations/20260810130000_allow_zero_byte_snapshot_export_leases.exs",
                    __DIR__
                  )

  test "rollback fails closed after zero-byte export lease evidence exists" do
    source = File.read!(@migration_path)
    [_up, down] = String.split(source, "def down do", parts: 2)

    assert down =~ "WHERE kind = 'snapshot_export' AND reserved_bytes = 0"
    assert down =~ "cannot be rolled back after zero-byte snapshot export leases exist"
    assert down =~ "ERRCODE = 'object_not_in_prerequisite_state'"
    refute down =~ "DELETE FROM workspace_storage_reservations"
    refute down =~ "UPDATE workspace_storage_reservations"
  end
end
