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
    healthy_id = insert_snapshot!(prefix, SnapshotContentHealth.healthy())
    warning_id = insert_snapshot!(prefix, runtime_warning_health())

    for snapshot_id <- [unknown_id, blocked_id, malformed_id] do
      assert_restore_guard_rejected(fn -> insert_restore(prefix, snapshot_id, "queued") end)
    end

    assert {:ok, %Postgrex.Result{rows: [[_restore_id]]}} =
             insert_restore(prefix, healthy_id, "queued")

    assert {:ok, %Postgrex.Result{rows: [[_restore_id]]}} =
             insert_restore(prefix, warning_id, "queued")

    assert_restore_guard_rejected(fn -> insert_restore(prefix, 999_999, "queued") end)
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
      lifecycle_state text NOT NULL DEFAULT 'ready',
      capture_digest varchar(64),
      captured_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL DEFAULT clock_timestamp()
    )
    """)

    Repo.query!("CREATE TABLE #{prefix}.project_snapshot_captures (id bigserial PRIMARY KEY)")

    Repo.query!("""
    CREATE TABLE #{prefix}.project_snapshot_restores (
      id bigserial PRIMARY KEY,
      project_snapshot_id bigint,
      status text NOT NULL,
      phase text NOT NULL
    )
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
      "UPDATE #{prefix}.project_snapshots SET content_health = $2::jsonb WHERE id = $1",
      [snapshot_id, content_health]
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
