defmodule Storyarn.Repo.Migrations.AddSnapshotExportLeaseRetentionIndex do
  use Ecto.Migration

  @moduledoc """
  Adds the bounded-retention access path for terminal zero-byte export leases.

  Active leases are deliberately outside the partial index and the purge
  contract. This migration changes no lease state and is compatible with old
  nodes during a rolling deploy.
  """

  def up do
    create index(
             :workspace_storage_reservations,
             [:id, :settled_at],
             name: :workspace_storage_reservations_released_export_retention_idx,
             where: """
             status = 'released' AND kind = 'snapshot_export' AND
             reserved_bytes = 0 AND actual_bytes IS NULL AND
             storage_started_at IS NULL AND cleanup_status = 'not_required'
             """
           )
  end

  def down do
    drop_if_exists index(
                     :workspace_storage_reservations,
                     [:id, :settled_at],
                     name: :workspace_storage_reservations_released_export_retention_idx
                   )
  end
end
