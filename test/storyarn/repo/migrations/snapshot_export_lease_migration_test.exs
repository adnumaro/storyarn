defmodule Storyarn.Repo.Migrations.SnapshotExportLeaseMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.AllowZeroByteSnapshotExportLeases

  @migration_version 20_260_810_130_000
  @positive_values_constraint "workspace_storage_reservations_positive_values"
  @zero_lease_constraint "workspace_storage_reservations_zero_byte_snapshot_export_lease"
  @expired_lease_index "workspace_storage_reservations_expired_export_lease_idx"

  if !Code.ensure_loaded?(AllowZeroByteSnapshotExportLeases) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260810130000_allow_zero_byte_snapshot_export_leases.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "snapshot_export_lease_migration_#{System.unique_integer([:positive])}"

    Repo.query!("CREATE SCHEMA #{prefix}")

    Repo.query!("""
    CREATE TABLE #{prefix}.workspace_storage_reservations
    (LIKE public.workspace_storage_reservations INCLUDING ALL)
    """)

    # The production migration also installs the v2 cutover fence. Keep the
    # isolated fixture structurally representative of the tables that the
    # fence locks and constrains.
    Repo.query!("CREATE TABLE #{prefix}.project_snapshots (id bigint PRIMARY KEY)")
    Repo.query!("CREATE TABLE #{prefix}.entity_versions (id bigint PRIMARY KEY)")

    Repo.query!("""
    CREATE TABLE #{prefix}.oban_jobs (
      id bigint PRIMARY KEY,
      worker text NOT NULL,
      state text NOT NULL
    )
    """)

    # Derive the isolated fixture from the deployed table so new columns,
    # constraints, and indexes cannot silently drift from this migration smoke.
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    assert :ok = run_migration(:down, prefix)

    Repo.query!("""
    ALTER TABLE #{prefix}.project_snapshots
    ADD CONSTRAINT project_snapshots_cutover_quiescent CHECK (FALSE)
    """)

    Repo.query!("""
    ALTER TABLE #{prefix}.oban_jobs
    ADD CONSTRAINT oban_jobs_snapshot_cutover_quiescent
    CHECK (
      state NOT IN ('available', 'scheduled', 'executing', 'retryable') OR
      worker NOT IN (
        'Storyarn.Workers.BuildProjectSnapshotWorker',
        'Storyarn.Workers.DailySnapshotWorker',
        'Storyarn.Workers.SnapshotRetentionWorker',
        'Storyarn.Workers.RestoreProjectWorker',
        'Storyarn.Workers.RecoverProjectWorker'
      )
    )
    """)

    %{prefix: prefix}
  end

  test "executes an empty rollback and can apply the migration again", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    assert constraint_exists?(prefix, @zero_lease_constraint)
    assert index_exists?(prefix, @expired_lease_index)

    assert :ok = run_migration(:down, prefix)
    refute constraint_exists?(prefix, @zero_lease_constraint)
    refute index_exists?(prefix, @expired_lease_index)

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_zero_byte_export_lease(prefix)

    assert :ok = run_migration(:up, prefix)
    assert {:ok, _result} = insert_zero_byte_export_lease(prefix)
  end

  test "rollback fails closed before DDL after zero-byte lease evidence exists", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    assert {:ok, _result} = insert_zero_byte_export_lease(prefix)

    error =
      assert_raise Postgrex.Error, fn ->
        run_migration(:down, prefix)
      end

    assert error.postgres.code == :object_not_in_prerequisite_state
    assert error.postgres.pg_code == "55000"
    assert zero_byte_export_lease_count(prefix) == 1
    assert constraint_exists?(prefix, @positive_values_constraint)
    assert constraint_exists?(prefix, @zero_lease_constraint)
    assert index_exists?(prefix, @expired_lease_index)
  end

  test "up fails before DDL when the persistent cutover barrier is incomplete", %{
    prefix: prefix
  } do
    Repo.query!("""
    ALTER TABLE #{prefix}.oban_jobs
    DROP CONSTRAINT oban_jobs_snapshot_cutover_quiescent
    """)

    assert_raise RuntimeError, ~r/cutover barriers are incomplete/, fn ->
      run_migration(:up, prefix)
    end

    refute constraint_exists?(prefix, @zero_lease_constraint)
    refute index_exists?(prefix, @expired_lease_index)
  end

  defp run_migration(direction, prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      AllowZeroByteSnapshotExportLeases,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end

  defp insert_zero_byte_export_lease(prefix) do
    Repo.query(
      """
      INSERT INTO #{prefix}.workspace_storage_reservations (
        id,
        workspace_id_snapshot,
        project_id_snapshot,
        project_snapshot_id_snapshot,
        idempotency_key,
        kind,
        status,
        storage_namespace,
        cleanup_object_prefix,
        reserved_bytes,
        actual_bytes,
        lease_token,
        generation,
        accounting_version,
        expires_at,
        accounting_measured_at,
        storage_started_at,
        cleanup_inventory_digest,
        cleanup_inventory_count,
        inserted_at,
        updated_at
      )
      VALUES (
        1,
        1,
        2,
        3,
        'snapshot-export-migration-test',
        'snapshot_export',
        'active',
        'projects/2/storage-reservations/v1/snapshot-export/00000000-0000-4000-8000-000000000001',
        'projects/2/storage-reservations/v1/snapshot-export/00000000-0000-4000-8000-000000000001',
        0,
        NULL,
        '00000000-0000-4000-8000-000000000001',
        1,
        1,
        clock_timestamp() + interval '15 minutes',
        clock_timestamp(),
        NULL,
        NULL,
        NULL,
        clock_timestamp(),
        clock_timestamp()
      )
      """,
      [],
      mode: :savepoint
    )
  end

  defp zero_byte_export_lease_count(prefix) do
    %Postgrex.Result{rows: [[count]]} =
      Repo.query!("""
      SELECT count(*)
      FROM #{prefix}.workspace_storage_reservations
      WHERE kind = 'snapshot_export' AND reserved_bytes = 0
      """)

    count
  end

  defp constraint_exists?(prefix, constraint_name) do
    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_constraint AS constraint_row
          JOIN pg_namespace AS namespace_row
            ON namespace_row.oid = constraint_row.connamespace
          WHERE namespace_row.nspname = $1 AND constraint_row.conname = $2
        )
        """,
        [prefix, constraint_name]
      )

    exists?
  end

  defp index_exists?(prefix, index_name) do
    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_class AS relation_row
          JOIN pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
          WHERE namespace_row.nspname = $1 AND relation_row.relname = $2 AND relation_row.relkind = 'i'
        )
        """,
        [prefix, index_name]
      )

    exists?
  end
end
