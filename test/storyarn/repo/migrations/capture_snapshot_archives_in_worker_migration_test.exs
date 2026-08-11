defmodule Storyarn.Repo.Migrations.CaptureSnapshotArchivesInWorkerMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.CaptureSnapshotArchivesInWorker

  @migration_version 20_260_811_140_000

  if !Code.ensure_loaded?(CaptureSnapshotArchivesInWorker) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260811140000_capture_snapshot_archives_in_worker.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "snapshot_worker_capture_migration_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    create_schema!(prefix)
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    %{prefix: prefix}
  end

  test "up admits queued and terminal uncaptured archive rows", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)

    assert {:ok, _result} = insert_uncaptured(prefix, "pending", "pending")
    queued_id = latest_id(prefix)

    assert {:ok, _result} = materialize_capture(prefix, queued_id)

    assert {:error, %Postgrex.Error{postgres: %{code: :integrity_constraint_violation}}} =
             mutate_capture_digest(prefix, queued_id)

    assert {:ok, _result} = insert_uncaptured(prefix, "failed", "failed")
    assert {:ok, _result} = insert_uncaptured(prefix, "cancelled", "cancelled")

    for {state, phase} <- [{"pending", "pending"}, {"failed", "failed"}, {"cancelled", "cancelled"}] do
      assert {:ok, _result} = insert_uncaptured(prefix, state, phase)
      assert {:ok, _result} = mark_deleting(prefix, latest_id(prefix))
    end

    assert {:ok, _result} = insert_uncaptured(prefix, "deleting", "cancelled")

    refute column_not_null?(prefix, "project_size_bytes")
    refute column_not_null?(prefix, "capture_digest")
    refute column_not_null?(prefix, "captured_at")

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_uncaptured(prefix, "building", "copying")

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_captured(prefix, archive_size_bytes: nil)

    assert {:ok, _result} = insert_uncaptured(prefix, "pending", "pending")

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             partially_materialize_capture(prefix, latest_id(prefix))

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_uncaptured_v1(prefix)
  end

  test "empty down restores the synchronous capture shape and can reapply", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    assert :ok = run_migration(:down, prefix)

    assert column_not_null?(prefix, "project_size_bytes")
    assert column_not_null?(prefix, "capture_digest")
    assert column_not_null?(prefix, "captured_at")

    assert :ok = run_migration(:up, prefix)
    assert {:ok, _result} = insert_uncaptured(prefix, "pending", "pending")
  end

  test "down fails before DDL while an uncaptured request exists", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    assert {:ok, _result} = insert_uncaptured(prefix, "pending", "pending")

    error =
      assert_raise Postgrex.Error, fn ->
        run_migration(:down, prefix)
      end

    assert error.postgres.code == :object_not_in_prerequisite_state
    assert error.postgres.pg_code == "55000"
    assert query_count(prefix) == 1
    refute column_not_null?(prefix, "capture_digest")
    assert constraint_exists?(prefix, "project_snapshots_archive_format")
    assert constraint_exists?(prefix, "project_snapshots_build_progress")
  end

  defp create_schema!(prefix) do
    Repo.query!("""
    CREATE TABLE #{prefix}.project_snapshots (
      id bigserial PRIMARY KEY,
      project_id bigint NOT NULL DEFAULT 1,
      version_number integer NOT NULL DEFAULT 1,
      idempotency_key uuid NOT NULL DEFAULT '00000000-0000-4000-8000-000000000001',
      capture_boundary uuid NOT NULL DEFAULT '00000000-0000-4000-8000-000000000002',
      inserted_at timestamp(0) without time zone NOT NULL DEFAULT clock_timestamp(),
      format_version integer NOT NULL,
      mode text NOT NULL,
      lifecycle_state text NOT NULL,
      project_storage_key varchar(520),
      project_size_bytes bigint NOT NULL,
      capture_digest varchar(64) NOT NULL,
      captured_at timestamp(0) without time zone NOT NULL,
      archive_storage_key varchar(520),
      archive_size_bytes bigint,
      archive_checksum varchar(64),
      progress_phase text NOT NULL,
      progress_bytes bigint NOT NULL,
      progress_total_bytes bigint NOT NULL,
      build_attempt integer NOT NULL,
      CONSTRAINT project_snapshots_archive_format CHECK (
        (format_version = 1 AND archive_storage_key IS NULL AND
         archive_size_bytes IS NULL AND archive_checksum IS NULL) OR
        (format_version = 2 AND mode = 'full' AND archive_storage_key IS NOT NULL AND
         archive_size_bytes IS NOT NULL AND archive_size_bytes > 0 AND
         (archive_checksum IS NULL OR archive_checksum ~ '^[0-9a-f]{64}$'))
      ),
      CONSTRAINT project_snapshots_build_progress CHECK (
        progress_phase IN
          ('pending', 'copying', 'verifying', 'finalizing', 'retrying',
           'complete', 'failed', 'cancelled') AND
        progress_bytes >= 0 AND progress_total_bytes > 0 AND
        progress_bytes <= progress_total_bytes AND build_attempt >= 0
      )
    )
    """)

    Repo.query!("""
    CREATE FUNCTION #{prefix}.storyarn_guard_project_snapshot_capture_identity()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key OR
         NEW.capture_boundary IS DISTINCT FROM OLD.capture_boundary OR
         NEW.capture_digest IS DISTINCT FROM OLD.capture_digest OR
         NEW.captured_at IS DISTINCT FROM OLD.captured_at OR
         NEW.project_id IS DISTINCT FROM OLD.project_id OR
         NEW.version_number IS DISTINCT FROM OLD.version_number OR
         NEW.inserted_at IS DISTINCT FROM OLD.inserted_at THEN
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

  defp insert_uncaptured(prefix, lifecycle_state, progress_phase) do
    Repo.query(
      """
      INSERT INTO #{prefix}.project_snapshots (
        format_version, mode, lifecycle_state, project_size_bytes,
        capture_digest, captured_at, archive_storage_key, archive_size_bytes,
        archive_checksum, progress_phase, progress_bytes,
        progress_total_bytes, build_attempt
      )
      VALUES (2, 'full', $1, NULL, NULL, NULL, 'snapshot.zip', NULL, NULL, $2, 0, 0, 0)
      """,
      [lifecycle_state, progress_phase],
      mode: :savepoint
    )
  end

  defp insert_captured(prefix, overrides) do
    archive_size_bytes = Keyword.get(overrides, :archive_size_bytes, 1)

    Repo.query(
      """
      INSERT INTO #{prefix}.project_snapshots (
        format_version, mode, lifecycle_state, project_size_bytes,
        capture_digest, captured_at, archive_storage_key, archive_size_bytes,
        archive_checksum, progress_phase, progress_bytes,
        progress_total_bytes, build_attempt
      )
      VALUES (
        2, 'full', 'pending', 1, $1, clock_timestamp(), 'snapshot.zip', $2,
        NULL, 'pending', 0, 1, 0
      )
      """,
      [String.duplicate("a", 64), archive_size_bytes],
      mode: :savepoint
    )
  end

  defp materialize_capture(prefix, id) do
    Repo.query(
      """
      UPDATE #{prefix}.project_snapshots
      SET project_size_bytes = 1,
          capture_digest = $2,
          captured_at = clock_timestamp(),
          archive_size_bytes = 1,
          progress_total_bytes = 1
      WHERE id = $1
      """,
      [id, String.duplicate("b", 64)],
      mode: :savepoint
    )
  end

  defp partially_materialize_capture(prefix, id) do
    Repo.query(
      "UPDATE #{prefix}.project_snapshots SET archive_size_bytes = 1 WHERE id = $1",
      [id],
      mode: :savepoint
    )
  end

  defp insert_uncaptured_v1(prefix) do
    Repo.query(
      """
      INSERT INTO #{prefix}.project_snapshots (
        format_version, mode, lifecycle_state, project_storage_key,
        project_size_bytes, capture_digest, captured_at, progress_phase,
        progress_bytes, progress_total_bytes, build_attempt
      )
      VALUES (1, 'full', 'pending', 'project.json', NULL, NULL, NULL, 'pending', 0, 1, 0)
      """,
      [],
      mode: :savepoint
    )
  end

  defp mutate_capture_digest(prefix, id) do
    Repo.query(
      "UPDATE #{prefix}.project_snapshots SET capture_digest = $2 WHERE id = $1",
      [id, String.duplicate("c", 64)],
      mode: :savepoint
    )
  end

  defp mark_deleting(prefix, id) do
    Repo.query(
      "UPDATE #{prefix}.project_snapshots SET lifecycle_state = 'deleting' WHERE id = $1",
      [id],
      mode: :savepoint
    )
  end

  defp latest_id(prefix) do
    %Postgrex.Result{rows: [[id]]} = Repo.query!("SELECT max(id) FROM #{prefix}.project_snapshots")
    id
  end

  defp run_migration(direction, prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      CaptureSnapshotArchivesInWorker,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end

  defp query_count(prefix) do
    %Postgrex.Result{rows: [[count]]} = Repo.query!("SELECT count(*) FROM #{prefix}.project_snapshots")
    count
  end

  defp column_not_null?(prefix, column_name) do
    %Postgrex.Result{rows: [[not_null?]]} =
      Repo.query!(
        """
        SELECT attribute.attnotnull
        FROM pg_attribute AS attribute
        JOIN pg_class AS relation ON relation.oid = attribute.attrelid
        JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
        WHERE namespace.nspname = $1 AND relation.relname = 'project_snapshots' AND
              attribute.attname = $2
        """,
        [prefix, column_name]
      )

    not_null?
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
end
