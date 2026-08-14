defmodule Storyarn.Repo.Migrations.ZeroByteRestoreStagingMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.AllowZeroByteRestoreStagingReservations

  @migration_version 20_260_813_101_000
  @positive_values_constraint "workspace_storage_reservations_positive_values"
  @terminal_fields_constraint "workspace_storage_reservations_terminal_fields"
  @zero_restore_constraint "workspace_storage_reservations_zero_byte_restore_staging"

  if !Code.ensure_loaded?(AllowZeroByteRestoreStagingReservations) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260813101000_allow_zero_byte_restore_staging_reservations.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "zero_byte_restore_staging_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    create_pre_migration_table!(prefix)
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    %{prefix: prefix}
  end

  test "up admits only the restore-specific zero-byte commitment", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)

    assert {:ok, _result} =
             insert_reservation(prefix, kind: "restore_staging", reserved_bytes: 0)

    assert {:ok, _result} =
             insert_reservation(prefix,
               kind: "restore_staging",
               status: "committed",
               reserved_bytes: 0,
               actual_bytes: 0,
               settled_at: now()
             )

    assert {:ok, _result} =
             insert_reservation(prefix, kind: "snapshot_export", reserved_bytes: 0)

    assert_check_violation(fn ->
      insert_reservation(prefix, kind: "snapshot_build", reserved_bytes: 0)
    end)

    assert_check_violation(fn ->
      insert_reservation(prefix,
        kind: "restore_staging",
        reserved_bytes: 0,
        storage_started_at: now()
      )
    end)

    assert_check_violation(fn ->
      insert_reservation(prefix,
        kind: "snapshot_export",
        status: "committed",
        reserved_bytes: 0,
        actual_bytes: 0,
        storage_started_at: now(),
        settled_at: now()
      )
    end)

    assert_check_violation(fn ->
      insert_reservation(prefix,
        kind: "snapshot_build",
        status: "committed",
        reserved_bytes: 10,
        actual_bytes: 0,
        storage_started_at: now(),
        settled_at: now()
      )
    end)
  end

  test "up preserves generation, accounting, expiry, and actual-byte fences", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)

    for invalid_attrs <- [
          [kind: "restore_staging", reserved_bytes: 0, generation: 0],
          [kind: "restore_staging", reserved_bytes: 0, accounting_version: 2],
          [kind: "restore_staging", reserved_bytes: 0, expires_at: now()],
          [
            kind: "restore_staging",
            status: "committed",
            reserved_bytes: 1,
            actual_bytes: 2,
            storage_started_at: now(),
            settled_at: now()
          ],
          [
            kind: "restore_staging",
            status: "committed",
            reserved_bytes: 5,
            actual_bytes: 0,
            settled_at: now()
          ]
        ] do
      assert_check_violation(fn -> insert_reservation(prefix, invalid_attrs) end)
    end

    assert constraint_definition(prefix, @positive_values_constraint) =~ "accounting_version = 1"
    assert constraint_definition(prefix, @positive_values_constraint) =~ "expires_at > accounting_measured_at"
  end

  test "down restores the exact prior contract and can be applied again", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    assert :ok = run_migration(:down, prefix)

    assert_check_violation(fn ->
      insert_reservation(prefix, kind: "restore_staging", reserved_bytes: 0)
    end)

    assert {:ok, _result} =
             insert_reservation(prefix, kind: "snapshot_export", reserved_bytes: 0)

    assert_check_violation(fn ->
      insert_reservation(prefix,
        kind: "restore_staging",
        status: "committed",
        reserved_bytes: 1,
        actual_bytes: 1,
        settled_at: now()
      )
    end)

    assert :ok = run_migration(:up, prefix)

    assert {:ok, _result} =
             insert_reservation(prefix,
               kind: "restore_staging",
               status: "committed",
               reserved_bytes: 0,
               actual_bytes: 0,
               settled_at: now()
             )
  end

  test "down fails before DDL after durable zero-byte restore evidence exists", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    assert {:ok, _result} = insert_reservation(prefix, kind: "restore_staging", reserved_bytes: 0)

    assert_raise Ecto.MigrationError, ~r/cannot be rolled back/, fn ->
      run_migration(:down, prefix)
    end

    assert constraint_exists?(prefix, @positive_values_constraint)
    assert constraint_exists?(prefix, @terminal_fields_constraint)
    assert constraint_exists?(prefix, @zero_restore_constraint)

    assert {:ok, _result} =
             insert_reservation(prefix,
               kind: "restore_staging",
               status: "committed",
               reserved_bytes: 0,
               actual_bytes: 0,
               settled_at: now()
             )
  end

  defp create_pre_migration_table!(prefix) do
    Repo.query!("""
    CREATE TABLE #{prefix}.workspace_storage_reservations (
      id bigserial PRIMARY KEY,
      kind text NOT NULL,
      status text NOT NULL,
      reserved_bytes bigint NOT NULL,
      actual_bytes bigint,
      generation integer NOT NULL,
      accounting_version integer NOT NULL,
      expires_at timestamp(0) without time zone NOT NULL,
      accounting_measured_at timestamp(0) without time zone NOT NULL,
      storage_started_at timestamp(0) without time zone,
      cleanup_inventory_digest text,
      cleanup_inventory_count integer,
      settled_at timestamp(0) without time zone,
      release_reason text,
      cleanup_status text,
      cleanup_reference text,
      CONSTRAINT workspace_storage_reservations_positive_values CHECK (
        ((kind = 'snapshot_export' AND reserved_bytes >= 0) OR
         (kind <> 'snapshot_export' AND reserved_bytes > 0)) AND
        (actual_bytes IS NULL OR (actual_bytes > 0 AND actual_bytes <= reserved_bytes)) AND
        generation > 0 AND accounting_version = 1 AND
        (status <> 'active' OR expires_at > accounting_measured_at)
      ),
      CONSTRAINT workspace_storage_reservations_terminal_fields CHECK (
        (status = 'active' AND actual_bytes IS NULL AND settled_at IS NULL AND
         release_reason IS NULL AND cleanup_status IS NULL AND cleanup_reference IS NULL) OR
        (status = 'committed' AND actual_bytes IS NOT NULL AND settled_at IS NOT NULL AND
         storage_started_at IS NOT NULL AND release_reason IS NULL AND
         cleanup_status IS NULL AND cleanup_reference IS NULL) OR
        (status = 'released' AND actual_bytes IS NULL AND settled_at IS NOT NULL AND
         release_reason IS NOT NULL AND btrim(release_reason) <> '' AND
         cleanup_status IS NOT NULL AND cleanup_status IN ('not_required', 'owned'))
      )
    )
    """)
  end

  defp insert_reservation(prefix, overrides) do
    attrs =
      Keyword.merge(
        [
          kind: "snapshot_build",
          status: "active",
          reserved_bytes: 10,
          actual_bytes: nil,
          generation: 1,
          accounting_version: 1,
          expires_at: NaiveDateTime.add(now(), 900),
          accounting_measured_at: now(),
          storage_started_at: nil,
          settled_at: nil,
          release_reason: nil,
          cleanup_status: nil,
          cleanup_reference: nil
        ],
        overrides
      )

    Repo.query(
      """
      INSERT INTO #{prefix}.workspace_storage_reservations (
        kind, status, reserved_bytes, actual_bytes, generation, accounting_version,
        expires_at, accounting_measured_at, storage_started_at, settled_at,
        release_reason, cleanup_status, cleanup_reference
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
      """,
      [
        attrs[:kind],
        attrs[:status],
        attrs[:reserved_bytes],
        attrs[:actual_bytes],
        attrs[:generation],
        attrs[:accounting_version],
        attrs[:expires_at],
        attrs[:accounting_measured_at],
        attrs[:storage_started_at],
        attrs[:settled_at],
        attrs[:release_reason],
        attrs[:cleanup_status],
        attrs[:cleanup_reference]
      ],
      mode: :savepoint
    )
  end

  defp run_migration(direction, prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      AllowZeroByteRestoreStagingReservations,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end

  defp now, do: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

  defp assert_check_violation(fun) do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} = fun.()
  end

  defp constraint_exists?(prefix, name) do
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
        [prefix, name]
      )

    exists?
  end

  defp constraint_definition(prefix, name) do
    %Postgrex.Result{rows: [[definition]]} =
      Repo.query!(
        """
        SELECT pg_get_constraintdef(constraint_row.oid)
        FROM pg_constraint AS constraint_row
        JOIN pg_namespace AS namespace_row
          ON namespace_row.oid = constraint_row.connamespace
        WHERE namespace_row.nspname = $1 AND constraint_row.conname = $2
        """,
        [prefix, name]
      )

    definition
  end
end
