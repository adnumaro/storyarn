defmodule Storyarn.Repo.Migrations.SnapshotReconciliationProjectionIndexMigrationTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Repo

  @index_name "project_snapshot_reconciliation_runs_latest_completed_idx"

  test "installs the partial latest-completed-run projection index" do
    assert %Postgrex.Result{rows: [[definition]]} =
             Repo.query!(
               """
               SELECT indexdef
               FROM pg_indexes
               WHERE schemaname = current_schema() AND indexname = $1
               """,
               [@index_name]
             )

    assert definition =~ "provider_namespace_fingerprint"
    assert definition =~ "finished_at DESC"
    assert definition =~ "id DESC"
    assert definition =~ "status"
    assert definition =~ "'completed'"
    assert definition =~ "finished_at IS NOT NULL"
  end
end
