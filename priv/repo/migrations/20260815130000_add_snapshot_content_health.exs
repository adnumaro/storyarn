defmodule Storyarn.Repo.Migrations.AddSnapshotContentHealth do
  use Ecto.Migration

  @unknown %{
    "impact_counts" => %{"restore_blocked" => 0, "runtime_degraded" => 0},
    "issue_count" => 0,
    "issue_counts_by_code" => %{},
    "issues" => [],
    "issues_truncated" => false,
    "severity_counts" => %{"error" => 0, "warning" => 0, "info" => 0},
    "state" => "unknown",
    "version" => 1
  }

  @restore_guard_function :storyarn_guard_project_snapshot_restore_content_health
  @restore_guard_trigger :project_snapshot_restores_content_health_guard

  def up do
    alter table(:project_snapshots) do
      add :content_health, :map, null: false, default: @unknown
    end

    alter table(:project_snapshot_captures) do
      add :content_health, :map, null: false, default: @unknown
    end

    create constraint(:project_snapshots, :project_snapshots_content_health,
             check: content_health_check()
           )

    create constraint(:project_snapshot_captures, :project_snapshot_captures_content_health,
             check: content_health_check()
           )

    replace_capture_identity_function(capture_identity_function())
    create_restore_content_health_guard()
  end

  def down do
    raise Ecto.MigrationError,
          "AddSnapshotContentHealth is irreversible because removing the content-health " <>
            "columns or restore guard would let older application versions restore " <>
            "unassessed or explicitly blocked snapshots"
  end

  defp content_health_check do
    """
    (
      jsonb_typeof(content_health) = 'object' AND
      content_health ?& ARRAY[
        'impact_counts', 'issue_count', 'issue_counts_by_code', 'issues',
        'issues_truncated', 'severity_counts', 'state', 'version'
      ] AND
      octet_length(content_health::text) <= 65536 AND
      content_health->>'version' = '1' AND
      content_health->>'state' IN ('unknown', 'healthy', 'warnings') AND
      jsonb_typeof(content_health->'issue_count') = 'number' AND
      (content_health->>'issue_count') ~ '^[0-9]+$' AND
      jsonb_typeof(content_health->'issues_truncated') = 'boolean' AND
      jsonb_typeof(content_health->'issue_counts_by_code') = 'object' AND
      jsonb_typeof(content_health->'impact_counts') = 'object' AND
      jsonb_typeof(content_health->'severity_counts') = 'object' AND
      jsonb_typeof(content_health->'issues') = 'array' AND
      jsonb_array_length(content_health->'issues') <= 50
    ) IS TRUE
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

      IF NEW.content_health IS DISTINCT FROM OLD.content_health AND NOT ((
          OLD.format_version = 2 AND OLD.lifecycle_state = 'pending' AND
          OLD.capture_digest IS NULL AND OLD.captured_at IS NULL AND
          OLD.content_health = '#{Jason.encode!(@unknown)}'::jsonb AND
          NEW.format_version = 2 AND NEW.lifecycle_state = 'pending' AND
          NEW.capture_digest IS NOT NULL AND NEW.captured_at IS NOT NULL AND
          NEW.content_health->>'state' IN ('healthy', 'warnings')
        ) IS TRUE) THEN
        RAISE EXCEPTION 'project snapshot content health is immutable'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      RETURN NEW;
    END;
    """
  end

  defp create_restore_content_health_guard do
    execute("""
    CREATE FUNCTION #{@restore_guard_function}()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      snapshot_health jsonb;
    BEGIN
      IF TG_OP = 'INSERT' OR NEW.status IN ('queued', 'running', 'retrying') THEN
        IF NEW.project_snapshot_id IS NULL THEN
          RAISE EXCEPTION 'project snapshot restore content health is not restorable'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;

        SELECT snapshot.content_health
        INTO snapshot_health
        FROM project_snapshots AS snapshot
        WHERE snapshot.id = NEW.project_snapshot_id
        FOR KEY SHARE;

        IF NOT FOUND OR NOT ((
          jsonb_typeof(snapshot_health) = 'object' AND
          jsonb_typeof(snapshot_health->'state') = 'string' AND
          snapshot_health->>'state' IN ('healthy', 'warnings') AND
          jsonb_typeof(snapshot_health->'impact_counts') = 'object' AND
          jsonb_typeof(snapshot_health->'impact_counts'->'restore_blocked') = 'number' AND
          snapshot_health->'impact_counts'->>'restore_blocked' = '0'
        ) IS TRUE) THEN
          RAISE EXCEPTION 'project snapshot restore content health is not restorable'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER #{@restore_guard_trigger}
    BEFORE INSERT OR UPDATE OF phase, project_snapshot_id, status ON project_snapshot_restores
    FOR EACH ROW
    EXECUTE FUNCTION #{@restore_guard_function}()
    """)
  end
end
