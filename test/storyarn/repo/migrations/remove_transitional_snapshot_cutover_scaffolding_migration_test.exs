defmodule Storyarn.Repo.Migrations.RemoveTransitionalSnapshotCutoverScaffoldingMigrationTest do
  use Storyarn.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Migration.Runner
  alias Storyarn.Release
  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.AllowZeroByteRestoreStagingReservations
  alias Storyarn.Repo.Migrations.RemoveTransitionalSnapshotCutoverScaffolding

  @storage_accounting_migration 20_260_804_120_000
  @lifecycle_migration 20_260_805_130_000
  @barrier_migration 20_260_810_130_000
  @v2_only_migration 20_260_811_180_000
  @migration_version 20_260_812_100_000
  @zero_byte_restore_migration_version 20_260_813_101_000
  @release_gate :enforce_snapshot_lifecycle_release_gate
  @cleanup_authorization_config :project_snapshot_scaffolding_cleanup_authorization
  @cleanup_authorization "20260812100000"
  @authorization_key :storyarn_snapshot_scaffolding_cleanup_authorized_v1
  @lock_gate_timeout 15_000

  if !Code.ensure_loaded?(RemoveTransitionalSnapshotCutoverScaffolding) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260812100000_remove_transitional_snapshot_cutover_scaffolding.exs",
        __DIR__
      )
    )
  end

  if !Code.ensure_loaded?(AllowZeroByteRestoreStagingReservations) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260813101000_allow_zero_byte_restore_staging_reservations.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "RemoveSnapshotCutover#{System.unique_integer([:positive])}"
    Repo.query!(~s(CREATE SCHEMA "#{prefix}"))
    Repo.query!("SELECT set_config('search_path', $1, true)", [~s("#{prefix}", public)])
    create_transitional_schema!(prefix)

    # The fixture clones today's public table, so explicitly rewind the later
    # ENG-76 constraint migration to reproduce the schema seen by 20260812100000.
    assert :ok = run_zero_byte_restore_migration(:down, prefix)

    %{prefix: prefix}
  end

  test "an upgrade removes only transitional scaffolding and matches the fresh schema", %{
    prefix: prefix
  } do
    Repo.query!("""
    INSERT INTO #{qualified_table(prefix, "oban_jobs")} (worker, queue, state)
    VALUES ('Storyarn.Workers.RestoreProjectWorker', 'snapshots', 'completed')
    """)

    assert_positive_values_violation(fn ->
      insert_storage_reservation(prefix, "restore_staging", "active", 0, nil)
    end)

    assert :ok = run_migration(:up, prefix)

    refute column_exists?(prefix, "project_snapshots", "project_storage_key")
    refute column_exists?(prefix, "workspace_storage_reservations", "source_asset_count")
    refute constraint_exists?(prefix, "project_snapshots_retired_project_storage")
    refute constraint_exists?(prefix, "workspace_storage_reservations_source_inventory")
    refute constraint_exists?(prefix, "oban_jobs_snapshot_worker_routing")

    assert :ok = run_zero_byte_restore_migration(:up, prefix)

    assert {:ok, _result} =
             insert_storage_reservation(prefix, "restore_staging", "active", 0, nil)

    assert {:ok, _result} =
             insert_storage_reservation(prefix, "restore_staging", "committed", 0, 0)

    assert_positive_values_violation(fn ->
      insert_storage_reservation(prefix, "snapshot_build", "active", 0, nil)
    end)

    assert final_contract(prefix) == final_contract("public")

    assert {:ok, _result} =
             Repo.query(
               "INSERT INTO #{qualified_table(prefix, "oban_jobs")} (worker, queue, state) VALUES ($1, 'snapshots', 'available')",
               ["Storyarn.Workers.DailySnapshotWorker"],
               mode: :savepoint
             )

    assert {:ok, _result} =
             Repo.query(
               "INSERT INTO #{qualified_table(prefix, "oban_jobs")} (worker, queue, state) VALUES ($1, 'snapshots', 'available')",
               ["Storyarn.Workers.BuildProjectSnapshotWorker"],
               mode: :savepoint
             )
  end

  test "fails before DDL when a retired null fence is weakened", %{prefix: prefix} do
    snapshots = qualified_table(prefix, "project_snapshots")
    reservations = qualified_table(prefix, "workspace_storage_reservations")

    Repo.query!("ALTER TABLE #{snapshots} DROP CONSTRAINT project_snapshots_retired_project_storage")

    Repo.query!("""
    ALTER TABLE #{snapshots}
    ADD CONSTRAINT project_snapshots_retired_project_storage
    CHECK (project_storage_key IS NULL OR id = 9001)
    """)

    Repo.query!("ALTER TABLE #{reservations} DROP CONSTRAINT workspace_storage_reservations_source_inventory")

    Repo.query!("""
    ALTER TABLE #{reservations}
    ADD CONSTRAINT workspace_storage_reservations_source_inventory
    CHECK (source_asset_count IS NULL OR id = 9001)
    """)

    assert_raise Ecto.MigrationError,
                 ~r/canonical project_snapshots_retired_project_storage definition/,
                 fn ->
                   run_migration(:up, prefix)
                 end

    assert_scaffolding_intact!(prefix)
  end

  test "fails before DDL without the preceding v2-only migration marker", %{prefix: prefix} do
    Repo.query!(
      "DELETE FROM #{qualified_table(prefix, "schema_migrations")} WHERE version = $1",
      [@v2_only_migration]
    )

    assert_raise Ecto.MigrationError, ~r/requires the v2-only migration marker/, fn ->
      run_migration(:up, prefix)
    end

    assert_scaffolding_intact!(prefix)
  end

  test "fails before DDL when a canonical v2-only constraint is weakened", %{prefix: prefix} do
    snapshots = qualified_table(prefix, "project_snapshots")
    Repo.query!("ALTER TABLE #{snapshots} DROP CONSTRAINT project_snapshots_mode")

    Repo.query!("""
    ALTER TABLE #{snapshots}
    ADD CONSTRAINT project_snapshots_mode CHECK (mode = 'full' OR TRUE)
    """)

    assert_raise Ecto.MigrationError, ~r/canonical project_snapshots_mode definition/, fn ->
      run_migration(:up, prefix)
    end

    assert_scaffolding_intact!(prefix)
  end

  test "rejects a format constraint that only contains the expected tokens", %{prefix: prefix} do
    snapshots = qualified_table(prefix, "project_snapshots")
    Repo.query!("ALTER TABLE #{snapshots} DROP CONSTRAINT project_snapshots_object_format_version")

    Repo.query!("""
    ALTER TABLE #{snapshots}
    ADD CONSTRAINT project_snapshots_object_format_version CHECK (format_version >= 2)
    """)

    assert_raise Ecto.MigrationError,
                 ~r/canonical project_snapshots_object_format_version definition/,
                 fn ->
                   run_migration(:up, prefix)
                 end

    assert_scaffolding_intact!(prefix)
  end

  test "fails before DDL when the canonical snapshot object target is weakened", %{
    prefix: prefix
  } do
    snapshots = qualified_table(prefix, "project_snapshots")
    Repo.query!("ALTER TABLE #{snapshots} DROP CONSTRAINT project_snapshots_object_target")

    Repo.query!("""
    ALTER TABLE #{snapshots}
    ADD CONSTRAINT project_snapshots_object_target
    CHECK (
      (format_version = 2 AND mode = 'full' AND object_prefix IS NOT NULL AND
       object_prefix ~ ('^projects/' || project_id ||
         '/snapshots/archives/v2/ready/[A-Za-z0-9_-]{16}$') AND
       archive_storage_key = object_prefix || '/snapshot.zip' AND
       manifest_storage_key IS NOT NULL AND
       manifest_storage_key = object_prefix || '/manifest.json') OR TRUE
    )
    """)

    assert_raise Ecto.MigrationError, ~r/canonical project_snapshots_object_target definition/, fn ->
      run_migration(:up, prefix)
    end

    assert_scaffolding_intact!(prefix)
  end

  test "fails before DDL when the canonical reservation namespace constraint is missing", %{
    prefix: prefix
  } do
    reservations = qualified_table(prefix, "workspace_storage_reservations")

    Repo.query!("ALTER TABLE #{reservations} DROP CONSTRAINT workspace_storage_reservations_namespace")

    assert_raise Ecto.MigrationError,
                 ~r/validated constraint workspace_storage_reservations_namespace/,
                 fn ->
                   run_migration(:up, prefix)
                 end

    assert_scaffolding_intact!(prefix)
  end

  test "fails before DDL while retired or misrouted snapshot work is active", %{prefix: prefix} do
    jobs = qualified_table(prefix, "oban_jobs")

    # CHECK constraints accept NULL, while the cleanup preflight deliberately
    # uses IS DISTINCT FROM so nullable-schema drift cannot hide this job.
    Repo.query!("""
    INSERT INTO #{jobs} (worker, queue, state)
    VALUES ('Storyarn.Workers.BuildProjectSnapshotWorker', NULL, 'available')
    """)

    assert_raise Ecto.MigrationError,
                 ~r/no active retired or misrouted snapshot workers/,
                 fn ->
                   run_migration(:up, prefix)
                 end

    assert_scaffolding_intact!(prefix)
  end

  test "fails closed when oban_jobs cannot be locked within the bounded timeout" do
    prefix = "RemoveSnapshotLockTimeout#{System.unique_integer([:positive])}"

    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!(~s(CREATE SCHEMA "#{prefix}"))
      create_transitional_schema!(prefix)
      parent = self()
      barrier = make_ref()
      jobs = qualified_table(prefix, "oban_jobs")

      gate =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Repo.transaction(fn ->
              Repo.query!("LOCK TABLE #{jobs} IN ACCESS SHARE MODE")
              send(parent, {barrier, :locked})

              receive do
                {^barrier, :release} -> :released
              after
                @lock_gate_timeout -> exit(:lock_gate_release_timeout)
              end
            end)
          end)
        end)

      try do
        assert_receive {^barrier, :locked}, @lock_gate_timeout

        error =
          assert_raise Postgrex.Error, fn ->
            Repo.transaction(fn ->
              Repo.query!("SELECT set_config('search_path', $1, true)", [~s("#{prefix}", public)])
              run_migration(:up, prefix)
            end)
          end

        assert error.postgres.code == :lock_not_available
        assert error.postgres.pg_code == "55P03"
        assert_scaffolding_intact!(prefix)
      after
        send(gate.pid, {barrier, :release})
        assert {:ok, :released} = Task.await(gate, @lock_gate_timeout)
        Repo.query!(~s(DROP SCHEMA "#{prefix}" CASCADE))
      end
    end)
  end

  test "production enforcement rejects direct execution before DDL", %{prefix: prefix} do
    with_release_gate(true, fn ->
      assert_raise RuntimeError, ~r/must run through \/app\/bin\/migrate/, fn ->
        run_migration(:up, prefix)
      end
    end)

    assert_scaffolding_intact!(prefix)
  end

  test "the frozen release authorization reaches a migration task and applies DDL", %{
    prefix: prefix
  } do
    with_release_gate(true, fn ->
      with_cleanup_authorization(@cleanup_authorization, fn ->
        assert :ok = Release.run_project_snapshot_migrations(Repo, fn -> run_migration(:up, prefix) end)
      end)
    end)

    refute column_exists?(prefix, "project_snapshots", "project_storage_key")
    refute column_exists?(prefix, "workspace_storage_reservations", "source_asset_count")
    refute constraint_exists?(prefix, "oban_jobs_snapshot_worker_routing")
    refute Process.get(@authorization_key, false)
  end

  test "development and test entrypoints remain ungated", %{prefix: prefix} do
    with_release_gate(false, fn ->
      assert :ok = run_migration(:up, prefix)
    end)

    refute column_exists?(prefix, "project_snapshots", "project_storage_key")
    refute column_exists?(prefix, "workspace_storage_reservations", "source_asset_count")
  end

  test "rollback cannot reconstruct retired compatibility", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)

    assert_raise Ecto.MigrationError, ~r/irreversible/, fn ->
      run_migration(:down, prefix)
    end

    refute column_exists?(prefix, "project_snapshots", "project_storage_key")
    refute column_exists?(prefix, "workspace_storage_reservations", "source_asset_count")
  end

  defp create_transitional_schema!(prefix) do
    migrations = qualified_table(prefix, "schema_migrations")
    snapshots = qualified_table(prefix, "project_snapshots")
    publication_claims = qualified_table(prefix, "snapshot_object_publication_claims")
    reservations = qualified_table(prefix, "workspace_storage_reservations")
    cleanup_intents = qualified_table(prefix, "snapshot_cleanup_intents")
    jobs = qualified_table(prefix, "oban_jobs")

    Repo.query!("CREATE TABLE #{migrations} (version bigint PRIMARY KEY)")

    for version <- [
          @storage_accounting_migration,
          @lifecycle_migration,
          @barrier_migration,
          @v2_only_migration
        ] do
      Repo.query!("INSERT INTO #{migrations} (version) VALUES ($1)", [version])
    end

    Repo.query!("CREATE TABLE #{snapshots} (LIKE public.project_snapshots INCLUDING ALL)")

    Repo.query!("""
    ALTER TABLE #{snapshots}
      ADD COLUMN project_storage_key varchar(520),
      ADD CONSTRAINT project_snapshots_retired_project_storage
        CHECK (project_storage_key IS NULL)
    """)

    Repo.query!("""
    CREATE TABLE #{publication_claims}
      (LIKE public.snapshot_object_publication_claims INCLUDING ALL)
    """)

    Repo.query!("CREATE TABLE #{reservations} (LIKE public.workspace_storage_reservations INCLUDING ALL)")

    Repo.query!("""
    ALTER TABLE #{reservations}
      ADD COLUMN source_asset_count bigint,
      ADD CONSTRAINT workspace_storage_reservations_source_inventory
        CHECK (source_asset_count IS NULL)
    """)

    Repo.query!("""
    CREATE TABLE #{cleanup_intents} (LIKE public.snapshot_cleanup_intents INCLUDING ALL)
    """)

    Repo.query!("""
    CREATE TABLE #{jobs} (
      id bigserial PRIMARY KEY,
      worker text,
      queue text,
      state text,
      CONSTRAINT oban_jobs_snapshot_worker_routing
      CHECK (
        state NOT IN ('available', 'scheduled', 'executing', 'retryable') OR
        (
          worker NOT IN (
            'Storyarn.Workers.DailySnapshotWorker',
            'Storyarn.Workers.SnapshotRetentionWorker',
            'Storyarn.Workers.RestoreProjectWorker',
            'Storyarn.Workers.RecoverProjectWorker'
          ) AND
          (worker <> 'Storyarn.Workers.BuildProjectSnapshotWorker' OR queue = 'snapshot_archives')
        )
      )
    )
    """)
  end

  defp assert_scaffolding_intact!(prefix) do
    assert column_exists?(prefix, "project_snapshots", "project_storage_key")
    assert column_exists?(prefix, "workspace_storage_reservations", "source_asset_count")
    assert constraint_exists?(prefix, "project_snapshots_retired_project_storage")
    assert constraint_exists?(prefix, "workspace_storage_reservations_source_inventory")
    assert constraint_exists?(prefix, "oban_jobs_snapshot_worker_routing")
  end

  defp final_contract(prefix) do
    %{
      project_storage_column?: column_exists?(prefix, "project_snapshots", "project_storage_key"),
      source_inventory_column?: column_exists?(prefix, "workspace_storage_reservations", "source_asset_count"),
      retired_project_constraint?: constraint_exists?(prefix, "project_snapshots_retired_project_storage"),
      source_inventory_constraint?: constraint_exists?(prefix, "workspace_storage_reservations_source_inventory"),
      worker_routing_constraint?: constraint_exists?(prefix, "oban_jobs_snapshot_worker_routing"),
      canonical_constraints: canonical_constraint_definitions(prefix)
    }
  end

  defp run_migration(direction, prefix) do
    Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      RemoveTransitionalSnapshotCutoverScaffolding,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end

  defp run_zero_byte_restore_migration(direction, prefix) do
    Runner.run(
      Repo,
      Repo.config(),
      @zero_byte_restore_migration_version,
      AllowZeroByteRestoreStagingReservations,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end

  defp insert_storage_reservation(prefix, kind, status, reserved_bytes, actual_bytes) do
    unique_id = System.unique_integer([:positive])
    lease_token = Ecto.UUID.generate()
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    expires_at = NaiveDateTime.add(now, 900)
    settled_at = if status == "committed", do: now

    storage_namespace =
      "projects/1/storage-reservations/v1/#{String.replace(kind, "_", "-")}/#{lease_token}"

    cleanup_object_prefix =
      if kind == "snapshot_build" do
        "projects/1/snapshots/archives/v2/ready/ORDERKILLER00001"
      else
        storage_namespace
      end

    Repo.query(
      """
      INSERT INTO #{qualified_table(prefix, "workspace_storage_reservations")} (
        id, workspace_id_snapshot, project_id_snapshot, project_snapshot_id_snapshot,
        idempotency_key, kind, status, storage_namespace, cleanup_object_prefix,
        reserved_bytes, actual_bytes, lease_token, generation, expires_at,
        storage_started_at, settled_at, accounting_version, accounting_measured_at,
        inserted_at, updated_at
      )
      VALUES (
        $1, 1, 1, $1, $2, $3, $4, $5, $6, $7, $8, $9, 1, $10,
        NULL, $11, 1, $12, $12, $12
      )
      """,
      [
        unique_id,
        "snapshot-cutover-order-#{unique_id}",
        kind,
        status,
        storage_namespace,
        cleanup_object_prefix,
        reserved_bytes,
        actual_bytes,
        Ecto.UUID.dump!(lease_token),
        expires_at,
        settled_at,
        now
      ],
      mode: :savepoint
    )
  end

  defp assert_positive_values_violation(fun) do
    assert {:error,
            %Postgrex.Error{
              postgres: %{
                code: :check_violation,
                constraint: "workspace_storage_reservations_positive_values"
              }
            }} = fun.()
  end

  defp with_release_gate(value, fun) do
    with_application_env(@release_gate, value, fun)
  end

  defp with_cleanup_authorization(value, fun) do
    with_application_env(@cleanup_authorization_config, value, fun)
  end

  defp with_application_env(key, value, fun) do
    previous = Application.get_env(:storyarn, key, :missing)
    Application.put_env(:storyarn, key, value)

    try do
      fun.()
    after
      restore_application_env(key, previous)
    end
  end

  defp restore_application_env(key, :missing), do: Application.delete_env(:storyarn, key)
  defp restore_application_env(key, value), do: Application.put_env(:storyarn, key, value)

  defp column_exists?(prefix, table, column) do
    Repo.query!(
      """
      SELECT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = $1 AND table_name = $2 AND column_name = $3
      )
      """,
      [prefix, table, column]
    ).rows == [[true]]
  end

  defp constraint_exists?(prefix, constraint) do
    Repo.query!(
      """
      SELECT EXISTS (
        SELECT 1
        FROM pg_constraint AS constraint_row
        JOIN pg_namespace AS namespace_row ON namespace_row.oid = constraint_row.connamespace
        WHERE namespace_row.nspname = $1 AND constraint_row.conname = $2
      )
      """,
      [prefix, constraint]
    ).rows == [[true]]
  end

  defp canonical_constraint_definitions(prefix) do
    names = [
      "project_snapshots_object_format_version",
      "project_snapshots_archive_format",
      "project_snapshots_object_counts",
      "project_snapshots_mode",
      "project_snapshots_mode_integrity",
      "project_snapshots_accounting_identity",
      "project_snapshots_object_target",
      "project_snapshots_ready_object_set",
      "project_snapshots_full_ready_accounting",
      "snapshot_object_publication_claims_identity",
      "workspace_storage_reservations_kind",
      "workspace_storage_reservations_positive_values",
      "workspace_storage_reservations_namespace",
      "workspace_storage_reservations_cleanup_object_prefix",
      "snapshot_cleanup_intents_identity"
    ]

    Repo.query!(
      """
      SELECT constraint_row.conname,
             pg_get_expr(constraint_row.conbin, constraint_row.conrelid, false)
      FROM pg_constraint AS constraint_row
      JOIN pg_namespace AS namespace_row ON namespace_row.oid = constraint_row.connamespace
      WHERE namespace_row.nspname = $1
        AND constraint_row.conname = ANY($2)
      ORDER BY constraint_row.conname
      """,
      [prefix, names]
    ).rows
  end

  defp qualified_table(prefix, table), do: ~s("#{prefix}"."#{table}")
end
