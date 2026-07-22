defmodule Storyarn.Repo.Migrations.HardenAiExecutionKernel do
  use Ecto.Migration

  def up do
    alter table(:ai_route_options) do
      add :task_contract_hash, :string, null: false, default: "legacy-contract"
    end

    alter table(:ai_operations) do
      add :task_contract_hash, :string, null: false, default: "legacy-contract"
    end

    alter table(:ai_results) do
      modify :expires_at, :utc_datetime, null: true
    end

    execute "ALTER TABLE ai_route_options ALTER COLUMN task_contract_hash DROP DEFAULT"
    execute "ALTER TABLE ai_operations ALTER COLUMN task_contract_hash DROP DEFAULT"

    execute """
    CREATE OR REPLACE FUNCTION ai_workspace_policy_audits_append_only() RETURNS trigger AS $$
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
  end

  def down do
    execute """
    CREATE OR REPLACE FUNCTION ai_workspace_policy_audits_append_only() RETURNS trigger AS $$
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

    execute "UPDATE ai_results SET expires_at = NOW() + INTERVAL '24 hours' WHERE expires_at IS NULL"

    alter table(:ai_results) do
      modify :expires_at, :utc_datetime, null: false
    end

    alter table(:ai_operations) do
      remove :task_contract_hash
    end

    alter table(:ai_route_options) do
      remove :task_contract_hash
    end
  end
end
