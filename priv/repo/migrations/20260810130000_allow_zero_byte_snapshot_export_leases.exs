defmodule Storyarn.Repo.Migrations.AllowZeroByteSnapshotExportLeases do
  @moduledoc """
  Allows zero-byte snapshot-export read leases.

  The migration can be rolled back only before the first such lease is
  created. Released leases are durable lifecycle evidence and must not be
  deleted or rewritten merely to restore the previous positive-byte check.
  """

  use Ecto.Migration

  def up do
    drop constraint(
           :workspace_storage_reservations,
           :workspace_storage_reservations_positive_values
         )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_positive_values,
             check: """
             ((kind IN ('linked_to_full_conversion', 'snapshot_export') AND reserved_bytes >= 0) OR
              (kind NOT IN ('linked_to_full_conversion', 'snapshot_export') AND reserved_bytes > 0)) AND
             (actual_bytes IS NULL OR
              (((kind = 'linked_to_full_conversion' AND actual_bytes >= 0) OR
                (kind <> 'linked_to_full_conversion' AND actual_bytes > 0)) AND
               actual_bytes <= reserved_bytes)) AND
             generation > 0 AND accounting_version = 1 AND
             (status <> 'active' OR expires_at > accounting_measured_at)
             """
           )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_zero_byte_snapshot_export_lease,
             check: """
             kind <> 'snapshot_export' OR reserved_bytes <> 0 OR
             (actual_bytes IS NULL AND storage_started_at IS NULL AND
              cleanup_inventory_digest IS NULL AND cleanup_inventory_count IS NULL)
             """
           )

    create index(
             :workspace_storage_reservations,
             [:expires_at, :id],
             where: """
             status = 'active' AND kind = 'snapshot_export' AND reserved_bytes = 0 AND
             storage_started_at IS NULL
             """,
             name: :workspace_storage_reservations_expired_export_lease_idx
           )
  end

  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM workspace_storage_reservations
        WHERE kind = 'snapshot_export' AND reserved_bytes = 0
      ) THEN
        RAISE EXCEPTION
          'AllowZeroByteSnapshotExportLeases cannot be rolled back after zero-byte snapshot export leases exist'
          USING ERRCODE = 'object_not_in_prerequisite_state';
      END IF;
    END;
    $$;
    """)

    drop_if_exists index(
                     :workspace_storage_reservations,
                     [:expires_at, :id],
                     name: :workspace_storage_reservations_expired_export_lease_idx
                   )

    drop constraint(
           :workspace_storage_reservations,
           :workspace_storage_reservations_zero_byte_snapshot_export_lease
         )

    drop constraint(
           :workspace_storage_reservations,
           :workspace_storage_reservations_positive_values
         )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_positive_values,
             check: """
             ((kind = 'linked_to_full_conversion' AND reserved_bytes >= 0) OR
              (kind <> 'linked_to_full_conversion' AND reserved_bytes > 0)) AND
             (actual_bytes IS NULL OR
              (((kind = 'linked_to_full_conversion' AND actual_bytes >= 0) OR
                (kind <> 'linked_to_full_conversion' AND actual_bytes > 0)) AND
               actual_bytes <= reserved_bytes)) AND
             generation > 0 AND accounting_version = 1 AND
             (status <> 'active' OR expires_at > accounting_measured_at)
             """
           )
  end
end
