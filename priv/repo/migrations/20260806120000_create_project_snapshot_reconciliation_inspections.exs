defmodule Storyarn.Repo.Migrations.CreateProjectSnapshotReconciliationInspections do
  use Ecto.Migration

  def change do
    create table(:project_snapshot_reconciliation_runs) do
      add :contract_version, :integer, null: false, default: 1
      add :provider_namespace_fingerprint, :string, size: 64, null: false
      add :mode, :string, null: false, default: "dry_run"
      add :status, :string, null: false, default: "pending"
      add :phase, :string, null: false, default: "ready_snapshots"
      add :snapshot_high_watermark, :bigint, null: false, default: 0
      add :snapshot_after_id, :bigint, null: false, default: 0
      add :reservation_high_watermark, :bigint, null: false, default: 0
      add :reservation_after_id, :bigint, null: false, default: 0
      add :claim_sequence_high_watermark, :bigint, null: false, default: 0
      add :claim_after_sequence, :bigint, null: false, default: 0
      add :cleanup_intent_high_watermark, :bigint, null: false, default: 0
      add :cleanup_intent_after_id, :bigint, null: false, default: 0
      add :active_snapshot_id, :bigint
      add :active_snapshot_generation, :bigint
      add :active_snapshot_accounting_generation, :bigint
      add :active_object_index, :integer, null: false, default: 0
      add :active_inventory_cursor, :text
      add :active_inventory_digest, :string, size: 64
      add :active_inventory_last_key, :text
      add :active_inventory_object_count, :bigint, null: false, default: 0
      add :active_inventory_bytes, :bigint, null: false, default: 0
      add :provider_cursor, :text
      add :provider_last_key, :text
      add :provider_scan_completed, :boolean, null: false, default: false
      add :cursor_generation, :bigint, null: false, default: 1
      add :max_objects_per_step, :integer, null: false
      add :max_bytes_per_step, :bigint, null: false
      add :max_findings, :integer, null: false
      add :provider_page_size, :integer, null: false
      add :max_provider_objects, :bigint, null: false
      add :max_provider_bytes, :bigint, null: false
      add :inspected_snapshot_count, :bigint, null: false, default: 0
      add :inspected_object_count, :bigint, null: false, default: 0
      add :inspected_bytes, :bigint, null: false, default: 0
      add :provider_object_count, :bigint, null: false, default: 0
      add :provider_bytes, :bigint, null: false, default: 0
      add :finding_count, :bigint, null: false, default: 0
      add :multipart_inventory_state, :string, null: false, default: "unsupported"
      add :physical_inventory_complete, :boolean, null: false, default: false
      add :last_error_code, :string
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :project_snapshot_reconciliation_runs,
             [:provider_namespace_fingerprint],
             where: "status IN ('pending', 'running')",
             name: :project_snapshot_reconciliation_runs_one_active_namespace
           )

    create index(:project_snapshot_reconciliation_runs, [:status, :inserted_at, :id])

    create constraint(
             :project_snapshot_reconciliation_runs,
             :project_snapshot_reconciliation_runs_state,
             check: """
             provider_namespace_fingerprint ~ '^[0-9a-f]{64}$' AND
             contract_version = 1 AND
             mode = 'dry_run' AND
             status IN ('pending', 'running', 'completed', 'failed') AND
             phase IN ('ready_snapshots', 'stale_reservations', 'publication_claims', 'cleanup_intents',
                       'provider_objects', 'completed') AND
             snapshot_high_watermark >= 0 AND snapshot_after_id >= 0 AND
             snapshot_after_id <= snapshot_high_watermark AND
             reservation_high_watermark >= 0 AND reservation_after_id >= 0 AND
             reservation_after_id <= reservation_high_watermark AND
             claim_sequence_high_watermark >= 0 AND claim_after_sequence >= 0 AND
             claim_after_sequence <= claim_sequence_high_watermark AND
             cleanup_intent_high_watermark >= 0 AND cleanup_intent_after_id >= 0 AND
             cleanup_intent_after_id <= cleanup_intent_high_watermark AND
             active_object_index >= 0 AND active_object_index <= 10001 AND cursor_generation > 0 AND
             max_objects_per_step > 0 AND max_objects_per_step <= 1000 AND
             max_bytes_per_step >= 134217728 AND max_bytes_per_step <= 1073741824 AND
             max_findings > 0 AND max_findings <= 10000 AND
             provider_page_size > 0 AND provider_page_size <= 1000 AND
             max_provider_objects > 0 AND max_provider_objects <= 10000000 AND
             max_provider_bytes > 0 AND max_provider_bytes <= 1125899906842624 AND
             inspected_snapshot_count >= 0 AND inspected_object_count >= 0 AND
             inspected_bytes >= 0 AND provider_object_count >= 0 AND
             provider_bytes >= 0 AND finding_count >= 0 AND
             inspected_snapshot_count <= snapshot_high_watermark AND
             provider_object_count <= max_provider_objects AND
             provider_bytes <= max_provider_bytes AND finding_count <= max_findings AND
             multipart_inventory_state = 'unsupported' AND physical_inventory_complete = false AND
             active_inventory_object_count >= 0 AND active_inventory_object_count <= 10002 AND
             active_inventory_bytes >= 0 AND
             ((active_snapshot_id IS NULL AND active_snapshot_generation IS NULL AND
                active_snapshot_accounting_generation IS NULL AND active_object_index = 0 AND
                active_inventory_cursor IS NULL AND active_inventory_digest IS NULL AND
                active_inventory_last_key IS NULL AND active_inventory_object_count = 0 AND
                active_inventory_bytes = 0) OR
              (active_snapshot_id IS NOT NULL AND active_snapshot_id > 0 AND
               active_snapshot_generation IS NOT NULL AND active_snapshot_generation > 0 AND
               active_snapshot_accounting_generation IS NOT NULL AND
               active_snapshot_accounting_generation > 0 AND active_object_index > 0 AND
               active_snapshot_id > snapshot_after_id AND
               active_snapshot_id <= snapshot_high_watermark AND
               ((active_inventory_digest IS NULL AND active_inventory_cursor IS NULL AND
                 active_inventory_last_key IS NULL AND active_inventory_object_count = 0 AND
                 active_inventory_bytes = 0) OR
                (active_inventory_digest IS NOT NULL AND
                 active_inventory_digest ~ '^[0-9a-f]{64}$' AND
                 ((active_inventory_cursor IS NULL AND active_inventory_last_key IS NULL AND
                   active_inventory_object_count = 0 AND active_inventory_bytes = 0) OR
                  (active_inventory_cursor IS NOT NULL AND active_inventory_last_key IS NOT NULL AND
                   active_inventory_object_count > 0)))))) AND
             (phase <> 'ready_snapshots' OR reservation_after_id = 0) AND
             (phase NOT IN ('ready_snapshots', 'stale_reservations') OR
              claim_after_sequence = 0) AND
             (phase NOT IN ('ready_snapshots', 'stale_reservations', 'publication_claims') OR
              cleanup_intent_after_id = 0) AND
             ((phase = 'ready_snapshots') OR
              (snapshot_after_id = snapshot_high_watermark AND active_snapshot_id IS NULL)) AND
             ((phase IN ('ready_snapshots', 'stale_reservations')) OR
              reservation_after_id = reservation_high_watermark) AND
             ((phase IN ('ready_snapshots', 'stale_reservations', 'publication_claims')) OR
              claim_after_sequence = claim_sequence_high_watermark) AND
             ((phase IN ('ready_snapshots', 'stale_reservations', 'publication_claims', 'cleanup_intents')) OR
              cleanup_intent_after_id = cleanup_intent_high_watermark) AND
             ((phase NOT IN ('provider_objects', 'completed') AND
               provider_cursor IS NULL AND provider_last_key IS NULL AND
               provider_object_count = 0 AND provider_bytes = 0 AND NOT provider_scan_completed) OR
              (phase = 'provider_objects' AND NOT provider_scan_completed AND
               ((provider_cursor IS NULL AND provider_last_key IS NULL AND
                 provider_object_count = 0 AND provider_bytes = 0) OR
                (provider_cursor IS NOT NULL AND provider_last_key IS NOT NULL AND
                 provider_object_count > 0))) OR
              (phase = 'completed' AND provider_scan_completed AND provider_cursor IS NULL AND
               ((provider_object_count = 0 AND provider_last_key IS NULL AND provider_bytes = 0) OR
                (provider_object_count > 0 AND provider_last_key IS NOT NULL)))) AND
             provider_scan_completed = (status = 'completed' AND phase = 'completed') AND
             ((status = 'pending' AND started_at IS NULL AND finished_at IS NULL AND
               last_error_code IS NULL) OR
              (status = 'running' AND started_at IS NOT NULL AND finished_at IS NULL AND
               last_error_code IS NULL) OR
              (status = 'completed' AND started_at IS NOT NULL AND finished_at IS NOT NULL AND
               finished_at >= started_at AND last_error_code IS NULL) OR
              (status = 'failed' AND started_at IS NOT NULL AND finished_at IS NOT NULL AND
               finished_at >= started_at AND last_error_code IS NOT NULL AND
               last_error_code <> '')) AND
             ((status = 'completed' AND phase = 'completed') OR
              (status <> 'completed' AND phase <> 'completed')) AND
             (status <> 'completed' OR
              (active_snapshot_id IS NULL AND provider_cursor IS NULL)) AND
             (provider_cursor IS NULL OR octet_length(provider_cursor) <= 4096) AND
             (active_inventory_cursor IS NULL OR octet_length(active_inventory_cursor) <= 4096) AND
             (provider_last_key IS NULL OR octet_length(provider_last_key) <= 2048) AND
             (active_inventory_last_key IS NULL OR octet_length(active_inventory_last_key) <= 2048)
             """
           )

    execute(
      """
      CREATE FUNCTION storyarn_guard_project_snapshot_reconciliation_run()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
      IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'pending' OR
           NEW.phase <> 'ready_snapshots' OR
           NEW.cursor_generation <> 1 OR
           NEW.snapshot_after_id <> 0 OR
           NEW.reservation_after_id <> 0 OR
           NEW.claim_after_sequence <> 0 OR
           NEW.cleanup_intent_after_id <> 0 OR
           NEW.active_snapshot_id IS NOT NULL OR
           NEW.active_snapshot_generation IS NOT NULL OR
           NEW.active_snapshot_accounting_generation IS NOT NULL OR
           NEW.active_object_index <> 0 OR
           NEW.active_inventory_cursor IS NOT NULL OR
           NEW.active_inventory_digest IS NOT NULL OR
           NEW.active_inventory_last_key IS NOT NULL OR
           NEW.active_inventory_object_count <> 0 OR
           NEW.active_inventory_bytes <> 0 OR
           NEW.provider_cursor IS NOT NULL OR
           NEW.provider_last_key IS NOT NULL OR
           NEW.provider_scan_completed OR
           NEW.inspected_snapshot_count <> 0 OR
           NEW.inspected_object_count <> 0 OR
           NEW.inspected_bytes <> 0 OR
           NEW.provider_object_count <> 0 OR
           NEW.provider_bytes <> 0 OR
           NEW.finding_count <> 0 OR
           NEW.last_error_code IS NOT NULL OR
           NEW.started_at IS NOT NULL OR
           NEW.finished_at IS NOT NULL OR
           NEW.updated_at IS DISTINCT FROM NEW.inserted_at THEN
          RAISE EXCEPTION 'snapshot reconciliation runs must start pending and pristine'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;

        RETURN NEW;
      END IF;

      IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'snapshot reconciliation runs cannot be deleted'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      IF NEW.contract_version IS DISTINCT FROM OLD.contract_version OR
         NEW.provider_namespace_fingerprint IS DISTINCT FROM OLD.provider_namespace_fingerprint OR
         NEW.mode IS DISTINCT FROM OLD.mode OR
         NEW.snapshot_high_watermark IS DISTINCT FROM OLD.snapshot_high_watermark OR
         NEW.reservation_high_watermark IS DISTINCT FROM OLD.reservation_high_watermark OR
         NEW.claim_sequence_high_watermark IS DISTINCT FROM OLD.claim_sequence_high_watermark OR
         NEW.cleanup_intent_high_watermark IS DISTINCT FROM OLD.cleanup_intent_high_watermark OR
         NEW.max_objects_per_step IS DISTINCT FROM OLD.max_objects_per_step OR
         NEW.max_bytes_per_step IS DISTINCT FROM OLD.max_bytes_per_step OR
         NEW.max_findings IS DISTINCT FROM OLD.max_findings OR
         NEW.provider_page_size IS DISTINCT FROM OLD.provider_page_size OR
         NEW.max_provider_objects IS DISTINCT FROM OLD.max_provider_objects OR
         NEW.max_provider_bytes IS DISTINCT FROM OLD.max_provider_bytes OR
         NEW.inserted_at IS DISTINCT FROM OLD.inserted_at THEN
        RAISE EXCEPTION 'snapshot reconciliation run identity is immutable'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      IF NEW.cursor_generation <> OLD.cursor_generation + 1 OR
         (NEW.snapshot_after_id IS DISTINCT FROM OLD.snapshot_after_id AND
          OLD.phase <> 'ready_snapshots') OR
         (NEW.reservation_after_id IS DISTINCT FROM OLD.reservation_after_id AND
          OLD.phase <> 'stale_reservations') OR
         (NEW.claim_after_sequence IS DISTINCT FROM OLD.claim_after_sequence AND
          OLD.phase <> 'publication_claims') OR
         (NEW.cleanup_intent_after_id IS DISTINCT FROM OLD.cleanup_intent_after_id AND
          OLD.phase <> 'cleanup_intents') OR
         ((NEW.provider_cursor IS DISTINCT FROM OLD.provider_cursor OR
           NEW.provider_last_key IS DISTINCT FROM OLD.provider_last_key OR
           NEW.provider_scan_completed IS DISTINCT FROM OLD.provider_scan_completed OR
           NEW.provider_object_count IS DISTINCT FROM OLD.provider_object_count OR
           NEW.provider_bytes IS DISTINCT FROM OLD.provider_bytes) AND
          OLD.phase <> 'provider_objects') OR
         ((NEW.active_snapshot_id IS DISTINCT FROM OLD.active_snapshot_id OR
           NEW.active_snapshot_generation IS DISTINCT FROM OLD.active_snapshot_generation OR
           NEW.active_snapshot_accounting_generation IS DISTINCT FROM
             OLD.active_snapshot_accounting_generation OR
           NEW.active_object_index IS DISTINCT FROM OLD.active_object_index OR
           NEW.active_inventory_cursor IS DISTINCT FROM OLD.active_inventory_cursor OR
           NEW.active_inventory_digest IS DISTINCT FROM OLD.active_inventory_digest OR
           NEW.active_inventory_last_key IS DISTINCT FROM OLD.active_inventory_last_key OR
           NEW.active_inventory_object_count IS DISTINCT FROM OLD.active_inventory_object_count OR
           NEW.active_inventory_bytes IS DISTINCT FROM OLD.active_inventory_bytes) AND
          OLD.phase <> 'ready_snapshots') OR
         ((NEW.inspected_snapshot_count IS DISTINCT FROM OLD.inspected_snapshot_count OR
           NEW.inspected_object_count IS DISTINCT FROM OLD.inspected_object_count OR
           NEW.inspected_bytes IS DISTINCT FROM OLD.inspected_bytes) AND
          OLD.phase <> 'ready_snapshots') OR
         NEW.snapshot_after_id < OLD.snapshot_after_id OR
         NEW.reservation_after_id < OLD.reservation_after_id OR
         NEW.claim_after_sequence < OLD.claim_after_sequence OR
         NEW.cleanup_intent_after_id < OLD.cleanup_intent_after_id OR
         (OLD.active_snapshot_id = NEW.active_snapshot_id AND
          OLD.active_inventory_last_key IS NOT NULL AND
          (NEW.active_inventory_last_key IS NULL OR
           NEW.active_inventory_last_key COLLATE "C" <
             OLD.active_inventory_last_key COLLATE "C")) OR
         (OLD.provider_last_key IS NOT NULL AND
          (NEW.provider_last_key IS NULL OR
           NEW.provider_last_key COLLATE "C" < OLD.provider_last_key COLLATE "C")) OR
         NEW.inspected_snapshot_count < OLD.inspected_snapshot_count OR
         NEW.inspected_object_count < OLD.inspected_object_count OR
         NEW.inspected_bytes < OLD.inspected_bytes OR
         NEW.provider_object_count < OLD.provider_object_count OR
         NEW.provider_bytes < OLD.provider_bytes OR
         NEW.finding_count < OLD.finding_count OR
         (OLD.provider_scan_completed AND NOT NEW.provider_scan_completed) OR
         (OLD.started_at IS NOT NULL AND NEW.started_at IS DISTINCT FROM OLD.started_at) OR
         NEW.inspected_snapshot_count - OLD.inspected_snapshot_count > 1 OR
         NEW.inspected_object_count - OLD.inspected_object_count > OLD.max_objects_per_step OR
         NEW.inspected_bytes - OLD.inspected_bytes > OLD.max_bytes_per_step OR
         (OLD.active_snapshot_id IS NOT NULL AND
          OLD.active_snapshot_id = NEW.active_snapshot_id AND
          (NEW.active_object_index - OLD.active_object_index > OLD.max_objects_per_step OR
           NEW.active_inventory_object_count - OLD.active_inventory_object_count >
             LEAST(OLD.provider_page_size, OLD.max_objects_per_step))) OR
         NEW.provider_object_count - OLD.provider_object_count > OLD.provider_page_size THEN
        RAISE EXCEPTION 'snapshot reconciliation progress must advance exactly once'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      IF OLD.active_snapshot_id IS NULL AND NEW.active_snapshot_id IS NOT NULL THEN
        IF NEW.phase <> 'ready_snapshots' OR
           NEW.snapshot_after_id IS DISTINCT FROM OLD.snapshot_after_id OR
           NEW.active_snapshot_id <= NEW.snapshot_after_id OR
           NEW.active_snapshot_id > NEW.snapshot_high_watermark OR
           NEW.inspected_snapshot_count IS DISTINCT FROM OLD.inspected_snapshot_count THEN
          RAISE EXCEPTION 'snapshot reconciliation active snapshot identity is invalid'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;
      ELSIF OLD.active_snapshot_id IS NOT NULL THEN
        IF NEW.active_snapshot_id IS NULL THEN
          IF NEW.snapshot_after_id IS DISTINCT FROM OLD.active_snapshot_id OR
             NEW.inspected_snapshot_count <> OLD.inspected_snapshot_count + 1 THEN
            RAISE EXCEPTION 'snapshot reconciliation cannot abandon active snapshot progress'
              USING ERRCODE = 'integrity_constraint_violation';
          END IF;
        ELSIF NEW.active_snapshot_id IS DISTINCT FROM OLD.active_snapshot_id OR
              NEW.active_snapshot_generation IS DISTINCT FROM OLD.active_snapshot_generation OR
              NEW.active_snapshot_accounting_generation IS DISTINCT FROM
                OLD.active_snapshot_accounting_generation OR
              NEW.snapshot_after_id IS DISTINCT FROM OLD.snapshot_after_id OR
              NEW.active_object_index < OLD.active_object_index OR
              NEW.active_inventory_object_count < OLD.active_inventory_object_count OR
              NEW.active_inventory_bytes < OLD.active_inventory_bytes OR
              NEW.inspected_snapshot_count IS DISTINCT FROM OLD.inspected_snapshot_count OR
              (OLD.active_inventory_digest IS NOT NULL AND NEW.active_inventory_digest IS NULL) OR
              (OLD.active_inventory_cursor IS NOT NULL AND NEW.active_inventory_cursor IS NULL) OR
              (OLD.active_inventory_digest IS NOT NULL AND
               NEW.active_object_index IS DISTINCT FROM OLD.active_object_index) THEN
          RAISE EXCEPTION 'snapshot reconciliation active snapshot progress is not monotonic'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;
      END IF;

      IF OLD.status IN ('completed', 'failed') OR
         (OLD.status = 'pending' AND NEW.status NOT IN ('running', 'failed')) OR
         (OLD.status = 'running' AND NEW.status NOT IN ('running', 'completed', 'failed')) OR
         (OLD.phase = 'ready_snapshots' AND
          NEW.phase NOT IN ('ready_snapshots', 'stale_reservations')) OR
         (OLD.phase = 'stale_reservations' AND
          NEW.phase NOT IN ('stale_reservations', 'publication_claims')) OR
         (OLD.phase = 'publication_claims' AND
          NEW.phase NOT IN ('publication_claims', 'cleanup_intents')) OR
         (OLD.phase = 'cleanup_intents' AND
          NEW.phase NOT IN ('cleanup_intents', 'provider_objects')) OR
         (OLD.phase = 'provider_objects' AND
          NEW.phase NOT IN ('provider_objects', 'completed')) OR
         (OLD.phase = 'completed' AND NEW.phase <> 'completed') THEN
        RAISE EXCEPTION 'snapshot reconciliation state cannot regress'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      IF NEW.phase IS DISTINCT FROM OLD.phase THEN
        IF (OLD.phase = 'ready_snapshots' AND
            (NEW.snapshot_after_id <> NEW.snapshot_high_watermark OR
             NEW.active_snapshot_id IS NOT NULL)) OR
           (OLD.phase = 'stale_reservations' AND
            NEW.reservation_after_id <> NEW.reservation_high_watermark) OR
           (OLD.phase = 'publication_claims' AND
            NEW.claim_after_sequence <> NEW.claim_sequence_high_watermark) OR
           (OLD.phase = 'cleanup_intents' AND
            (NEW.cleanup_intent_after_id <> NEW.cleanup_intent_high_watermark OR
             NEW.provider_cursor IS NOT NULL OR NEW.provider_last_key IS NOT NULL OR
             NEW.provider_object_count <> 0 OR NEW.provider_bytes <> 0 OR
             NEW.provider_scan_completed)) OR
           (OLD.phase = 'provider_objects' AND
            (NOT NEW.provider_scan_completed OR NEW.provider_cursor IS NOT NULL)) THEN
          RAISE EXCEPTION 'snapshot reconciliation phase cannot advance before exhaustion'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;
      END IF;

      RETURN NEW;
      END;
      $$
      """,
      "DROP FUNCTION storyarn_guard_project_snapshot_reconciliation_run()"
    )

    execute(
      """
      CREATE TRIGGER project_snapshot_reconciliation_runs_write_guard
      BEFORE INSERT OR UPDATE OR DELETE ON project_snapshot_reconciliation_runs
      FOR EACH ROW
      EXECUTE FUNCTION storyarn_guard_project_snapshot_reconciliation_run()
      """,
      "DROP TRIGGER project_snapshot_reconciliation_runs_write_guard ON project_snapshot_reconciliation_runs"
    )

    create table(:project_snapshot_reconciliation_findings) do
      add :run_id,
          references(:project_snapshot_reconciliation_runs, on_delete: :restrict),
          null: false

      add :fingerprint, :string, size: 64, null: false
      add :category, :string, null: false
      add :severity, :string, null: false
      add :workspace_id_snapshot, :bigint
      add :project_id_snapshot, :bigint
      add :project_snapshot_id_snapshot, :bigint
      add :storage_reservation_id_snapshot, :bigint
      add :lifecycle_generation, :bigint
      add :reservation_generation, :bigint
      add :object_prefix, :string, size: 500
      add :storage_key, :text
      add :expected_size_bytes, :bigint
      add :observed_size_bytes, :bigint
      add :error_code, :string
      add :details, :map, null: false, default: %{}

      timestamps(updated_at: false, type: :utc_datetime)
    end

    create unique_index(
             :project_snapshot_reconciliation_findings,
             [:run_id, :fingerprint],
             name: :project_snapshot_reconciliation_findings_run_fingerprint_idx
           )

    create index(
             :project_snapshot_reconciliation_findings,
             [:run_id, :category, :id]
           )

    create index(
             :project_snapshot_reconciliation_findings,
             [:workspace_id_snapshot, :category, :inserted_at]
           )

    create constraint(
             :project_snapshot_reconciliation_findings,
             :project_snapshot_reconciliation_findings_evidence,
             check: """
             fingerprint ~ '^[0-9a-f]{64}$' AND
             category IN (
               'ready_manifest_missing', 'ready_manifest_corrupt',
               'ready_object_missing', 'ready_object_corrupt',
               'ready_database_manifest_mismatch', 'ready_inventory_mismatch',
               'ready_accounting_mismatch', 'ready_verification_limit_exceeded',
               'failed_snapshot_finalization',
               'ambiguous_storage_object', 'unsafe_snapshot_storage_key',
               'abandoned_temporary_object', 'stale_reservation',
               'terminal_cleanup_failure'
             ) AND
             severity IN ('warning', 'critical') AND
             (workspace_id_snapshot IS NULL OR workspace_id_snapshot > 0) AND
             (project_id_snapshot IS NULL OR project_id_snapshot > 0) AND
             (project_snapshot_id_snapshot IS NULL OR project_snapshot_id_snapshot > 0) AND
             (storage_reservation_id_snapshot IS NULL OR storage_reservation_id_snapshot > 0) AND
             (lifecycle_generation IS NULL OR lifecycle_generation > 0) AND
             (reservation_generation IS NULL OR reservation_generation > 0) AND
             (expected_size_bytes IS NULL OR expected_size_bytes >= 0) AND
             (observed_size_bytes IS NULL OR observed_size_bytes >= 0) AND
             pg_column_size(details) <= 16384 AND
             (storage_key IS NULL OR octet_length(storage_key) <= 2048)
             """
           )

    execute(
      """
      CREATE FUNCTION storyarn_guard_project_snapshot_reconciliation_finding()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
      RAISE EXCEPTION 'snapshot reconciliation findings are immutable'
        USING ERRCODE = 'integrity_constraint_violation';
      END;
      $$
      """,
      "DROP FUNCTION storyarn_guard_project_snapshot_reconciliation_finding()"
    )

    execute(
      """
      CREATE FUNCTION storyarn_guard_project_snapshot_reconciliation_finding_insert()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        run_status text;
      BEGIN
      SELECT status
        INTO run_status
        FROM project_snapshot_reconciliation_runs
        WHERE id = NEW.run_id
        FOR UPDATE;

      IF run_status IN ('completed', 'failed') THEN
        RAISE EXCEPTION 'snapshot reconciliation findings cannot be inserted after run completion'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      RETURN NEW;
      END;
      $$
      """,
      "DROP FUNCTION storyarn_guard_project_snapshot_reconciliation_finding_insert()"
    )

    execute(
      """
      CREATE TRIGGER project_snapshot_reconciliation_findings_insert_guard
      BEFORE INSERT ON project_snapshot_reconciliation_findings
      FOR EACH ROW
      EXECUTE FUNCTION storyarn_guard_project_snapshot_reconciliation_finding_insert()
      """,
      "DROP TRIGGER project_snapshot_reconciliation_findings_insert_guard ON project_snapshot_reconciliation_findings"
    )

    execute(
      """
      CREATE TRIGGER project_snapshot_reconciliation_findings_immutable
      BEFORE UPDATE OR DELETE ON project_snapshot_reconciliation_findings
      FOR EACH ROW
      EXECUTE FUNCTION storyarn_guard_project_snapshot_reconciliation_finding()
      """,
      "DROP TRIGGER project_snapshot_reconciliation_findings_immutable ON project_snapshot_reconciliation_findings"
    )

    execute(
      """
      CREATE FUNCTION storyarn_guard_project_snapshot_reconciliation_truncate()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
      RAISE EXCEPTION 'snapshot reconciliation evidence cannot be truncated'
        USING ERRCODE = 'integrity_constraint_violation';
      END;
      $$
      """,
      "DROP FUNCTION storyarn_guard_project_snapshot_reconciliation_truncate()"
    )

    execute(
      """
      CREATE TRIGGER project_snapshot_reconciliation_runs_truncate_guard
      BEFORE TRUNCATE ON project_snapshot_reconciliation_runs
      FOR EACH STATEMENT
      EXECUTE FUNCTION storyarn_guard_project_snapshot_reconciliation_truncate()
      """,
      "DROP TRIGGER project_snapshot_reconciliation_runs_truncate_guard ON project_snapshot_reconciliation_runs"
    )

    execute(
      """
      CREATE TRIGGER project_snapshot_reconciliation_findings_truncate_guard
      BEFORE TRUNCATE ON project_snapshot_reconciliation_findings
      FOR EACH STATEMENT
      EXECUTE FUNCTION storyarn_guard_project_snapshot_reconciliation_truncate()
      """,
      "DROP TRIGGER project_snapshot_reconciliation_findings_truncate_guard ON project_snapshot_reconciliation_findings"
    )
  end
end
