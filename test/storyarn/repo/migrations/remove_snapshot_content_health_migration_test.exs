defmodule Storyarn.Repo.Migrations.RemoveSnapshotContentHealthMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.RemoveSnapshotContentHealth

  @migration_version 20_260_816_120_000
  @capture_identity_function "storyarn_guard_project_snapshot_capture_identity"
  @capture_identity_trigger "project_snapshots_capture_identity_immutable"
  @restore_guard_function "storyarn_guard_project_snapshot_restore_content_health"
  @restore_guard_trigger "project_snapshot_restores_content_health_guard"

  if !Code.ensure_loaded?(RemoveSnapshotContentHealth) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260816120000_remove_snapshot_content_health.exs",
        __DIR__
      )
    )
  end

  test "fresh migrated schema retains inert legacy columns without a restore gate" do
    prefix = current_schema()

    for table <- ~w(project_snapshots project_snapshot_captures) do
      assert column_exists?(prefix, table, "content_health")
      refute constraint_exists?(prefix, "#{table}_content_health")
    end

    refute trigger_exists?(prefix, @restore_guard_trigger)
    refute function_exists?(prefix, @restore_guard_function)

    assert trigger_exists?(prefix, @capture_identity_trigger)
    assert function_exists?(prefix, @capture_identity_function)

    definition = function_definition(prefix, @capture_identity_function)
    assert definition =~ "capture_digest"
    assert definition =~ "capture identity is immutable"
    refute definition =~ "content_health"
  end

  test "upgrade removes health gates but retains legacy columns for rolling compatibility" do
    prefix = "remove_snapshot_health_migration_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    create_upgrade_schema!(prefix)
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])

    assert trigger_exists?(prefix, @restore_guard_trigger)
    assert function_exists?(prefix, @restore_guard_function)
    assert function_definition(prefix, @capture_identity_function) =~ "content_health"

    assert :ok = run_migration(:up, prefix)

    for table <- ~w(project_snapshots project_snapshot_captures) do
      assert column_exists?(prefix, table, "content_health")
      refute constraint_exists?(prefix, "#{table}_content_health")
    end

    refute trigger_exists?(prefix, @restore_guard_trigger)
    refute function_exists?(prefix, @restore_guard_function)

    assert trigger_exists?(prefix, @capture_identity_trigger)
    assert function_exists?(prefix, @capture_identity_function)

    definition = function_definition(prefix, @capture_identity_function)
    assert definition =~ "capture_digest"
    assert definition =~ "capture identity is immutable"
    refute definition =~ "content_health"

    snapshot_id = insert_snapshot!(prefix)
    capture_id = insert_capture!(prefix)

    assert {:ok, _result} = replace_legacy_health(prefix, "project_snapshots", snapshot_id)
    assert {:ok, _result} = replace_legacy_health(prefix, "project_snapshot_captures", capture_id)
    assert {:ok, _result} = insert_restore(prefix, snapshot_id)

    assert_raise Ecto.MigrationError, ~r/irreversible/, fn ->
      run_migration(:down, prefix)
    end

    for table <- ~w(project_snapshots project_snapshot_captures) do
      assert column_exists?(prefix, table, "content_health")
      refute constraint_exists?(prefix, "#{table}_content_health")
    end

    refute trigger_exists?(prefix, @restore_guard_trigger)
    refute function_exists?(prefix, @restore_guard_function)
  end

  defp create_upgrade_schema!(prefix) do
    Repo.query!("""
    CREATE TABLE #{prefix}.project_snapshots (
      id bigserial PRIMARY KEY,
      idempotency_key uuid NOT NULL DEFAULT '00000000-0000-4000-8000-000000000001',
      capture_boundary uuid NOT NULL DEFAULT '00000000-0000-4000-8000-000000000002',
      project_id bigint NOT NULL DEFAULT 1,
      version_number integer NOT NULL DEFAULT 1,
      inserted_at timestamp(0) without time zone NOT NULL DEFAULT clock_timestamp(),
      format_version integer NOT NULL DEFAULT 2,
      lifecycle_state text NOT NULL DEFAULT 'pending',
      capture_digest varchar(64),
      captured_at timestamp(0) without time zone,
      content_health jsonb NOT NULL DEFAULT '{}'::jsonb,
      CONSTRAINT project_snapshots_content_health CHECK (
        jsonb_typeof(content_health) = 'object'
      )
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.project_snapshot_captures (
      id bigserial PRIMARY KEY,
      content_health jsonb NOT NULL DEFAULT '{}'::jsonb,
      CONSTRAINT project_snapshot_captures_content_health CHECK (
        jsonb_typeof(content_health) = 'object'
      )
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.project_snapshot_restores (
      id bigserial PRIMARY KEY,
      project_snapshot_id bigint,
      status text NOT NULL DEFAULT 'queued',
      phase text NOT NULL DEFAULT 'queued'
    )
    """)

    Repo.query!("""
    CREATE FUNCTION #{prefix}.storyarn_guard_project_snapshot_capture_identity()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.content_health IS DISTINCT FROM OLD.content_health THEN
        RAISE EXCEPTION 'project snapshot content health is immutable'
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

    Repo.query!("""
    CREATE FUNCTION #{prefix}.storyarn_guard_project_snapshot_restore_content_health()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      RAISE EXCEPTION 'project snapshot restore content health is not restorable'
        USING ERRCODE = 'integrity_constraint_violation';
    END;
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER project_snapshot_restores_content_health_guard
    BEFORE INSERT OR UPDATE OF phase, project_snapshot_id, status
    ON #{prefix}.project_snapshot_restores
    FOR EACH ROW
    EXECUTE FUNCTION #{prefix}.storyarn_guard_project_snapshot_restore_content_health()
    """)
  end

  defp insert_snapshot!(prefix) do
    %Postgrex.Result{rows: [[id]]} =
      Repo.query!("INSERT INTO #{prefix}.project_snapshots DEFAULT VALUES RETURNING id")

    id
  end

  defp insert_capture!(prefix) do
    %Postgrex.Result{rows: [[id]]} =
      Repo.query!("INSERT INTO #{prefix}.project_snapshot_captures DEFAULT VALUES RETURNING id")

    id
  end

  defp replace_legacy_health(prefix, table, id) do
    Repo.query(
      "UPDATE #{prefix}.#{table} SET content_health = $2::jsonb WHERE id = $1",
      [id, ~s("inert")],
      mode: :savepoint
    )
  end

  defp insert_restore(prefix, snapshot_id) do
    Repo.query(
      "INSERT INTO #{prefix}.project_snapshot_restores (project_snapshot_id) VALUES ($1)",
      [snapshot_id],
      mode: :savepoint
    )
  end

  defp run_migration(direction, prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      RemoveSnapshotContentHealth,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end

  defp current_schema do
    %Postgrex.Result{rows: [[schema]]} = Repo.query!("SELECT current_schema()")
    schema
  end

  defp column_exists?(prefix, table, column) do
    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_attribute AS attribute
          JOIN pg_class AS relation ON relation.oid = attribute.attrelid
          JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
          WHERE namespace.nspname = $1 AND relation.relname = $2 AND
                attribute.attname = $3 AND attribute.attnum > 0 AND NOT attribute.attisdropped
        )
        """,
        [prefix, table, column]
      )

    exists?
  end

  defp constraint_exists?(prefix, constraint) do
    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_constraint AS constraint_row
          JOIN pg_namespace AS namespace ON namespace.oid = constraint_row.connamespace
          WHERE namespace.nspname = $1 AND constraint_row.conname = $2
        )
        """,
        [prefix, constraint]
      )

    exists?
  end

  defp trigger_exists?(prefix, trigger) do
    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_trigger AS trigger_row
          JOIN pg_class AS relation ON relation.oid = trigger_row.tgrelid
          JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
          WHERE namespace.nspname = $1 AND trigger_row.tgname = $2 AND
                NOT trigger_row.tgisinternal
        )
        """,
        [prefix, trigger]
      )

    exists?
  end

  defp function_exists?(prefix, function) do
    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_proc AS procedure
          JOIN pg_namespace AS namespace ON namespace.oid = procedure.pronamespace
          WHERE namespace.nspname = $1 AND procedure.proname = $2
        )
        """,
        [prefix, function]
      )

    exists?
  end

  defp function_definition(prefix, function) do
    %Postgrex.Result{rows: [[definition]]} =
      Repo.query!(
        """
        SELECT pg_get_functiondef(procedure.oid)
        FROM pg_proc AS procedure
        JOIN pg_namespace AS namespace ON namespace.oid = procedure.pronamespace
        WHERE namespace.nspname = $1 AND procedure.proname = $2
        """,
        [prefix, function]
      )

    definition
  end
end
