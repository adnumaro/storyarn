defmodule Storyarn.Repo.Migrations.CreateAsyncSnapshotBuilds do
  use Ecto.Migration

  def change do
    # Reset policy: project snapshots have not been enabled since the canonical
    # object/accounting reset. Do not carry partially-populated lifecycle rows
    # or reservations into the asynchronous build contract.
    execute(
      """
      DELETE FROM snapshot_object_publication_claims
      WHERE storage_reservation_id_snapshot IN (
        SELECT id
        FROM workspace_storage_reservations
        WHERE kind IN ('snapshot_build', 'linked_to_full_conversion')
      )
      """,
      "SELECT 1"
    )

    execute(
      """
      DELETE FROM workspace_storage_reservations
      WHERE kind IN ('snapshot_build', 'linked_to_full_conversion')
      """,
      "SELECT 1"
    )

    execute("DELETE FROM project_snapshots", "SELECT 1")

    execute(
      "ALTER TABLE project_snapshots ALTER COLUMN project_size_bytes TYPE bigint USING project_size_bytes::bigint",
      "ALTER TABLE project_snapshots ALTER COLUMN project_size_bytes TYPE integer USING project_size_bytes::integer"
    )

    alter table(:project_snapshots) do
      add :idempotency_key, :string, null: false
      add :capture_boundary, :uuid, null: false
      add :capture_digest, :string, size: 64, null: false
      add :captured_at, :utc_datetime, null: false
      add :progress_phase, :string, null: false
      add :progress_bytes, :bigint, null: false
      add :progress_total_bytes, :bigint, null: false
      add :failure_code, :string
      add :failure_message, :string, size: 500

      add :storage_reservation_id,
          references(:workspace_storage_reservations, on_delete: :restrict)

      add :build_job_id, :bigint
      add :build_attempt, :integer, null: false, default: 0
      add :publication_claim_token, :uuid
      add :building_started_at, :utc_datetime
      add :verifying_started_at, :utc_datetime
      add :ready_at, :utc_datetime
      add :failed_at, :utc_datetime
      add :cancel_requested_at, :utc_datetime
      add :cancelled_at, :utc_datetime
      add :state_updated_at, :utc_datetime, null: false
    end

    create unique_index(:project_snapshots, [:project_id, :idempotency_key],
             name: :project_snapshots_project_id_idempotency_idx
           )

    create unique_index(:project_snapshots, [:capture_boundary])
    create index(:project_snapshots, [:storage_reservation_id])
    create index(:project_snapshots, [:lifecycle_state, :state_updated_at])

    create constraint(:project_snapshots, :project_snapshots_capture_digest_format,
             check: "capture_digest ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:project_snapshots, :project_snapshots_build_progress,
             check: """
             progress_phase IN
               ('pending', 'copying', 'verifying', 'finalizing', 'retrying',
                'complete', 'failed', 'cancelled') AND
             progress_bytes >= 0 AND progress_total_bytes > 0 AND
             progress_bytes <= progress_total_bytes AND build_attempt >= 0
             """
           )

    create constraint(:project_snapshots, :project_snapshots_build_failure,
             check: """
             (lifecycle_state = 'failed' AND failed_at IS NOT NULL AND
              failure_code IS NOT NULL AND btrim(failure_code) <> '' AND
              failure_message IS NOT NULL AND btrim(failure_message) <> '') OR
             (lifecycle_state <> 'failed' AND failed_at IS NULL AND
              failure_code IS NULL AND failure_message IS NULL)
             """
           )

    create constraint(:project_snapshots, :project_snapshots_build_timestamps,
             check: """
             (lifecycle_state = 'pending' AND ready_at IS NULL AND cancelled_at IS NULL) OR
             (lifecycle_state = 'building' AND building_started_at IS NOT NULL AND
              ready_at IS NULL AND cancelled_at IS NULL) OR
             (lifecycle_state = 'verifying' AND building_started_at IS NOT NULL AND
              verifying_started_at IS NOT NULL AND ready_at IS NULL AND cancelled_at IS NULL) OR
             (lifecycle_state = 'ready' AND building_started_at IS NOT NULL AND
              verifying_started_at IS NOT NULL AND ready_at IS NOT NULL AND
              cancelled_at IS NULL) OR
             (lifecycle_state = 'failed' AND ready_at IS NULL AND cancelled_at IS NULL) OR
             (lifecycle_state = 'cancelled' AND cancelled_at IS NOT NULL AND ready_at IS NULL) OR
             (lifecycle_state = 'deleting' AND ready_at IS NOT NULL)
             """
           )

    create table(:project_snapshot_captures, primary_key: false) do
      add :project_snapshot_id,
          references(:project_snapshots, on_delete: :delete_all),
          primary_key: true

      add :capture_boundary, :uuid, null: false
      add :capture_digest, :string, size: 64, null: false
      add :project_json, :binary, null: false
      add :manifest_json, :binary, null: false
      add :source_keys, :map, null: false
      add :project_size_bytes, :bigint, null: false
      add :manifest_size_bytes, :bigint, null: false
      add :asset_blob_size_bytes, :bigint, null: false
      add :total_size_bytes, :bigint, null: false
      add :object_count, :integer, null: false
      add :asset_count, :integer, null: false
      add :blob_count, :integer, null: false
      add :captured_at, :utc_datetime, null: false
    end

    create unique_index(:project_snapshot_captures, [:capture_boundary])

    create constraint(:project_snapshot_captures, :project_snapshot_captures_digest_format,
             check: "capture_digest ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:project_snapshot_captures, :project_snapshot_captures_inventory,
             check: """
             project_size_bytes > 0 AND manifest_size_bytes > 0 AND
             asset_blob_size_bytes >= 0 AND
             total_size_bytes = project_size_bytes + manifest_size_bytes + asset_blob_size_bytes AND
             object_count = blob_count + 2 AND asset_count >= blob_count AND blob_count >= 0
             """
           )

    execute(
      """
      CREATE FUNCTION storyarn_guard_project_snapshot_capture_update()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'project snapshot captures are immutable'
          USING ERRCODE = 'integrity_constraint_violation';
      END;
      $$
      """,
      "DROP FUNCTION IF EXISTS storyarn_guard_project_snapshot_capture_update() CASCADE"
    )

    execute(
      """
      CREATE TRIGGER project_snapshot_captures_immutable
      BEFORE UPDATE ON project_snapshot_captures
      FOR EACH ROW
      EXECUTE FUNCTION storyarn_guard_project_snapshot_capture_update()
      """,
      "DROP TRIGGER IF EXISTS project_snapshot_captures_immutable ON project_snapshot_captures"
    )

    execute(
      """
      CREATE FUNCTION storyarn_guard_project_snapshot_capture_identity()
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
      """,
      "DROP FUNCTION IF EXISTS storyarn_guard_project_snapshot_capture_identity() CASCADE"
    )

    execute(
      """
      CREATE TRIGGER project_snapshots_capture_identity_immutable
      BEFORE UPDATE ON project_snapshots
      FOR EACH ROW
      EXECUTE FUNCTION storyarn_guard_project_snapshot_capture_identity()
      """,
      "DROP TRIGGER IF EXISTS project_snapshots_capture_identity_immutable ON project_snapshots"
    )
  end
end
