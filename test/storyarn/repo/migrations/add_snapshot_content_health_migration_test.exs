defmodule Storyarn.Repo.Migrations.AddSnapshotContentHealthMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.AddSnapshotContentHealth
  alias Storyarn.Versioning.SnapshotContentHealth

  @migration_version 20_260_815_130_000
  @restore_guard_function "storyarn_guard_project_snapshot_restore_content_health"
  @restore_guard_trigger "project_snapshot_restores_content_health_guard"

  if !Code.ensure_loaded?(AddSnapshotContentHealth) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260815130000_add_snapshot_content_health.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "snapshot_content_health_migration_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    create_pre_migration_tables!(prefix)
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    %{prefix: prefix}
  end

  test "up installs durable columns, constraints, and the mixed-version restore guard", %{
    prefix: prefix
  } do
    assert :ok = run_migration(:up, prefix)

    for table <- ~w(project_snapshots project_snapshot_captures) do
      assert column_contract(prefix, table) == {true, true}
      assert constraint_exists?(prefix, "#{table}_content_health")
    end

    assert trigger_exists?(prefix, @restore_guard_trigger)
    assert function_exists?(prefix, @restore_guard_function)

    trigger_definition = trigger_definition(prefix, @restore_guard_trigger)

    assert trigger_definition =~
             "BEFORE INSERT OR UPDATE OF phase, project_snapshot_id, status"

    function_definition = function_definition(prefix, @restore_guard_function)
    assert function_definition =~ "FOR KEY SHARE"
    assert function_definition =~ "TG_OP = 'INSERT'"
    assert function_definition =~ "NEW.status IN ('queued', 'running', 'retrying')"
  end

  test "insert rejects unknown, blocked, and malformed health but accepts assessed restorable reports", %{
    prefix: prefix
  } do
    assert :ok = run_migration(:up, prefix)

    unknown_id = insert_snapshot!(prefix, SnapshotContentHealth.unknown())
    blocked_id = insert_snapshot!(prefix, blocked_health())

    malformed_health = put_in(SnapshotContentHealth.healthy(), ["impact_counts", "restore_blocked"], "0")

    malformed_id = insert_snapshot!(prefix, malformed_health)
    legacy_id = insert_snapshot!(prefix, SnapshotContentHealth.legacy_strict())
    healthy_id = insert_snapshot!(prefix, SnapshotContentHealth.healthy())
    warning_id = insert_snapshot!(prefix, runtime_warning_health())

    for snapshot_id <- [unknown_id, blocked_id, malformed_id] do
      assert_restore_guard_rejected(fn -> insert_restore(prefix, snapshot_id, "queued") end)
    end

    assert {:ok, %Postgrex.Result{rows: [[_restore_id]]}} =
             insert_restore(prefix, healthy_id, "queued")

    assert {:ok, %Postgrex.Result{rows: [[_restore_id]]}} =
             insert_restore(prefix, warning_id, "queued")

    assert {:ok, %Postgrex.Result{rows: [[_restore_id]]}} =
             insert_restore(prefix, legacy_id, "queued")

    assert_restore_guard_rejected(fn -> insert_restore(prefix, 999_999, "queued") end)
  end

  test "backfills only finalized strict ready snapshots and keeps the evidence one-shot and immutable", %{
    prefix: prefix
  } do
    legacy_id = insert_strict_ready_snapshot!(prefix)
    captured_id = insert_strict_ready_snapshot!(prefix)
    insert_capture_before_up!(prefix, captured_id)

    negative_snapshots =
      Enum.map(
        [
          format_version: [format_version: 1],
          mode: [mode: "linked"],
          lifecycle_state: [lifecycle_state: "verifying"],
          integrity_state: [integrity_state: "unknown"],
          restore_contract_version: [restore_contract_version: nil],
          capture_digest: [capture_digest: nil],
          captured_at: [captured_at: nil],
          building_started_at: [building_started_at: nil],
          verifying_started_at: [verifying_started_at: nil],
          ready_at: [ready_at: nil],
          cancelled_at: [cancelled_at: ~N[2026-08-15 12:03:00]],
          deletion_requested_at: [deletion_requested_at: ~N[2026-08-15 12:03:00]],
          object_prefix: [object_prefix: "not-a-ready-prefix"],
          archive_storage_key: [archive_storage_key: "snapshot.zip"],
          archive_size_bytes: [archive_size_bytes: 0],
          archive_checksum: [archive_checksum: "invalid"],
          project_size_bytes: [project_size_bytes: 0],
          project_checksum: [project_checksum: "invalid"],
          manifest_storage_key: [manifest_storage_key: "manifest.json"],
          manifest_size_bytes: [manifest_size_bytes: 0],
          manifest_checksum: [manifest_checksum: "invalid"],
          total_size_bytes: [total_size_bytes: 999],
          accounted_size_bytes: [accounted_size_bytes: 999],
          object_count: [object_count: 1],
          asset_count: [asset_count: nil],
          blob_count: [blob_count: nil],
          negative_blob_count: [blob_count: -1],
          asset_blob_order: [asset_count: -1],
          progress_total_bytes: [progress_total_bytes: 999],
          accounting_version: [accounting_version: 2],
          accounting_generation: [accounting_generation: 0],
          lifecycle_generation: [lifecycle_generation: 0]
        ],
        fn {label, overrides} ->
          {label, insert_strict_ready_snapshot!(prefix, overrides)}
        end
      )

    assert :ok = run_migration(:up, prefix)

    assert persisted_health(prefix, legacy_id) == SnapshotContentHealth.legacy_strict()
    refute capture_exists?(prefix, legacy_id)

    for {label, snapshot_id} <- [{:capture_not_finalized, captured_id} | negative_snapshots] do
      assert persisted_health(prefix, snapshot_id) == SnapshotContentHealth.unknown(),
             "#{label} must remain unassessed"

      assert_restore_guard_rejected(fn -> insert_restore(prefix, snapshot_id, "queued") end)
    end

    assert {:ok, %Postgrex.Result{rows: [[_restore_id]]}} =
             insert_restore(prefix, legacy_id, "queued")

    assert_content_health_update_rejected(prefix, legacy_id, SnapshotContentHealth.healthy())

    post_migration_id = insert_strict_ready_snapshot!(prefix)

    assert persisted_health(prefix, post_migration_id) == SnapshotContentHealth.unknown()
    assert_restore_guard_rejected(fn -> insert_restore(prefix, post_migration_id, "queued") end)
  end

  test "every transition into or within an active restore status revalidates content health", %{
    prefix: prefix
  } do
    historical_snapshot_id = insert_snapshot_before_up!(prefix)
    historical_restore_id = insert_restore_before_up!(prefix, historical_snapshot_id, "failed")
    historical_active_snapshot_id = insert_snapshot_before_up!(prefix)

    historical_active_restore_id =
      insert_restore_before_up!(prefix, historical_active_snapshot_id, "queued")

    assert :ok = run_migration(:up, prefix)

    assert_restore_guard_rejected(fn ->
      update_restore_status(prefix, historical_restore_id, "queued")
    end)

    assert_restore_guard_rejected(fn ->
      update_restore_phase(prefix, historical_active_restore_id, "preflight")
    end)

    healthy_snapshot_id = insert_snapshot!(prefix, SnapshotContentHealth.healthy())

    {:ok, %Postgrex.Result{rows: [[restore_id]]}} =
      insert_restore(prefix, healthy_snapshot_id, "failed")

    assert {:ok, %Postgrex.Result{num_rows: 1}} =
             update_restore_status(prefix, restore_id, "queued")

    set_snapshot_health!(prefix, healthy_snapshot_id, blocked_health())

    assert_restore_guard_rejected(fn ->
      update_restore_phase(prefix, restore_id, "preflight")
    end)

    assert_restore_guard_rejected(fn ->
      update_restore_status(prefix, restore_id, "running")
    end)
  end

  test "down is fail-closed and leaves both schema evidence and the restore guard installed", %{
    prefix: prefix
  } do
    assert :ok = run_migration(:up, prefix)

    healthy_id = insert_snapshot!(prefix, SnapshotContentHealth.healthy())
    assert {:ok, _result} = insert_restore(prefix, healthy_id, "queued")

    assert_raise Ecto.MigrationError, ~r/irreversible/, fn ->
      run_migration(:down, prefix)
    end

    assert column_exists?(prefix, "project_snapshots", "content_health")
    assert column_exists?(prefix, "project_snapshot_captures", "content_health")
    assert trigger_exists?(prefix, @restore_guard_trigger)
    assert function_exists?(prefix, @restore_guard_function)

    unknown_id = insert_snapshot!(prefix, SnapshotContentHealth.unknown())
    assert_restore_guard_rejected(fn -> insert_restore(prefix, unknown_id, "queued") end)
  end

  defp create_pre_migration_tables!(prefix) do
    Repo.query!("""
    CREATE TABLE #{prefix}.project_snapshots (
      id bigserial PRIMARY KEY,
      idempotency_key text NOT NULL DEFAULT 'request',
      capture_boundary text NOT NULL DEFAULT 'boundary',
      project_id bigint NOT NULL DEFAULT 1,
      version_number integer NOT NULL DEFAULT 1,
      format_version integer NOT NULL DEFAULT 2,
      mode text NOT NULL DEFAULT 'full',
      lifecycle_state text NOT NULL DEFAULT 'ready',
      integrity_state text NOT NULL DEFAULT 'unknown',
      restore_contract_version integer,
      capture_digest varchar(64),
      captured_at timestamp(0) without time zone,
      object_prefix text,
      archive_storage_key text,
      archive_size_bytes bigint,
      archive_checksum varchar(64),
      project_size_bytes bigint,
      project_checksum varchar(64),
      manifest_storage_key text,
      manifest_size_bytes bigint,
      manifest_checksum varchar(64),
      total_size_bytes bigint,
      accounted_size_bytes bigint,
      object_count integer,
      asset_count integer,
      blob_count integer,
      progress_total_bytes bigint,
      accounting_version integer,
      accounting_generation integer,
      lifecycle_generation integer,
      building_started_at timestamp(0) without time zone,
      verifying_started_at timestamp(0) without time zone,
      ready_at timestamp(0) without time zone,
      cancelled_at timestamp(0) without time zone,
      deletion_requested_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL DEFAULT clock_timestamp()
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.project_snapshot_captures (
      project_snapshot_id bigint PRIMARY KEY,
      capture_digest varchar(64),
      captured_at timestamp(0) without time zone
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.project_snapshot_restores (
      id bigserial PRIMARY KEY,
      project_snapshot_id bigint,
      status text NOT NULL,
      phase text NOT NULL
    )
    """)

    create_pre_migration_immutability_triggers!(prefix)
  end

  defp create_pre_migration_immutability_triggers!(prefix) do
    Repo.query!("""
    CREATE FUNCTION #{prefix}.storyarn_guard_project_snapshot_capture_identity()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.capture_digest IS DISTINCT FROM OLD.capture_digest OR
         NEW.captured_at IS DISTINCT FROM OLD.captured_at THEN
        RAISE EXCEPTION 'project snapshot capture identity is immutable'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      RETURN NEW;
    END;
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER project_snapshots_capture_identity_immutable
    BEFORE UPDATE ON #{prefix}.project_snapshots
    FOR EACH ROW
    EXECUTE FUNCTION #{prefix}.storyarn_guard_project_snapshot_capture_identity()
    """)
  end

  defp blocked_health do
    SnapshotContentHealth.build([
      %{
        code: :unclassified_content_issue,
        severity: :error,
        entity_type: :project,
        entity_id: 1,
        impact: :restore_blocked,
        container_type: :project,
        container_id: 1
      }
    ])
  end

  defp runtime_warning_health do
    SnapshotContentHealth.build([
      %{
        code: :unclassified_content_issue,
        severity: :warning,
        entity_type: :project,
        entity_id: 1,
        impact: :runtime_degraded,
        container_type: :project,
        container_id: 1
      }
    ])
  end

  defp insert_snapshot_before_up!(prefix) do
    %Postgrex.Result{rows: [[id]]} =
      Repo.query!("INSERT INTO #{prefix}.project_snapshots DEFAULT VALUES RETURNING id")

    id
  end

  defp insert_strict_ready_snapshot!(prefix, overrides \\ []) do
    ready_prefix = "projects/1/snapshots/archives/v2/ready/AbCdEfGhIjKlMnOp"

    attrs =
      Keyword.merge(
        [
          project_id: 1,
          format_version: 2,
          mode: "full",
          lifecycle_state: "ready",
          integrity_state: "verified",
          restore_contract_version: 1,
          capture_digest: String.duplicate("a", 64),
          captured_at: ~N[2026-08-15 12:00:00],
          object_prefix: ready_prefix,
          archive_storage_key: ready_prefix <> "/snapshot.zip",
          archive_size_bytes: 700,
          archive_checksum: String.duplicate("b", 64),
          project_size_bytes: 500,
          project_checksum: String.duplicate("c", 64),
          manifest_storage_key: ready_prefix <> "/manifest.json",
          manifest_size_bytes: 300,
          manifest_checksum: String.duplicate("d", 64),
          total_size_bytes: 1_000,
          accounted_size_bytes: 1_000,
          object_count: 2,
          asset_count: 0,
          blob_count: 0,
          progress_total_bytes: 1_000,
          accounting_version: 1,
          accounting_generation: 1,
          lifecycle_generation: 1,
          building_started_at: ~N[2026-08-15 12:01:00],
          verifying_started_at: ~N[2026-08-15 12:02:00],
          ready_at: ~N[2026-08-15 12:03:00],
          cancelled_at: nil,
          deletion_requested_at: nil
        ],
        overrides
      )

    columns = attrs |> Keyword.keys() |> Enum.map_join(", ", &Atom.to_string/1)
    placeholders = Enum.map_join(1..length(attrs), ", ", &"$#{&1}")

    %Postgrex.Result{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO #{prefix}.project_snapshots (#{columns}) VALUES (#{placeholders}) RETURNING id",
        Keyword.values(attrs)
      )

    id
  end

  defp insert_capture_before_up!(prefix, snapshot_id) do
    Repo.query!(
      """
      INSERT INTO #{prefix}.project_snapshot_captures (
        project_snapshot_id, capture_digest, captured_at
      )
      VALUES ($1, $2, $3)
      """,
      [snapshot_id, String.duplicate("a", 64), ~N[2026-08-15 12:00:00]]
    )
  end

  defp insert_snapshot!(prefix, content_health) do
    %Postgrex.Result{rows: [[id]]} =
      Repo.query!(
        """
        INSERT INTO #{prefix}.project_snapshots (content_health)
        VALUES ($1::jsonb)
        RETURNING id
        """,
        [content_health]
      )

    id
  end

  defp set_snapshot_health!(prefix, snapshot_id, content_health) do
    Repo.query!(
      "ALTER TABLE #{prefix}.project_snapshots " <>
        "DISABLE TRIGGER project_snapshots_capture_identity_immutable"
    )

    try do
      Repo.query!(
        "UPDATE #{prefix}.project_snapshots SET content_health = $2::jsonb WHERE id = $1",
        [snapshot_id, content_health]
      )
    after
      Repo.query!(
        "ALTER TABLE #{prefix}.project_snapshots " <>
          "ENABLE TRIGGER project_snapshots_capture_identity_immutable"
      )
    end
  end

  defp persisted_health(prefix, id) do
    %Postgrex.Result{rows: [[health]]} =
      Repo.query!("SELECT content_health FROM #{prefix}.project_snapshots WHERE id = $1", [id])

    health
  end

  defp capture_exists?(prefix, snapshot_id) do
    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!(
        "SELECT EXISTS(SELECT 1 FROM #{prefix}.project_snapshot_captures WHERE project_snapshot_id = $1)",
        [snapshot_id]
      )

    exists?
  end

  defp assert_content_health_update_rejected(prefix, id, content_health) do
    assert {:error, %Postgrex.Error{postgres: %{code: :integrity_constraint_violation}}} =
             Repo.query(
               "UPDATE #{prefix}.project_snapshots SET content_health = $2::jsonb WHERE id = $1",
               [id, content_health],
               mode: :savepoint
             )
  end

  defp insert_restore_before_up!(prefix, snapshot_id, status) do
    {:ok, %Postgrex.Result{rows: [[id]]}} = insert_restore(prefix, snapshot_id, status)
    id
  end

  defp insert_restore(prefix, snapshot_id, status) do
    Repo.query(
      """
      INSERT INTO #{prefix}.project_snapshot_restores (project_snapshot_id, status, phase)
      VALUES ($1, $2, $2)
      RETURNING id
      """,
      [snapshot_id, status],
      mode: :savepoint
    )
  end

  defp update_restore_status(prefix, restore_id, status) do
    Repo.query(
      "UPDATE #{prefix}.project_snapshot_restores SET status = $2 WHERE id = $1",
      [restore_id, status],
      mode: :savepoint
    )
  end

  defp update_restore_phase(prefix, restore_id, phase) do
    Repo.query(
      "UPDATE #{prefix}.project_snapshot_restores SET phase = $2 WHERE id = $1",
      [restore_id, phase],
      mode: :savepoint
    )
  end

  defp run_migration(direction, prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      AddSnapshotContentHealth,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end

  defp assert_restore_guard_rejected(fun) do
    assert {:error, %Postgrex.Error{postgres: %{code: :integrity_constraint_violation}}} =
             fun.()
  end

  defp column_contract(prefix, table) do
    %Postgrex.Result{rows: [[not_null?, has_default?]]} =
      Repo.query!(
        """
        SELECT attribute.attnotnull, default_value.adbin IS NOT NULL
        FROM pg_attribute AS attribute
        JOIN pg_class AS relation ON relation.oid = attribute.attrelid
        JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
        LEFT JOIN pg_attrdef AS default_value
          ON default_value.adrelid = relation.oid AND default_value.adnum = attribute.attnum
        WHERE namespace.nspname = $1 AND relation.relname = $2 AND
              attribute.attname = 'content_health'
        """,
        [prefix, table]
      )

    {not_null?, has_default?}
  end

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
    catalog_object_exists?(prefix, constraint, "pg_constraint", "connamespace", "conname")
  end

  defp function_exists?(prefix, function) do
    catalog_object_exists?(prefix, function, "pg_proc", "pronamespace", "proname")
  end

  defp trigger_exists?(prefix, trigger) do
    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_trigger AS trigger_row
          JOIN pg_class AS table_row ON table_row.oid = trigger_row.tgrelid
          JOIN pg_namespace AS namespace_row ON namespace_row.oid = table_row.relnamespace
          WHERE namespace_row.nspname = $1 AND trigger_row.tgname = $2 AND
                NOT trigger_row.tgisinternal
        )
        """,
        [prefix, trigger]
      )

    exists?
  end

  defp trigger_definition(prefix, trigger) do
    %Postgrex.Result{rows: [[definition]]} =
      Repo.query!(
        """
        SELECT pg_get_triggerdef(trigger_row.oid, true)
        FROM pg_trigger AS trigger_row
        JOIN pg_class AS table_row ON table_row.oid = trigger_row.tgrelid
        JOIN pg_namespace AS namespace_row ON namespace_row.oid = table_row.relnamespace
        WHERE namespace_row.nspname = $1 AND trigger_row.tgname = $2
        """,
        [prefix, trigger]
      )

    definition
  end

  defp function_definition(prefix, function) do
    %Postgrex.Result{rows: [[definition]]} =
      Repo.query!(
        """
        SELECT pg_get_functiondef(function_row.oid)
        FROM pg_proc AS function_row
        JOIN pg_namespace AS namespace_row ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = $1 AND function_row.proname = $2
        """,
        [prefix, function]
      )

    definition
  end

  defp catalog_object_exists?(prefix, name, catalog, namespace_column, name_column) do
    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM #{catalog} AS object_row
          JOIN pg_namespace AS namespace_row
            ON namespace_row.oid = object_row.#{namespace_column}
          WHERE namespace_row.nspname = $1 AND object_row.#{name_column} = $2
        )
        """,
        [prefix, name]
      )

    exists?
  end
end
