defmodule Storyarn.Repo.Migrations.SupportDirectWorkspaceSnapshotUploads do
  use Ecto.Migration

  def up do
    execute("DROP INDEX workspace_snapshot_imports_active_idempotency_idx")

    alter table(:workspace_snapshot_imports) do
      remove :idempotency_key
    end

    replace_constraints(up_constraints_sql())

    execute("""
    CREATE UNIQUE INDEX workspace_snapshot_imports_one_active_idx
    ON workspace_snapshot_imports (workspace_id)
    WHERE status IN ('uploading', 'queued', 'running', 'retrying')
    """)
  end

  def down do
    execute("""
    DO $$ BEGIN
      IF EXISTS (
        SELECT 1 FROM workspace_snapshot_imports
        WHERE status = 'uploading' OR archive_checksum IS NULL OR
              manifest_checksum IS NULL OR project_checksum IS NULL
      ) THEN
        RAISE EXCEPTION 'direct snapshot uploads must be resolved before rollback';
      END IF;
    END $$
    """)

    execute("DROP INDEX workspace_snapshot_imports_one_active_idx")
    replace_constraints(down_constraints_sql())

    alter table(:workspace_snapshot_imports) do
      add :idempotency_key, :string, size: 64
    end

    execute("""
    UPDATE workspace_snapshot_imports
    SET idempotency_key = md5(random()::text || clock_timestamp()::text || id::text) ||
                          md5(id::text || random()::text || clock_timestamp()::text)
    """)

    execute("ALTER TABLE workspace_snapshot_imports ALTER COLUMN idempotency_key SET NOT NULL")

    execute("""
    CREATE UNIQUE INDEX workspace_snapshot_imports_active_idempotency_idx
    ON workspace_snapshot_imports (workspace_id, idempotency_key)
    WHERE status IN ('queued', 'running', 'retrying')
    """)
  end

  defp replace_constraints(sql) do
    execute("""
    ALTER TABLE workspace_snapshot_imports
      DROP CONSTRAINT workspace_snapshot_imports_status_check,
      DROP CONSTRAINT workspace_snapshot_imports_stage_check,
      DROP CONSTRAINT workspace_snapshot_imports_identity_check,
      DROP CONSTRAINT workspace_snapshot_imports_lifecycle_check
    """)

    execute(sql)
  end

  defp up_constraints_sql do
    """
    ALTER TABLE workspace_snapshot_imports
      ALTER COLUMN archive_checksum DROP NOT NULL,
      ALTER COLUMN manifest_checksum DROP NOT NULL,
      ALTER COLUMN project_checksum DROP NOT NULL,
      ADD CONSTRAINT workspace_snapshot_imports_status_check
        CHECK (status IN ('uploading', 'queued', 'running', 'retrying', 'completed', 'failed')),
      ADD CONSTRAINT workspace_snapshot_imports_stage_check
        CHECK (stage IN ('uploading', 'queued', 'verifying', 'materializing', 'retrying', 'completed', 'failed')),
      ADD CONSTRAINT workspace_snapshot_imports_identity_check CHECK (
        archive_storage_key <> '' AND octet_length(archive_storage_key) <= 520 AND archive_size_bytes > 0 AND
        (archive_checksum IS NULL OR archive_checksum ~ '^[0-9a-f]{64}$') AND
        (manifest_checksum IS NULL OR manifest_checksum ~ '^[0-9a-f]{64}$') AND
        (project_checksum IS NULL OR project_checksum ~ '^[0-9a-f]{64}$') AND reserved_bytes >= 0 AND
        progress_total_bytes > 0 AND cardinality(staging_storage_keys) <= 10001 AND
        (reserved_project_id IS NULL OR reserved_project_id > 0) AND cardinality(materialization_storage_keys) <= 20000
      ),
      ADD CONSTRAINT workspace_snapshot_imports_lifecycle_check CHECK (
        progress_bytes >= 0 AND progress_bytes <= progress_total_bytes AND attempt >= 0 AND
        max_attempts > 0 AND attempt <= max_attempts AND (
          (status = 'uploading' AND stage = 'uploading' AND attempt = 0 AND started_at IS NULL AND
           completed_at IS NULL AND project_id IS NULL AND oban_job_id IS NULL AND archive_checksum IS NULL AND
           manifest_checksum IS NULL AND project_checksum IS NULL AND reserved_bytes = 0 AND
           reserved_project_id IS NULL AND cardinality(materialization_storage_keys) = 0 AND
           failure_code IS NULL AND failure_details = '{}'::jsonb) OR
          (status = 'queued' AND stage = 'queued' AND attempt = 0 AND started_at IS NULL AND
           completed_at IS NULL AND project_id IS NULL AND reserved_project_id IS NULL AND
           cardinality(materialization_storage_keys) = 0 AND manifest_checksum IS NOT NULL AND
           project_checksum IS NOT NULL AND failure_code IS NULL AND failure_details = '{}'::jsonb) OR
          (status = 'running' AND stage IN ('verifying', 'materializing') AND attempt > 0 AND
           started_at IS NOT NULL AND completed_at IS NULL AND
           (stage <> 'materializing' OR (reserved_project_id IS NOT NULL AND archive_checksum IS NOT NULL)) AND
           project_id IS NULL AND manifest_checksum IS NOT NULL AND project_checksum IS NOT NULL AND
           failure_code IS NULL AND failure_details = '{}'::jsonb) OR
          (status = 'retrying' AND stage = 'retrying' AND attempt > 0 AND started_at IS NOT NULL AND
           completed_at IS NULL AND project_id IS NULL AND manifest_checksum IS NOT NULL AND
           project_checksum IS NOT NULL AND failure_code IS NOT NULL) OR
          (status = 'completed' AND stage = 'completed' AND attempt > 0 AND started_at IS NOT NULL AND
           completed_at IS NOT NULL AND reserved_bytes = 0 AND archive_checksum IS NOT NULL AND
           (project_id IS NULL OR project_id = reserved_project_id) AND progress_bytes = progress_total_bytes AND
           failure_code IS NULL AND failure_details = '{}'::jsonb) OR
          (status = 'failed' AND stage = 'failed' AND started_at IS NOT NULL AND completed_at IS NOT NULL AND
           project_id IS NULL AND reserved_bytes = 0 AND failure_code IS NOT NULL)
        )
      )
    """
  end

  defp down_constraints_sql do
    """
    ALTER TABLE workspace_snapshot_imports
      ALTER COLUMN archive_checksum SET NOT NULL,
      ALTER COLUMN manifest_checksum SET NOT NULL,
      ALTER COLUMN project_checksum SET NOT NULL,
      ADD CONSTRAINT workspace_snapshot_imports_status_check
        CHECK (status IN ('queued', 'running', 'retrying', 'completed', 'failed')),
      ADD CONSTRAINT workspace_snapshot_imports_stage_check
        CHECK (stage IN ('queued', 'verifying', 'materializing', 'retrying', 'completed', 'failed')),
      ADD CONSTRAINT workspace_snapshot_imports_identity_check CHECK (
        archive_storage_key <> '' AND octet_length(archive_storage_key) <= 520 AND archive_size_bytes > 0 AND
        archive_checksum ~ '^[0-9a-f]{64}$' AND manifest_checksum ~ '^[0-9a-f]{64}$' AND
        project_checksum ~ '^[0-9a-f]{64}$' AND reserved_bytes >= 0 AND progress_total_bytes > 0 AND
        cardinality(staging_storage_keys) <= 10001 AND (reserved_project_id IS NULL OR reserved_project_id > 0) AND
        cardinality(materialization_storage_keys) <= 20000
      ),
      ADD CONSTRAINT workspace_snapshot_imports_lifecycle_check CHECK (
        progress_bytes >= 0 AND progress_bytes <= progress_total_bytes AND attempt >= 0 AND max_attempts > 0 AND
        attempt <= max_attempts AND (
          (status = 'queued' AND stage = 'queued' AND attempt = 0 AND started_at IS NULL AND completed_at IS NULL AND
           project_id IS NULL AND reserved_project_id IS NULL AND cardinality(materialization_storage_keys) = 0 AND
           failure_code IS NULL AND failure_details = '{}'::jsonb) OR
          (status = 'running' AND stage IN ('verifying', 'materializing') AND attempt > 0 AND
           started_at IS NOT NULL AND completed_at IS NULL AND (stage <> 'materializing' OR reserved_project_id IS NOT NULL) AND
           project_id IS NULL AND failure_code IS NULL AND failure_details = '{}'::jsonb) OR
          (status = 'retrying' AND stage = 'retrying' AND attempt > 0 AND started_at IS NOT NULL AND
           completed_at IS NULL AND project_id IS NULL AND failure_code IS NOT NULL) OR
          (status = 'completed' AND stage = 'completed' AND attempt > 0 AND started_at IS NOT NULL AND
           completed_at IS NOT NULL AND reserved_bytes = 0 AND (project_id IS NULL OR project_id = reserved_project_id) AND
           progress_bytes = progress_total_bytes AND failure_code IS NULL AND failure_details = '{}'::jsonb) OR
          (status = 'failed' AND stage = 'failed' AND started_at IS NOT NULL AND completed_at IS NOT NULL AND
           project_id IS NULL AND reserved_bytes = 0 AND failure_code IS NOT NULL)
        )
      )
    """
  end
end
