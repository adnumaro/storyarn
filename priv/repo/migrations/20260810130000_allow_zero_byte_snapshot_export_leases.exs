defmodule Storyarn.Repo.Migrations.AllowZeroByteSnapshotExportLeases do
  @moduledoc """
  Allows zero-byte snapshot-export read leases.

  The migration can be rolled back only before the first such lease is
  created. Released leases are durable lifecycle evidence and must not be
  deleted or rewritten merely to restore the previous positive-byte check.
  """

  use Ecto.Migration

  @authorization_key :storyarn_snapshot_cutover_authorized_v1

  def up do
    assert_cutover_barriers!()

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

  # The first destructive migration installs these transaction-persistent
  # barriers. This migration locks and verifies them rather than depending on a
  # live release helper or duplicating the installer.
  defp assert_cutover_barriers! do
    assert_release_authorized!()
    current_prefix = assert_current_prefix!()
    snapshots = qualified_table(current_prefix, "project_snapshots")
    jobs = qualified_table(current_prefix, "oban_jobs")
    repo().query!("LOCK TABLE #{snapshots}, #{jobs} IN ACCESS EXCLUSIVE MODE")

    case repo().query!(
           """
           SELECT count(*)
           FROM pg_constraint AS constraint_row
           JOIN pg_class AS table_row ON table_row.oid = constraint_row.conrelid
           JOIN pg_namespace AS namespace_row ON namespace_row.oid = table_row.relnamespace
           WHERE namespace_row.nspname = $1
             AND (table_row.relname, constraint_row.conname) IN (
               ('project_snapshots', 'project_snapshots_cutover_quiescent'),
               ('oban_jobs', 'oban_jobs_snapshot_cutover_quiescent')
             )
           """,
           [current_prefix]
         ).rows do
      [[2]] ->
        :ok

      [[count]] ->
        raise "Snapshot cutover barriers are incomplete; expected 2, found #{inspect(count)}"

      invalid ->
        raise "Invalid snapshot cutover barrier state: #{inspect(invalid)}"
    end
  end

  defp assert_release_authorized! do
    enforced? =
      Application.get_env(:storyarn, :enforce_snapshot_lifecycle_release_gate, false)

    if enforced? and not release_authorized?() do
      raise "Snapshot lifecycle migration must run through /app/bin/migrate after the v2-only cutover preflight"
    end
  end

  defp release_authorized? do
    Process.get(@authorization_key, false) == true or
      Enum.any?(List.wrap(Process.get(:"$callers")), &authorized_caller?/1)
  end

  defp authorized_caller?(pid) when is_pid(pid) and node(pid) == node() do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} ->
        List.keyfind(dictionary, @authorization_key, 0) == {@authorization_key, true}

      nil ->
        false
    end
  end

  defp authorized_caller?(_pid), do: false

  defp assert_current_prefix! do
    current_prefix =
      case repo().query!("SELECT current_schema()").rows do
        [[value]] -> validate_prefix!(value)
        invalid -> raise "Invalid current snapshot migration prefix: #{inspect(invalid)}"
      end

    requested_prefix = validate_prefix!(prefix() || current_prefix)

    if requested_prefix == current_prefix do
      current_prefix
    else
      raise "Project snapshot migrations require their explicit prefix to match current_schema(); requested #{inspect(requested_prefix)}, current #{inspect(current_prefix)}"
    end
  end

  defp validate_prefix!(value) when is_binary(value) and byte_size(value) > 0 do
    if Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_$]*\z/, value) do
      value
    else
      raise "Unsafe project snapshot migration prefix: #{inspect(value)}"
    end
  end

  defp validate_prefix!(value),
    do: raise("Invalid project snapshot migration prefix: #{inspect(value)}")

  defp qualified_table(current_prefix, table), do: ~s("#{current_prefix}"."#{table}")
end
