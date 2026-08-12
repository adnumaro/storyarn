defmodule Storyarn.Repo.Migrations.CaptureSnapshotArchivesInWorker do
  use Ecto.Migration

  def up do
    alter table(:project_snapshots) do
      modify :project_size_bytes, :bigint, null: true, from: {:bigint, null: false}

      modify :capture_digest, :string,
        size: 64,
        null: true,
        from: {:string, size: 64, null: false}

      modify :captured_at, :utc_datetime, null: true, from: {:utc_datetime, null: false}
    end

    drop constraint(:project_snapshots, :project_snapshots_archive_format)
    drop constraint(:project_snapshots, :project_snapshots_build_progress)

    create constraint(:project_snapshots, :project_snapshots_archive_format,
             check: archive_format_check()
           )

    create constraint(:project_snapshots, :project_snapshots_build_progress,
             check: build_progress_check()
           )

    replace_capture_identity_function(capture_identity_function())
  end

  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM project_snapshots
        WHERE format_version = 2 AND capture_digest IS NULL
      ) THEN
        RAISE EXCEPTION 'cannot restore synchronous snapshot capture while uncaptured archive requests exist'
          USING ERRCODE = 'object_not_in_prerequisite_state';
      END IF;
    END;
    $$
    """)

    drop constraint(:project_snapshots, :project_snapshots_archive_format)
    drop constraint(:project_snapshots, :project_snapshots_build_progress)

    create constraint(:project_snapshots, :project_snapshots_archive_format,
             check: previous_archive_format_check()
           )

    create constraint(:project_snapshots, :project_snapshots_build_progress,
             check: previous_build_progress_check()
           )

    replace_capture_identity_function(previous_capture_identity_function())

    alter table(:project_snapshots) do
      modify :project_size_bytes, :bigint, null: false, from: {:bigint, null: true}

      modify :capture_digest, :string,
        size: 64,
        null: false,
        from: {:string, size: 64, null: true}

      modify :captured_at, :utc_datetime, null: false, from: {:utc_datetime, null: true}
    end
  end

  defp archive_format_check do
    """
    (format_version = 1 AND project_size_bytes IS NOT NULL AND project_size_bytes > 0 AND
     capture_digest IS NOT NULL AND capture_digest ~ '^[0-9a-f]{64}$' AND captured_at IS NOT NULL AND
     archive_storage_key IS NULL AND archive_size_bytes IS NULL AND archive_checksum IS NULL) OR
    (format_version = 2 AND mode = 'full' AND project_storage_key IS NULL AND
     archive_storage_key IS NOT NULL AND
     ((lifecycle_state IN ('pending', 'failed', 'cancelled', 'deleting') AND capture_digest IS NULL AND
       project_size_bytes IS NULL AND captured_at IS NULL AND archive_size_bytes IS NULL AND
       archive_checksum IS NULL) OR
      (project_size_bytes IS NOT NULL AND project_size_bytes > 0 AND
       capture_digest IS NOT NULL AND capture_digest ~ '^[0-9a-f]{64}$' AND captured_at IS NOT NULL AND
       archive_size_bytes IS NOT NULL AND archive_size_bytes > 0 AND
       (archive_checksum IS NULL OR archive_checksum ~ '^[0-9a-f]{64}$'))))
    """
  end

  defp build_progress_check do
    """
    (capture_digest IS NULL AND lifecycle_state IN ('pending', 'failed', 'cancelled', 'deleting') AND
     ((lifecycle_state = 'pending' AND progress_phase = 'pending') OR
      (lifecycle_state = 'failed' AND progress_phase = 'failed') OR
      (lifecycle_state = 'cancelled' AND progress_phase = 'cancelled') OR
      (lifecycle_state = 'deleting' AND progress_phase IN ('pending', 'failed', 'cancelled'))) AND
     progress_bytes = 0 AND
     progress_total_bytes = 0 AND build_attempt = 0) OR
    (progress_phase IN
       ('pending', 'copying', 'verifying', 'finalizing', 'retrying',
        'complete', 'failed', 'cancelled') AND
     progress_bytes >= 0 AND progress_total_bytes > 0 AND
     progress_bytes <= progress_total_bytes AND build_attempt >= 0)
    """
  end

  defp previous_archive_format_check do
    """
    (format_version = 1 AND archive_storage_key IS NULL AND
     archive_size_bytes IS NULL AND archive_checksum IS NULL) OR
    (format_version = 2 AND mode = 'full' AND project_storage_key IS NULL AND
     archive_storage_key IS NOT NULL AND archive_size_bytes IS NOT NULL AND
     archive_size_bytes > 0 AND
     (archive_checksum IS NULL OR archive_checksum ~ '^[0-9a-f]{64}$'))
    """
  end

  defp previous_build_progress_check do
    """
    progress_phase IN
      ('pending', 'copying', 'verifying', 'finalizing', 'retrying',
       'complete', 'failed', 'cancelled') AND
    progress_bytes >= 0 AND progress_total_bytes > 0 AND
    progress_bytes <= progress_total_bytes AND build_attempt >= 0
    """
  end

  defp replace_capture_identity_function(body) do
    execute("""
    CREATE OR REPLACE FUNCTION storyarn_guard_project_snapshot_capture_identity()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    #{body}
    $$
    """)
  end

  defp capture_identity_function do
    """
    BEGIN
      IF NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key OR
         NEW.capture_boundary IS DISTINCT FROM OLD.capture_boundary OR
         NEW.project_id IS DISTINCT FROM OLD.project_id OR
         NEW.version_number IS DISTINCT FROM OLD.version_number OR
         NEW.inserted_at IS DISTINCT FROM OLD.inserted_at THEN
        RAISE EXCEPTION 'project snapshot capture identity is immutable'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      IF (NEW.capture_digest IS DISTINCT FROM OLD.capture_digest OR
          NEW.captured_at IS DISTINCT FROM OLD.captured_at) AND NOT (
        OLD.format_version = 2 AND OLD.lifecycle_state = 'pending' AND
        OLD.capture_digest IS NULL AND OLD.captured_at IS NULL AND
        NEW.format_version = 2 AND NEW.lifecycle_state = 'pending' AND
        NEW.capture_digest IS NOT NULL AND NEW.captured_at IS NOT NULL
      ) THEN
        RAISE EXCEPTION 'project snapshot capture identity is immutable'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      RETURN NEW;
    END;
    """
  end

  defp previous_capture_identity_function do
    """
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
    """
  end
end
