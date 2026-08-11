defmodule Storyarn.Repo.Migrations.SnapshotExportLeaseRetentionMigrationTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Repo

  @index_name "workspace_storage_reservations_released_export_retention_idx"

  test "installs the partial terminal export-lease retention index" do
    assert %Postgrex.Result{rows: [[definition]]} =
             Repo.query!(
               """
               SELECT indexdef
               FROM pg_indexes
               WHERE schemaname = current_schema() AND indexname = $1
               """,
               [@index_name]
             )

    assert definition =~ "settled_at"
    assert definition =~ "status"
    assert definition =~ "'released'"
    assert definition =~ "kind"
    assert definition =~ "'snapshot_export'"
    assert definition =~ "reserved_bytes = 0"
    assert definition =~ "storage_started_at IS NULL"
    assert definition =~ "cleanup_status"
    assert definition =~ "'not_required'"
  end
end
