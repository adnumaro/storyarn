defmodule Storyarn.Repo.Migrations.CreateProjectSnapshotReconciliationRepairs do
  use Ecto.Migration

  @finding_repair_constraint :project_snapshot_reconciliation_findings_repair_evidence
  @cleanup_request_namespace_constraint :storage_cleanup_requests_provider_namespace
  @cleanup_namespace_constraint :snapshot_cleanup_intents_provider_namespace

  def up do
    extend_reconciliation_findings()
    bind_snapshot_cleanup_to_provider_namespace()
    create_repair_actions()
  end

  def down do
    drop_repair_actions()
    unbind_snapshot_cleanup_from_provider_namespace()
    shrink_reconciliation_findings()
  end

  defp extend_reconciliation_findings do
    alter table(:project_snapshot_reconciliation_findings) do
      add :accounting_generation, :bigint
      add :cleanup_intent_id_snapshot, :bigint
    end

    execute("""
    ALTER TABLE project_snapshot_reconciliation_findings
    ADD CONSTRAINT #{@finding_repair_constraint}
    CHECK (
      (accounting_generation IS NULL OR accounting_generation > 0) AND
      (cleanup_intent_id_snapshot IS NULL OR cleanup_intent_id_snapshot > 0) AND
      (
        category NOT IN (
          'ready_manifest_missing', 'ready_manifest_corrupt',
          'ready_object_missing', 'ready_object_corrupt'
        ) OR accounting_generation IS NOT NULL
      ) AND
      (category <> 'terminal_cleanup_failure' OR cleanup_intent_id_snapshot IS NOT NULL)
    ) NOT VALID
    """)

    execute("""
    ALTER TABLE project_snapshot_reconciliation_findings
    VALIDATE CONSTRAINT #{@finding_repair_constraint}
    """)
  end

  defp shrink_reconciliation_findings do
    drop constraint(:project_snapshot_reconciliation_findings, @finding_repair_constraint)

    alter table(:project_snapshot_reconciliation_findings) do
      remove :accounting_generation
      remove :cleanup_intent_id_snapshot
    end
  end

  defp bind_snapshot_cleanup_to_provider_namespace do
    execute("""
    LOCK TABLE storage_cleanup_requests, snapshot_cleanup_intents
    IN SHARE ROW EXCLUSIVE MODE
    """)

    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM snapshot_cleanup_intents) OR
         EXISTS (
           SELECT 1
           FROM storage_cleanup_requests
           WHERE owner_kind = 'snapshot_lifecycle'
         ) THEN
        RAISE EXCEPTION
          'snapshot cleanup provider namespace migration requires reset state'
          USING ERRCODE = 'object_not_in_prerequisite_state';
      END IF;
    END;
    $$
    """)

    alter table(:storage_cleanup_requests) do
      add :provider_namespace_fingerprint, :string, size: 64
    end

    execute("""
    ALTER TABLE storage_cleanup_requests
    ADD CONSTRAINT #{@cleanup_request_namespace_constraint}
    CHECK (
      (owner_kind = 'storage_compensation' AND provider_namespace_fingerprint IS NULL) OR
      (owner_kind = 'snapshot_lifecycle' AND
       provider_namespace_fingerprint IS NOT NULL AND
       provider_namespace_fingerprint ~ '^[0-9a-f]{64}$')
    ) NOT VALID
    """)

    execute("""
    ALTER TABLE storage_cleanup_requests
    VALIDATE CONSTRAINT #{@cleanup_request_namespace_constraint}
    """)

    alter table(:snapshot_cleanup_intents) do
      add :provider_namespace_fingerprint, :string, size: 64
    end

    execute("""
    ALTER TABLE snapshot_cleanup_intents
    ADD CONSTRAINT #{@cleanup_namespace_constraint}
    CHECK (
      provider_namespace_fingerprint IS NOT NULL AND
      provider_namespace_fingerprint ~ '^[0-9a-f]{64}$'
    ) NOT VALID
    """)

    execute("""
    ALTER TABLE snapshot_cleanup_intents
    VALIDATE CONSTRAINT #{@cleanup_namespace_constraint}
    """)

    alter table(:snapshot_cleanup_intents) do
      modify :provider_namespace_fingerprint, :string, size: 64, null: false
    end

    execute(
      """
      CREATE FUNCTION storyarn_guard_snapshot_cleanup_provider_namespace()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'UPDATE' AND
           NEW.provider_namespace_fingerprint IS DISTINCT FROM OLD.provider_namespace_fingerprint THEN
          RAISE EXCEPTION 'snapshot cleanup provider namespace is immutable'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;

        RETURN NEW;
      END;
      $$
      """,
      "DROP FUNCTION storyarn_guard_snapshot_cleanup_provider_namespace()"
    )

    execute("""
    CREATE TRIGGER snapshot_cleanup_intents_provider_namespace_guard
    BEFORE UPDATE ON snapshot_cleanup_intents
    FOR EACH ROW
    EXECUTE FUNCTION storyarn_guard_snapshot_cleanup_provider_namespace()
    """)
  end

  defp unbind_snapshot_cleanup_from_provider_namespace do
    execute("""
    DROP TRIGGER snapshot_cleanup_intents_provider_namespace_guard
    ON snapshot_cleanup_intents
    """)

    execute("DROP FUNCTION storyarn_guard_snapshot_cleanup_provider_namespace()")
    drop constraint(:snapshot_cleanup_intents, @cleanup_namespace_constraint)

    alter table(:snapshot_cleanup_intents) do
      remove :provider_namespace_fingerprint
    end

    drop constraint(:storage_cleanup_requests, @cleanup_request_namespace_constraint)

    alter table(:storage_cleanup_requests) do
      remove :provider_namespace_fingerprint
    end
  end

  defp create_repair_actions do
    create table(:project_snapshot_reconciliation_repair_actions) do
      add :source_finding_id,
          references(:project_snapshot_reconciliation_findings,
            on_delete: :restrict,
            name: :snapshot_reconciliation_repair_actions_finding_fkey
          ),
          null: false

      add :contract_version, :integer, null: false, default: 1
      add :provider_namespace_fingerprint_snapshot, :string, size: 64, null: false
      add :subject_fingerprint, :string, size: 64, null: false
      add :action_kind, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :result_code, :string, size: 255
      add :attempt_count, :integer, null: false, default: 0
      add :finished_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :project_snapshot_reconciliation_repair_actions,
             [:source_finding_id, :contract_version],
             name: :snapshot_reconciliation_repair_actions_finding_idx
           )

    create index(
             :project_snapshot_reconciliation_repair_actions,
             [:provider_namespace_fingerprint_snapshot, :subject_fingerprint],
             name: :snapshot_reconciliation_repair_actions_subject_idx
           )

    create index(
             :project_snapshot_reconciliation_repair_actions,
             [:status, :id],
             name: :snapshot_reconciliation_repair_actions_status_idx
           )

    create constraint(
             :project_snapshot_reconciliation_repair_actions,
             :snapshot_reconciliation_repair_actions_shape,
             check: """
             contract_version = 1 AND
             provider_namespace_fingerprint_snapshot ~ '^[0-9a-f]{64}$' AND
             subject_fingerprint ~ '^[0-9a-f]{64}$' AND
             action_kind IN (
               'mark_missing', 'mark_corrupt', 'cleanup_expired_build',
               'replay_cleanup', 'report_only'
             ) AND
             status IN ('pending', 'repaired', 'resolved', 'manual', 'failed') AND
             (result_code IS NULL OR (result_code <> '' AND octet_length(result_code) <= 255)) AND
             ((status = 'pending' AND attempt_count >= 0 AND
               finished_at IS NULL AND result_code IS NULL) OR
              (status IN ('repaired', 'resolved', 'manual', 'failed') AND
               attempt_count > 0 AND finished_at IS NOT NULL AND
               result_code IS NOT NULL AND finished_at >= inserted_at))
             """
           )

    create_repair_action_guard()
  end

  defp create_repair_action_guard do
    execute(
      """
      CREATE FUNCTION storyarn_guard_snapshot_reconciliation_repair_action()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        evidence_fingerprint text;
        evidence_namespace text;
        evidence_run_status text;
        expected_action_kind text;
      BEGIN
      IF TG_OP = 'TRUNCATE' THEN
        RAISE EXCEPTION 'snapshot reconciliation repair actions cannot be truncated'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'snapshot reconciliation repair actions cannot be deleted'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      IF TG_OP = 'INSERT' THEN
        SELECT finding.fingerprint,
               run.provider_namespace_fingerprint,
               run.status,
               CASE
                 WHEN finding.category IN ('ready_manifest_missing', 'ready_object_missing')
                   THEN 'mark_missing'
                 WHEN finding.category IN ('ready_manifest_corrupt', 'ready_object_corrupt')
                   THEN 'mark_corrupt'
                 WHEN finding.category = 'stale_reservation' AND
                      finding.details->>'reason' IN (
                        'owning_job_missing', 'owning_job_completed',
                        'owning_job_discarded', 'owning_job_cancelled'
                      )
                   THEN 'cleanup_expired_build'
                 WHEN finding.category = 'failed_snapshot_finalization'
                   THEN 'cleanup_expired_build'
                 WHEN finding.category = 'terminal_cleanup_failure'
                   THEN 'replay_cleanup'
                 ELSE 'report_only'
               END
        INTO evidence_fingerprint, evidence_namespace, evidence_run_status, expected_action_kind
        FROM project_snapshot_reconciliation_findings AS finding
        JOIN project_snapshot_reconciliation_runs AS run ON run.id = finding.run_id
        WHERE finding.id = NEW.source_finding_id;

        IF NOT FOUND OR evidence_run_status <> 'completed' OR
           NEW.subject_fingerprint IS DISTINCT FROM evidence_fingerprint OR
           NEW.provider_namespace_fingerprint_snapshot IS DISTINCT FROM evidence_namespace OR
           NEW.action_kind IS DISTINCT FROM expected_action_kind THEN
          RAISE EXCEPTION 'snapshot reconciliation repair action evidence is invalid'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;

        IF NEW.status <> 'pending' OR NEW.attempt_count <> 0 OR
           NEW.result_code IS NOT NULL OR NEW.finished_at IS NOT NULL OR
           NEW.updated_at IS DISTINCT FROM NEW.inserted_at THEN
          RAISE EXCEPTION 'snapshot reconciliation repair actions must start pending and pristine'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;

        RETURN NEW;
      END IF;

      IF OLD.status <> 'pending' THEN
        RAISE EXCEPTION 'terminal snapshot reconciliation repair actions are immutable'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      IF NEW.id IS DISTINCT FROM OLD.id OR
         NEW.source_finding_id IS DISTINCT FROM OLD.source_finding_id OR
         NEW.contract_version IS DISTINCT FROM OLD.contract_version OR
         NEW.provider_namespace_fingerprint_snapshot IS DISTINCT FROM
           OLD.provider_namespace_fingerprint_snapshot OR
         NEW.subject_fingerprint IS DISTINCT FROM OLD.subject_fingerprint OR
         NEW.action_kind IS DISTINCT FROM OLD.action_kind OR
         NEW.inserted_at IS DISTINCT FROM OLD.inserted_at THEN
        RAISE EXCEPTION 'snapshot reconciliation repair action identity is immutable'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      IF NEW.status = 'pending' THEN
        IF NEW.attempt_count <> OLD.attempt_count + 1 OR
           NEW.updated_at < OLD.updated_at OR
           NEW.result_code IS DISTINCT FROM OLD.result_code OR
           NEW.finished_at IS DISTINCT FROM OLD.finished_at THEN
          RAISE EXCEPTION 'pending snapshot reconciliation repair actions may only record one attempt'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;
      ELSIF NEW.status IN ('repaired', 'resolved', 'manual', 'failed') THEN
        IF NEW.attempt_count <> OLD.attempt_count OR
           NEW.attempt_count <= 0 OR NEW.updated_at < OLD.updated_at OR
           NEW.finished_at < OLD.updated_at OR NEW.updated_at < NEW.finished_at THEN
          RAISE EXCEPTION 'snapshot reconciliation repair outcomes require a recorded attempt'
            USING ERRCODE = 'integrity_constraint_violation';
        END IF;
      ELSE
        RAISE EXCEPTION 'snapshot reconciliation repair action transition is invalid'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      RETURN NEW;
      END;
      $$
      """,
      "DROP FUNCTION storyarn_guard_snapshot_reconciliation_repair_action()"
    )

    execute("""
    CREATE TRIGGER snapshot_reconciliation_repair_actions_write_guard
    BEFORE INSERT OR UPDATE OR DELETE ON project_snapshot_reconciliation_repair_actions
    FOR EACH ROW
    EXECUTE FUNCTION storyarn_guard_snapshot_reconciliation_repair_action()
    """)

    execute("""
    CREATE TRIGGER snapshot_reconciliation_repair_actions_truncate_guard
    BEFORE TRUNCATE ON project_snapshot_reconciliation_repair_actions
    FOR EACH STATEMENT
    EXECUTE FUNCTION storyarn_guard_snapshot_reconciliation_repair_action()
    """)
  end

  defp drop_repair_actions do
    execute("""
    DROP TRIGGER snapshot_reconciliation_repair_actions_truncate_guard
    ON project_snapshot_reconciliation_repair_actions
    """)

    execute("""
    DROP TRIGGER snapshot_reconciliation_repair_actions_write_guard
    ON project_snapshot_reconciliation_repair_actions
    """)

    execute("DROP FUNCTION storyarn_guard_snapshot_reconciliation_repair_action()")
    drop table(:project_snapshot_reconciliation_repair_actions)
  end
end
