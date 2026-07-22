defmodule Storyarn.Repo.Migrations.CreateAiExecutionKernel do
  use Ecto.Migration

  def up do
    create table(:ai_workspace_policies) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :allowed_lanes, {:array, :string}, null: false, default: []
      add :version, :integer, null: false, default: 1
      add :updated_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_workspace_policies, [:workspace_id])

    create constraint(:ai_workspace_policies, :ai_workspace_policies_version_positive,
             check: "version > 0"
           )

    create constraint(:ai_workspace_policies, :ai_workspace_policies_known_lanes,
             check:
               "allowed_lanes <@ ARRAY['managed', 'personal_byok', 'workspace_byok']::varchar[]"
           )

    create table(:ai_workspace_policy_audits) do
      add :workspace_id, references(:workspaces, on_delete: :nilify_all)
      add :workspace_id_snapshot, :bigint, null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :actor_id, :bigint, null: false
      add :from_lanes, {:array, :string}, null: false, default: []
      add :to_lanes, {:array, :string}, null: false, default: []
      add :from_version, :integer, null: false
      add :to_version, :integer, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:ai_workspace_policy_audits, [:workspace_id, :inserted_at])
    create index(:ai_workspace_policy_audits, [:actor_id, :inserted_at])

    create constraint(:ai_workspace_policy_audits, :ai_workspace_policy_audits_version_step,
             check: "to_version = from_version + 1"
           )

    create table(:ai_route_options) do
      add :token_hash, :binary, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :actor_id, :bigint, null: false
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :project_id, references(:projects, on_delete: :delete_all)
      add :task_id, :string, null: false
      add :input_hash, :string, null: false
      add :subject_type, :string
      add :subject_id, :bigint
      add :subject_revision, :string
      add :lane, :string, null: false
      add :provider, :string, null: false
      add :model, :string, null: false
      add :credential_ref, :map, null: false
      add :payer, :string, null: false
      add :assignment_source, :string, null: false
      add :consent_basis, :string, null: false
      add :policy_version, :integer, null: false
      add :price_id, :string
      add :price_version, :integer
      add :expires_at, :utc_datetime, null: false
      add :consumed_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:ai_route_options, [:token_hash])
    create index(:ai_route_options, [:user_id, :expires_at])
    create index(:ai_route_options, [:workspace_id, :expires_at])

    create constraint(:ai_route_options, :ai_route_options_lane,
             check: "lane IN ('managed', 'personal_byok', 'workspace_byok')"
           )

    create constraint(:ai_route_options, :ai_route_options_subject_complete,
             check:
               "(subject_type IS NULL AND subject_id IS NULL AND subject_revision IS NULL) OR " <>
                 "(subject_type IS NOT NULL AND subject_id IS NOT NULL AND subject_revision IS NOT NULL)"
           )

    create table(:ai_operations) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :actor_id, :bigint, null: false
      add :workspace_id, references(:workspaces, on_delete: :nilify_all)
      add :workspace_id_snapshot, :bigint, null: false
      add :project_id, references(:projects, on_delete: :nilify_all)
      add :project_id_snapshot, :bigint
      add :route_option_id, references(:ai_route_options, on_delete: :nilify_all)
      add :task_id, :string, null: false
      add :capability, :string, null: false
      add :idempotency_key, :string, null: false
      add :execution_status, :string, null: false
      add :user_disposition, :string
      add :settlement_status, :string, null: false, default: "not_applicable"
      add :subject_type, :string
      add :subject_id, :bigint
      add :subject_revision, :string
      add :input_hash, :string, null: false
      add :input_schema_version, :string, null: false
      add :output_schema_version, :string, null: false
      add :prompt_version, :string, null: false
      add :context_version, :string, null: false
      add :result_type, :string, null: false
      add :result_destination, :map, null: false
      add :policy_decision, :map, null: false
      add :execution_route, :map, null: false
      add :error_classification, :string
      add :cancellation_requested_at, :utc_datetime
      add :started_at, :utc_datetime
      add :external_attempt_started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_operations, [:actor_id, :task_id, :idempotency_key],
             name: :ai_operations_actor_task_idempotency_unique
           )

    create index(:ai_operations, [:user_id, :inserted_at])
    create index(:ai_operations, [:workspace_id_snapshot, :inserted_at])
    create index(:ai_operations, [:project_id_snapshot, :inserted_at])
    create index(:ai_operations, [:execution_status, :inserted_at])

    create constraint(:ai_operations, :ai_operations_execution_status,
             check:
               "execution_status IN ('queued', 'running', 'succeeded', 'failed', 'cancelled', 'unknown')"
           )

    create constraint(:ai_operations, :ai_operations_user_disposition,
             check:
               "user_disposition IS NULL OR user_disposition IN ('accepted', 'dismissed', 'abandoned')"
           )

    create constraint(:ai_operations, :ai_operations_disposition_requires_success,
             check: "user_disposition IS NULL OR execution_status = 'succeeded'"
           )

    create constraint(:ai_operations, :ai_operations_settlement_status,
             check: "settlement_status IN ('not_applicable', 'reserved', 'committed', 'released')"
           )

    create constraint(:ai_operations, :ai_operations_subject_complete,
             check:
               "(subject_type IS NULL AND subject_id IS NULL AND subject_revision IS NULL) OR " <>
                 "(subject_type IS NOT NULL AND subject_id IS NOT NULL AND subject_revision IS NOT NULL)"
           )

    alter table(:ai_route_options) do
      add :consumed_by_operation_id, references(:ai_operations, on_delete: :nilify_all)
    end

    create unique_index(:ai_route_options, [:consumed_by_operation_id],
             where: "consumed_by_operation_id IS NOT NULL"
           )

    create table(:ai_usage_events) do
      add :operation_id, references(:ai_operations, on_delete: :restrict), null: false
      add :status, :string, null: false
      add :lane, :string, null: false
      add :provider, :string, null: false
      add :model, :string, null: false
      add :provider_request_id, :string
      add :input_units, :bigint
      add :output_units, :bigint
      add :latency_ms, :bigint
      add :provider_cost, :decimal
      add :provider_cost_currency, :string
      add :error_classification, :string
      add :started_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_usage_events, [:operation_id])
    create index(:ai_usage_events, [:provider, :inserted_at])

    create constraint(:ai_usage_events, :ai_usage_events_status,
             check: "status IN ('running', 'succeeded', 'failed', 'unknown')"
           )

    create constraint(:ai_usage_events, :ai_usage_events_nonnegative_counts,
             check:
               "(input_units IS NULL OR input_units >= 0) AND " <>
                 "(output_units IS NULL OR output_units >= 0) AND " <>
                 "(latency_ms IS NULL OR latency_ms >= 0) AND " <>
                 "(provider_cost IS NULL OR provider_cost >= 0)"
           )

    create table(:ai_results) do
      add :operation_id, references(:ai_operations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :actor_id, :bigint, null: false
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :project_id, references(:projects, on_delete: :delete_all)
      add :input_encrypted, :binary, null: false
      add :output_encrypted, :binary
      add :input_hash, :string, null: false
      add :task_id, :string, null: false
      add :prompt_version, :string, null: false
      add :context_version, :string, null: false
      add :output_schema_version, :string, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:ai_results, [:operation_id])
    create index(:ai_results, [:user_id, :expires_at])
    create index(:ai_results, [:project_id, :expires_at])
    create index(:ai_results, [:expires_at])

    execute_append_only_policy_audit()
    execute_project_result_cleanup_trigger()
  end

  def down do
    execute "DROP TRIGGER IF EXISTS ai_results_project_soft_delete_trigger ON projects;"
    execute "DROP FUNCTION IF EXISTS ai_results_project_soft_delete();"

    execute "DROP TRIGGER IF EXISTS ai_workspace_policy_audits_append_only_trigger ON ai_workspace_policy_audits;"

    execute "DROP FUNCTION IF EXISTS ai_workspace_policy_audits_append_only();"

    drop table(:ai_results)
    drop table(:ai_usage_events)

    drop_if_exists index(:ai_route_options, [:consumed_by_operation_id])

    alter table(:ai_route_options) do
      remove :consumed_by_operation_id
    end

    drop table(:ai_operations)
    drop table(:ai_route_options)
    drop table(:ai_workspace_policy_audits)
    drop table(:ai_workspace_policies)
  end

  defp execute_append_only_policy_audit do
    execute """
    CREATE FUNCTION ai_workspace_policy_audits_append_only() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'ai_workspace_policy_audits is append-only (DELETE blocked)';
      END IF;

      IF pg_trigger_depth() > 1
         AND (NEW.user_id IS NOT DISTINCT FROM OLD.user_id OR (OLD.user_id IS NOT NULL AND NEW.user_id IS NULL))
         AND (NEW.workspace_id IS NOT DISTINCT FROM OLD.workspace_id OR (OLD.workspace_id IS NOT NULL AND NEW.workspace_id IS NULL))
         AND NEW.actor_id = OLD.actor_id
         AND NEW.workspace_id_snapshot = OLD.workspace_id_snapshot
         AND NEW.from_lanes = OLD.from_lanes
         AND NEW.to_lanes = OLD.to_lanes
         AND NEW.from_version = OLD.from_version
         AND NEW.to_version = OLD.to_version
         AND NEW.inserted_at = OLD.inserted_at THEN
        RETURN NEW;
      END IF;

      RAISE EXCEPTION 'ai_workspace_policy_audits is append-only (UPDATE blocked)';
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER ai_workspace_policy_audits_append_only_trigger
    BEFORE UPDATE OR DELETE ON ai_workspace_policy_audits
    FOR EACH ROW EXECUTE FUNCTION ai_workspace_policy_audits_append_only();
    """
  end

  defp execute_project_result_cleanup_trigger do
    execute """
    CREATE FUNCTION ai_results_project_soft_delete() RETURNS trigger AS $$
    BEGIN
      IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
        DELETE FROM ai_results WHERE project_id = NEW.id;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER ai_results_project_soft_delete_trigger
    AFTER UPDATE OF deleted_at ON projects
    FOR EACH ROW EXECUTE FUNCTION ai_results_project_soft_delete();
    """
  end
end
