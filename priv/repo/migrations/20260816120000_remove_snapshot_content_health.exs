defmodule Storyarn.Repo.Migrations.RemoveSnapshotContentHealth do
  use Ecto.Migration

  # The published migration that introduced content_health remains in the
  # migration chain. Keep those columns so older application instances can
  # finish a rolling deployment, while removing every database health gate.
  def up do
    execute("""
    DROP TRIGGER IF EXISTS project_snapshot_restores_content_health_guard
    ON project_snapshot_restores
    """)

    execute("""
    DROP FUNCTION IF EXISTS storyarn_guard_project_snapshot_restore_content_health()
    """)

    restore_capture_identity_function()

    execute("""
    ALTER TABLE project_snapshots
    DROP CONSTRAINT IF EXISTS project_snapshots_content_health
    """)

    execute("""
    ALTER TABLE project_snapshot_captures
    DROP CONSTRAINT IF EXISTS project_snapshot_captures_content_health
    """)
  end

  def down do
    raise Ecto.MigrationError,
          "RemoveSnapshotContentHealth is irreversible because the removed health guards " <>
            "cannot be reconstructed safely"
  end

  defp restore_capture_identity_function do
    execute("""
    CREATE OR REPLACE FUNCTION storyarn_guard_project_snapshot_capture_identity()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
    $$
    """)
  end
end
