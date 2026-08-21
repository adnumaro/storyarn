defmodule Storyarn.Repo.Migrations.AddSnapshotBackedProjectImportReplacement do
  use Ecto.Migration

  def up do
    alter table(:project_import_attempts) do
      add :import_mode, :string, null: false, default: "additive"
      add :replace_eligible, :boolean, null: false, default: false
      add :replacement_prepared_at, :utc_datetime
      add :snapshot_request_key, :uuid
      add :snapshot_reference_bound_at, :utc_datetime

      add :pre_import_snapshot_id,
          references(:project_snapshots, on_delete: :nilify_all)

      add :snapshot_lifecycle_generation, :integer
      add :snapshot_accounting_generation, :integer
      add :snapshot_capture_digest, :string
      add :snapshot_project_checksum, :string
      add :snapshot_archive_storage_key, :string, size: 520
      add :snapshot_archive_size_bytes, :bigint
      add :snapshot_archive_checksum, :string
      add :snapshot_manifest_storage_key, :string, size: 520
      add :snapshot_manifest_size_bytes, :bigint
      add :snapshot_manifest_checksum, :string
    end

    drop constraint(:project_import_attempts, :project_import_attempts_stage_check)
    drop constraint(:project_import_attempts, :project_import_attempts_state_check)

    create constraint(:project_import_attempts, :project_import_attempts_stage_check,
             check:
               "stage IN ('parsed', 'awaiting_snapshot', 'queued', 'materializing', 'retrying', 'completed', 'failed', 'expired')"
           )

    create constraint(:project_import_attempts, :project_import_attempts_import_mode_check,
             check: "import_mode IN ('additive', 'replace_project')"
           )

    create constraint(
             :project_import_attempts,
             :project_import_attempts_replace_eligibility_check,
             check: "replace_eligible OR import_mode = 'additive'"
           )

    create constraint(
             :project_import_attempts,
             :project_import_attempts_replacement_fence_check,
             check: """
             (import_mode = 'additive' AND replacement_prepared_at IS NULL)
             OR
             (import_mode = 'replace_project'
              AND (
                (status = 'completed' AND replacement_prepared_at IS NOT NULL)
                OR
                (status <> 'completed' AND replacement_prepared_at IS NULL)
              ))
             """
           )

    create constraint(:project_import_attempts, :project_import_attempts_snapshot_identity_check,
             check: """
             num_nonnulls(
               snapshot_lifecycle_generation,
               snapshot_accounting_generation,
               snapshot_capture_digest,
               snapshot_project_checksum,
               snapshot_archive_storage_key,
               snapshot_archive_size_bytes,
               snapshot_archive_checksum,
               snapshot_manifest_storage_key,
               snapshot_manifest_size_bytes,
               snapshot_manifest_checksum
             ) = 0
             OR
             (snapshot_lifecycle_generation IS NOT NULL
              AND snapshot_accounting_generation IS NOT NULL
              AND snapshot_capture_digest IS NOT NULL
              AND snapshot_project_checksum IS NOT NULL
              AND snapshot_archive_storage_key IS NOT NULL
              AND snapshot_archive_size_bytes IS NOT NULL
              AND snapshot_archive_checksum IS NOT NULL
              AND snapshot_manifest_storage_key IS NOT NULL
              AND snapshot_manifest_size_bytes IS NOT NULL
              AND snapshot_manifest_checksum IS NOT NULL
              AND snapshot_lifecycle_generation > 0
              AND snapshot_accounting_generation > 0
              AND snapshot_capture_digest ~ '^[0-9a-f]{64}$'
              AND snapshot_project_checksum ~ '^[0-9a-f]{64}$'
              AND length(snapshot_archive_storage_key) > 0
              AND snapshot_archive_size_bytes > 0
              AND snapshot_archive_checksum ~ '^[0-9a-f]{64}$'
              AND length(snapshot_manifest_storage_key) > 0
              AND snapshot_manifest_size_bytes > 0
              AND snapshot_manifest_checksum ~ '^[0-9a-f]{64}$')
             """
           )

    create constraint(:project_import_attempts, :project_import_attempts_replace_snapshot_check,
             check: """
             (import_mode = 'additive'
              AND snapshot_request_key IS NULL
              AND pre_import_snapshot_id IS NULL
              AND snapshot_reference_bound_at IS NULL
              AND snapshot_lifecycle_generation IS NULL)
             OR
             (import_mode = 'replace_project'
              AND snapshot_request_key IS NOT NULL)
             """
           )

    create constraint(
             :project_import_attempts,
             :project_import_attempts_snapshot_reference_state_check,
             check: """
             (import_mode = 'additive' AND snapshot_reference_bound_at IS NULL)
             OR
             (import_mode = 'replace_project' AND (
               (status = 'ready'
                AND stage = 'parsed'
                AND snapshot_reference_bound_at IS NULL
                AND pre_import_snapshot_id IS NULL
                AND snapshot_lifecycle_generation IS NULL)
               OR
               (status = 'queued'
                AND stage = 'awaiting_snapshot'
                AND snapshot_lifecycle_generation IS NULL
                AND (
                  (snapshot_reference_bound_at IS NULL AND pre_import_snapshot_id IS NULL)
                  OR snapshot_reference_bound_at IS NOT NULL
                ))
               OR
               (status IN ('queued', 'running', 'retrying', 'completed')
                AND stage <> 'awaiting_snapshot'
                AND snapshot_reference_bound_at IS NOT NULL
                AND snapshot_lifecycle_generation IS NOT NULL)
               OR status IN ('failed', 'expired')
             ))
             """
           )

    create constraint(:project_import_attempts, :project_import_attempts_state_check,
             check: """
             (status = 'ready' AND stage = 'parsed' AND started_at IS NULL AND completed_at IS NULL)
             OR (status = 'queued' AND stage IN ('awaiting_snapshot', 'queued') AND completed_at IS NULL)
             OR (status = 'running' AND stage = 'materializing' AND started_at IS NOT NULL AND completed_at IS NULL)
             OR (status = 'retrying' AND stage = 'retrying' AND started_at IS NOT NULL AND completed_at IS NULL)
             OR (status = 'completed' AND stage = 'completed' AND started_at IS NOT NULL AND completed_at IS NOT NULL)
             OR (status = 'failed' AND stage = 'failed' AND completed_at IS NOT NULL)
             OR (status = 'expired' AND stage = 'expired' AND completed_at IS NOT NULL)
             """
           )

    create index(:project_import_attempts, [:pre_import_snapshot_id],
             name: :project_import_attempts_pre_import_snapshot_idx
           )
  end

  def down do
    execute "LOCK TABLE project_import_attempts IN ACCESS EXCLUSIVE MODE"

    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM project_import_attempts
        WHERE import_mode = 'replace_project'
          AND status IN ('ready', 'queued', 'running', 'retrying')
      ) THEN
        RAISE EXCEPTION
          'cannot roll back snapshot-backed project replacement while replacement imports are active';
      END IF;
    END
    $$
    """

    drop_if_exists index(:project_import_attempts, [:pre_import_snapshot_id],
                     name: :project_import_attempts_pre_import_snapshot_idx
                   )

    drop constraint(:project_import_attempts, :project_import_attempts_state_check)

    drop constraint(
           :project_import_attempts,
           :project_import_attempts_snapshot_reference_state_check
         )

    drop constraint(:project_import_attempts, :project_import_attempts_replace_snapshot_check)
    drop constraint(:project_import_attempts, :project_import_attempts_snapshot_identity_check)
    drop constraint(:project_import_attempts, :project_import_attempts_replacement_fence_check)
    drop constraint(:project_import_attempts, :project_import_attempts_replace_eligibility_check)
    drop constraint(:project_import_attempts, :project_import_attempts_import_mode_check)
    drop constraint(:project_import_attempts, :project_import_attempts_stage_check)

    execute """
    UPDATE project_import_attempts
    SET stage = 'queued'
    WHERE status = 'queued' AND stage = 'awaiting_snapshot'
    """

    create constraint(:project_import_attempts, :project_import_attempts_stage_check,
             check:
               "stage IN ('parsed', 'queued', 'materializing', 'retrying', 'completed', 'failed', 'expired')"
           )

    create constraint(:project_import_attempts, :project_import_attempts_state_check,
             check: """
             (status = 'ready' AND stage = 'parsed' AND started_at IS NULL AND completed_at IS NULL)
             OR (status = 'queued' AND stage = 'queued' AND completed_at IS NULL)
             OR (status = 'running' AND stage = 'materializing' AND started_at IS NOT NULL AND completed_at IS NULL)
             OR (status = 'retrying' AND stage = 'retrying' AND started_at IS NOT NULL AND completed_at IS NULL)
             OR (status = 'completed' AND stage = 'completed' AND started_at IS NOT NULL AND completed_at IS NOT NULL)
             OR (status = 'failed' AND stage = 'failed' AND completed_at IS NOT NULL)
             OR (status = 'expired' AND stage = 'expired' AND completed_at IS NOT NULL)
             """
           )

    alter table(:project_import_attempts) do
      remove :snapshot_manifest_checksum
      remove :snapshot_manifest_size_bytes
      remove :snapshot_manifest_storage_key
      remove :snapshot_archive_checksum
      remove :snapshot_archive_size_bytes
      remove :snapshot_archive_storage_key
      remove :snapshot_project_checksum
      remove :snapshot_capture_digest
      remove :snapshot_accounting_generation
      remove :snapshot_lifecycle_generation
      remove :pre_import_snapshot_id
      remove :snapshot_reference_bound_at
      remove :snapshot_request_key
      remove :replacement_prepared_at
      remove :replace_eligible
      remove :import_mode
    end
  end
end
