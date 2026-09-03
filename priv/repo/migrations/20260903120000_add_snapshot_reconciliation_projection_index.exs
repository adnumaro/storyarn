defmodule Storyarn.Repo.Migrations.AddSnapshotReconciliationProjectionIndex do
  use Ecto.Migration

  @moduledoc """
  Adds the lookup path used by the durable reconciliation metric projection.

  Only completed runs participate. The descending columns let PostgreSQL stop
  after the latest run for one provider namespace without scanning historical
  runs or indexing active reconciliation state.
  """

  @index_name :project_snapshot_reconciliation_runs_latest_completed_idx

  def change do
    create index(
             :project_snapshot_reconciliation_runs,
             [:provider_namespace_fingerprint, desc: :finished_at, desc: :id],
             name: @index_name,
             where: "status = 'completed' AND finished_at IS NOT NULL"
           )
  end
end
