defmodule Storyarn.Repo.Migrations.AllowZeroByteRestoreStagingReservations do
  @moduledoc """
  Allows an exact restore with no archived assets to reserve and commit zero
  staging bytes.

  Snapshot exports retain their established zero-byte read-lease allowance,
  but only restore staging may persist zero actual bytes. The migration can be
  rolled back only while no reservation relies on the new restore exception.
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
             ((kind IN ('snapshot_export', 'restore_staging') AND reserved_bytes >= 0) OR
              (kind NOT IN ('snapshot_export', 'restore_staging') AND reserved_bytes > 0)) AND
             (actual_bytes IS NULL OR
              (((kind = 'restore_staging' AND actual_bytes >= 0) OR
               (kind <> 'restore_staging' AND actual_bytes > 0)) AND
               actual_bytes <= reserved_bytes)) AND
             generation > 0 AND accounting_version = 1 AND
             (status <> 'active' OR expires_at > accounting_measured_at)
             """
           )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_zero_byte_restore_staging,
             check: """
             kind <> 'restore_staging' OR reserved_bytes <> 0 OR
             (storage_started_at IS NULL AND cleanup_inventory_digest IS NULL AND
              cleanup_inventory_count IS NULL AND
              (actual_bytes IS NULL OR actual_bytes = 0))
             """
           )

    drop constraint(
           :workspace_storage_reservations,
           :workspace_storage_reservations_terminal_fields
         )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_terminal_fields,
             check: """
             (status = 'active' AND actual_bytes IS NULL AND settled_at IS NULL AND
              release_reason IS NULL AND cleanup_status IS NULL AND cleanup_reference IS NULL) OR
             (status = 'committed' AND actual_bytes IS NOT NULL AND settled_at IS NOT NULL AND
              (storage_started_at IS NOT NULL OR
               (kind = 'restore_staging' AND reserved_bytes = 0 AND actual_bytes = 0 AND
                cleanup_inventory_digest IS NULL AND cleanup_inventory_count IS NULL)) AND
              release_reason IS NULL AND cleanup_status IS NULL AND cleanup_reference IS NULL) OR
             (status = 'released' AND actual_bytes IS NULL AND settled_at IS NOT NULL AND
              release_reason IS NOT NULL AND btrim(release_reason) <> '' AND
              cleanup_status IS NOT NULL AND cleanup_status IN ('not_required', 'owned'))
             """
           )
  end

  def down do
    assert_no_zero_byte_restore_evidence!()

    drop constraint(
           :workspace_storage_reservations,
           :workspace_storage_reservations_zero_byte_restore_staging
         )

    drop constraint(
           :workspace_storage_reservations,
           :workspace_storage_reservations_terminal_fields
         )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_terminal_fields,
             check: """
             (status = 'active' AND actual_bytes IS NULL AND settled_at IS NULL AND
              release_reason IS NULL AND cleanup_status IS NULL AND cleanup_reference IS NULL) OR
             (status = 'committed' AND actual_bytes IS NOT NULL AND settled_at IS NOT NULL AND
              storage_started_at IS NOT NULL AND release_reason IS NULL AND
              cleanup_status IS NULL AND cleanup_reference IS NULL) OR
             (status = 'released' AND actual_bytes IS NULL AND settled_at IS NOT NULL AND
              release_reason IS NOT NULL AND btrim(release_reason) <> '' AND
              cleanup_status IS NOT NULL AND cleanup_status IN ('not_required', 'owned'))
             """
           )

    drop constraint(
           :workspace_storage_reservations,
           :workspace_storage_reservations_positive_values
         )

    create constraint(
             :workspace_storage_reservations,
             :workspace_storage_reservations_positive_values,
             check: """
             ((kind = 'snapshot_export' AND reserved_bytes >= 0) OR
              (kind <> 'snapshot_export' AND reserved_bytes > 0)) AND
             (actual_bytes IS NULL OR (actual_bytes > 0 AND actual_bytes <= reserved_bytes)) AND
             generation > 0 AND accounting_version = 1 AND
             (status <> 'active' OR expires_at > accounting_measured_at)
             """
           )
  end

  # This assertion must run immediately, rather than being queued with the
  # reversible DDL below it. Otherwise Ecto's migration runner may execute the
  # drops before discovering that the rollback is unsafe.
  defp assert_no_zero_byte_restore_evidence! do
    case repo().query!("""
         SELECT EXISTS (
           SELECT 1
           FROM workspace_storage_reservations
           WHERE kind = 'restore_staging'
             AND (reserved_bytes = 0 OR actual_bytes = 0)
         )
         """).rows do
      [[false]] ->
        :ok

      [[true]] ->
        raise Ecto.MigrationError,
              "AllowZeroByteRestoreStagingReservations cannot be rolled back after zero-byte restore staging reservations exist"
    end
  end
end
