defmodule Storyarn.Repo.Migrations.CreateWorkspaceSnapshotImports do
  use Ecto.Migration

  def change do
    create table(:workspace_snapshot_imports) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :project_id, references(:projects, on_delete: :nilify_all)
      add :oban_job_id, references(:oban_jobs, type: :bigint, on_delete: :nilify_all)

      add :idempotency_key, :string, size: 64, null: false
      add :original_filename, :string, size: 255, null: false
      add :project_name, :string, size: 255, null: false
      add :archive_storage_key, :string, size: 520, null: false
      add :archive_size_bytes, :bigint, null: false
      add :archive_checksum, :string, size: 64, null: false
      add :manifest_checksum, :string, size: 64, null: false
      add :project_checksum, :string, size: 64, null: false
      add :reserved_bytes, :bigint, null: false
      add :staging_storage_keys, {:array, :string}, null: false, default: []
      add :reserved_project_id, :bigint
      add :materialization_storage_keys, {:array, :string}, null: false, default: []

      add :status, :string, null: false, default: "queued"
      add :stage, :string, null: false, default: "queued"
      add :progress_bytes, :bigint, null: false, default: 0
      add :progress_total_bytes, :bigint, null: false
      add :attempt, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false, default: 3
      add :failure_code, :string, size: 100
      add :failure_details, :map, null: false, default: %{}
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:workspace_snapshot_imports, [:workspace_id, :idempotency_key],
             where: "status IN ('queued', 'running', 'retrying')",
             name: :workspace_snapshot_imports_active_idempotency_idx
           )

    create unique_index(:workspace_snapshot_imports, [:oban_job_id],
             where: "oban_job_id IS NOT NULL",
             name: :workspace_snapshot_imports_oban_job_idx
           )

    create index(:workspace_snapshot_imports, [:workspace_id, :status, :inserted_at],
             name: :workspace_snapshot_imports_workspace_status_idx
           )

    create index(:workspace_snapshot_imports, [:user_id, :status, :inserted_at],
             name: :workspace_snapshot_imports_user_status_idx
           )

    create index(:workspace_snapshot_imports, [:project_id],
             name: :workspace_snapshot_imports_project_idx
           )

    execute(
      """
      CREATE INDEX workspace_snapshot_imports_active_materialization_keys_idx
      ON workspace_snapshot_imports USING GIN (materialization_storage_keys)
      WHERE status IN ('queued', 'running', 'retrying') AND
            cardinality(materialization_storage_keys) > 0
      """,
      "DROP INDEX workspace_snapshot_imports_active_materialization_keys_idx"
    )

    create constraint(:workspace_snapshot_imports, :workspace_snapshot_imports_status_check,
             check: "status IN ('queued', 'running', 'retrying', 'completed', 'failed')"
           )

    create constraint(:workspace_snapshot_imports, :workspace_snapshot_imports_stage_check,
             check:
               "stage IN ('queued', 'verifying', 'materializing', 'retrying', 'completed', 'failed')"
           )

    create constraint(:workspace_snapshot_imports, :workspace_snapshot_imports_identity_check,
             check: """
             archive_storage_key <> '' AND octet_length(archive_storage_key) <= 520 AND
             archive_size_bytes > 0 AND
             archive_checksum ~ '^[0-9a-f]{64}$' AND
             manifest_checksum ~ '^[0-9a-f]{64}$' AND
             project_checksum ~ '^[0-9a-f]{64}$' AND
             reserved_bytes >= 0 AND
             progress_total_bytes > 0 AND
             cardinality(staging_storage_keys) <= 10001 AND
             (reserved_project_id IS NULL OR reserved_project_id > 0) AND
             cardinality(materialization_storage_keys) <= 20000
             """
           )

    create constraint(:workspace_snapshot_imports, :workspace_snapshot_imports_payload_check,
             check: """
             jsonb_typeof(failure_details) = 'object' AND
             (failure_code IS NULL OR (btrim(failure_code) <> '' AND octet_length(failure_code) <= 100))
             """
           )

    create constraint(:workspace_snapshot_imports, :workspace_snapshot_imports_lifecycle_check,
             check: """
             progress_bytes >= 0 AND progress_bytes <= progress_total_bytes AND
             attempt >= 0 AND max_attempts > 0 AND attempt <= max_attempts AND
             (
               (status = 'queued' AND stage = 'queued' AND attempt = 0 AND
                started_at IS NULL AND completed_at IS NULL AND project_id IS NULL AND
                reserved_project_id IS NULL AND cardinality(materialization_storage_keys) = 0 AND
                failure_code IS NULL AND failure_details = '{}'::jsonb) OR
               (status = 'running' AND stage IN ('verifying', 'materializing') AND
                attempt > 0 AND started_at IS NOT NULL AND completed_at IS NULL AND
                (stage <> 'materializing' OR reserved_project_id IS NOT NULL) AND
                project_id IS NULL AND failure_code IS NULL AND failure_details = '{}'::jsonb) OR
               (status = 'retrying' AND stage = 'retrying' AND
                attempt > 0 AND started_at IS NOT NULL AND completed_at IS NULL AND
                project_id IS NULL AND failure_code IS NOT NULL) OR
               (status = 'completed' AND stage = 'completed' AND
                attempt > 0 AND started_at IS NOT NULL AND completed_at IS NOT NULL AND
                reserved_bytes = 0 AND
                (project_id IS NULL OR project_id = reserved_project_id) AND
                progress_bytes = progress_total_bytes AND
                failure_code IS NULL AND failure_details = '{}'::jsonb) OR
               (status = 'failed' AND stage = 'failed' AND
                started_at IS NOT NULL AND completed_at IS NOT NULL AND
                project_id IS NULL AND reserved_bytes = 0 AND failure_code IS NOT NULL)
             )
             """
           )
  end
end
