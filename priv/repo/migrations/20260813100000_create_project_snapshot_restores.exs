defmodule Storyarn.Repo.Migrations.CreateProjectSnapshotRestores do
  use Ecto.Migration

  def change do
    create table(:project_snapshot_restores) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      add :project_snapshot_id,
          references(:project_snapshots, on_delete: :nilify_all)

      add :requested_by_id, references(:users, on_delete: :nilify_all)
      add :oban_job_id, references(:oban_jobs, type: :bigint, on_delete: :nilify_all)

      add :idempotency_key, :uuid, null: false
      add :status, :string, null: false, default: "queued"
      add :phase, :string, null: false, default: "queued"
      add :generation, :integer, null: false, default: 1
      add :attempt, :integer, null: false, default: 0

      add :storage_reservation_id,
          references(:workspace_storage_reservations, on_delete: :restrict)

      add :storage_reservation_generation, :integer
      add :storage_reservation_lease_token, :uuid

      add :snapshot_lifecycle_generation, :integer, null: false
      add :snapshot_accounting_generation, :bigint, null: false
      add :archive_storage_key, :string, size: 520, null: false
      add :archive_size_bytes, :bigint, null: false
      add :archive_checksum, :string, size: 64, null: false
      add :manifest_storage_key, :string, size: 520, null: false
      add :manifest_size_bytes, :bigint, null: false
      add :manifest_checksum, :string, size: 64, null: false

      add :failure_code, :string, size: 100
      add :failure_message, :string, size: 500
      add :failure_details, :map, null: false, default: %{}
      add :result, :map, null: false, default: %{}
      add :result_digest, :string, size: 64

      add :requested_at, :utc_datetime, null: false
      add :claimed_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :failed_at, :utc_datetime
      add :state_updated_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:project_snapshot_restores, [:workspace_id, :idempotency_key],
             name: :project_snapshot_restores_workspace_idempotency_idx
           )

    create unique_index(:project_snapshot_restores, [:project_id],
             where: "status IN ('queued', 'running', 'retrying')",
             name: :project_snapshot_restores_active_project_idx
           )

    create unique_index(:project_snapshot_restores, [:oban_job_id],
             where: "oban_job_id IS NOT NULL",
             name: :project_snapshot_restores_oban_job_idx
           )

    create index(:project_snapshot_restores, [:workspace_id, :status, :inserted_at],
             name: :project_snapshot_restores_workspace_status_idx
           )

    create index(:project_snapshot_restores, [:project_id, :status, :inserted_at],
             name: :project_snapshot_restores_project_status_idx
           )

    create index(:project_snapshot_restores, [:project_snapshot_id],
             name: :project_snapshot_restores_snapshot_idx
           )

    create index(:project_snapshot_restores, [:requested_by_id],
             name: :project_snapshot_restores_requested_by_idx
           )

    create index(:project_snapshot_restores, [:storage_reservation_id],
             name: :project_snapshot_restores_reservation_idx
           )

    create constraint(:project_snapshot_restores, :project_snapshot_restores_status_check,
             check: "status IN ('queued', 'running', 'retrying', 'completed', 'failed')"
           )

    create constraint(:project_snapshot_restores, :project_snapshot_restores_phase_check,
             check: """
             phase IN (
               'queued', 'preflight', 'staging', 'materializing', 'verifying',
               'retrying', 'completed', 'failed'
             )
             """
           )

    create constraint(
             :project_snapshot_restores,
             :project_snapshot_restores_target_identity_check,
             check: """
             snapshot_lifecycle_generation > 0 AND
             snapshot_accounting_generation > 0 AND
             archive_storage_key <> '' AND octet_length(archive_storage_key) <= 520 AND
             archive_size_bytes > 0 AND archive_checksum ~ '^[0-9a-f]{64}$' AND
             manifest_storage_key <> '' AND octet_length(manifest_storage_key) <= 520 AND
             manifest_size_bytes > 0 AND manifest_checksum ~ '^[0-9a-f]{64}$' AND
             archive_storage_key <> manifest_storage_key
             """
           )

    create constraint(
             :project_snapshot_restores,
             :project_snapshot_restores_reservation_identity_check,
             check: """
             (
               storage_reservation_id IS NULL AND
               storage_reservation_generation IS NULL AND
               storage_reservation_lease_token IS NULL
             ) OR (
               storage_reservation_id IS NOT NULL AND
               storage_reservation_generation IS NOT NULL AND
               storage_reservation_generation > 0 AND
               storage_reservation_lease_token IS NOT NULL
             )
             """
           )

    create constraint(
             :project_snapshot_restores,
             :project_snapshot_restores_live_references_check,
             check: """
             status IN ('completed', 'failed') OR
             (project_snapshot_id IS NOT NULL AND requested_by_id IS NOT NULL)
             """
           )

    create constraint(
             :project_snapshot_restores,
             :project_snapshot_restores_payload_shape_check,
             check: """
             jsonb_typeof(failure_details) = 'object' AND
             jsonb_typeof(result) = 'object' AND
             (failure_code IS NULL OR
              (btrim(failure_code) <> '' AND octet_length(failure_code) <= 100)) AND
             (failure_message IS NULL OR
              (btrim(failure_message) <> '' AND octet_length(failure_message) <= 500)) AND
             (result_digest IS NULL OR result_digest ~ '^[0-9a-f]{64}$')
             """
           )

    create constraint(
             :project_snapshot_restores,
             :project_snapshot_restores_lifecycle_shape_check,
             check: """
             generation > 0 AND attempt >= 0 AND
             state_updated_at >= requested_at AND
             (claimed_at IS NULL OR claimed_at >= requested_at) AND
             (completed_at IS NULL OR
              (claimed_at IS NOT NULL AND completed_at >= claimed_at)) AND
             (failed_at IS NULL OR
              (claimed_at IS NOT NULL AND failed_at >= claimed_at)) AND
             (
               (status = 'queued' AND phase = 'queued' AND attempt = 0 AND
                claimed_at IS NULL AND completed_at IS NULL AND failed_at IS NULL AND
                failure_code IS NULL AND failure_message IS NULL AND
                failure_details = '{}'::jsonb AND result = '{}'::jsonb AND
                result_digest IS NULL) OR
               (status = 'running' AND
                phase IN ('preflight', 'staging', 'materializing', 'verifying') AND
                attempt > 0 AND claimed_at IS NOT NULL AND
                completed_at IS NULL AND failed_at IS NULL AND
                failure_code IS NULL AND failure_message IS NULL AND
                failure_details = '{}'::jsonb AND result = '{}'::jsonb AND
                result_digest IS NULL) OR
               (status = 'retrying' AND phase = 'retrying' AND
                attempt > 0 AND claimed_at IS NOT NULL AND
                completed_at IS NULL AND failed_at IS NULL AND
                failure_code IS NOT NULL AND result = '{}'::jsonb AND
                result_digest IS NULL) OR
               (status = 'completed' AND phase = 'completed' AND
                attempt > 0 AND claimed_at IS NOT NULL AND completed_at IS NOT NULL AND
                failed_at IS NULL AND failure_code IS NULL AND failure_message IS NULL AND
                failure_details = '{}'::jsonb AND result_digest IS NOT NULL) OR
               (status = 'failed' AND phase = 'failed' AND
                attempt > 0 AND claimed_at IS NOT NULL AND completed_at IS NULL AND
                failed_at IS NOT NULL AND failure_code IS NOT NULL AND
                result = '{}'::jsonb AND result_digest IS NULL)
             )
             """
           )

    execute(
      """
      CREATE FUNCTION storyarn_guard_project_snapshot_restore_identity()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NEW.workspace_id IS DISTINCT FROM OLD.workspace_id OR
           NEW.project_id IS DISTINCT FROM OLD.project_id OR
           NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key OR
           NEW.snapshot_lifecycle_generation IS DISTINCT FROM OLD.snapshot_lifecycle_generation OR
           NEW.snapshot_accounting_generation IS DISTINCT FROM OLD.snapshot_accounting_generation OR
           NEW.archive_storage_key IS DISTINCT FROM OLD.archive_storage_key OR
           NEW.archive_size_bytes IS DISTINCT FROM OLD.archive_size_bytes OR
           NEW.archive_checksum IS DISTINCT FROM OLD.archive_checksum OR
           NEW.manifest_storage_key IS DISTINCT FROM OLD.manifest_storage_key OR
           NEW.manifest_size_bytes IS DISTINCT FROM OLD.manifest_size_bytes OR
           NEW.manifest_checksum IS DISTINCT FROM OLD.manifest_checksum OR
           NEW.requested_at IS DISTINCT FROM OLD.requested_at THEN
          RAISE EXCEPTION 'project snapshot restore identity is immutable'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;

        IF NEW.project_snapshot_id IS DISTINCT FROM OLD.project_snapshot_id AND
           NOT (
             OLD.status IN ('completed', 'failed') AND
             OLD.project_snapshot_id IS NOT NULL AND
             NEW.project_snapshot_id IS NULL
           ) THEN
          RAISE EXCEPTION 'active project snapshot restore target is immutable'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;

        IF NEW.requested_by_id IS DISTINCT FROM OLD.requested_by_id AND
           NOT (
             OLD.status IN ('completed', 'failed') AND
             OLD.requested_by_id IS NOT NULL AND
             NEW.requested_by_id IS NULL
           ) THEN
          RAISE EXCEPTION 'active project snapshot restore requester is immutable'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;

        RETURN NEW;
      END;
      $$
      """,
      "DROP FUNCTION IF EXISTS storyarn_guard_project_snapshot_restore_identity() CASCADE"
    )

    execute(
      """
      CREATE TRIGGER project_snapshot_restores_identity_immutable
      BEFORE UPDATE ON project_snapshot_restores
      FOR EACH ROW
      EXECUTE FUNCTION storyarn_guard_project_snapshot_restore_identity()
      """,
      "DROP TRIGGER IF EXISTS project_snapshot_restores_identity_immutable ON project_snapshot_restores"
    )
  end
end
