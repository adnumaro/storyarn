defmodule Storyarn.Repo.Migrations.AddAiRoutingAssignments do
  use Ecto.Migration

  def up do
    alter table(:ai_integrations) do
      add :available_models, {:array, :string}
    end

    create table(:ai_integration_workspace_assignments) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :integration_id, references(:ai_integrations, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :assigned_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:ai_integration_workspace_assignments, [:user_id, :workspace_id],
             name: :ai_assignments_user_workspace_index
           )

    create index(:ai_integration_workspace_assignments, [:integration_id],
             name: :ai_assignments_integration_index
           )

    create unique_index(
             :ai_integration_workspace_assignments,
             [:integration_id, :workspace_id],
             where: "revoked_at IS NULL",
             name: :ai_assignments_active_integration_workspace_index
           )

    create unique_index(
             :ai_integration_workspace_assignments,
             [:user_id, :workspace_id, :provider],
             where: "revoked_at IS NULL",
             name: :ai_assignments_active_provider_workspace_index
           )

    create constraint(
             :ai_integration_workspace_assignments,
             :ai_assignments_provider_not_blank,
             check: "char_length(provider) > 0"
           )

    create constraint(
             :ai_integration_workspace_assignments,
             :ai_assignments_revocation_after_assignment,
             check: "revoked_at IS NULL OR revoked_at >= assigned_at"
           )

    execute """
    CREATE FUNCTION ai_assignment_identity_guard() RETURNS trigger AS $$
    DECLARE
      integration_owner_id bigint;
      integration_provider text;
      integration_revoked_at timestamp without time zone;
    BEGIN
      SELECT user_id, provider, revoked_at
        INTO integration_owner_id, integration_provider, integration_revoked_at
        FROM ai_integrations
       WHERE id = NEW.integration_id;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'AI assignment integration does not exist';
      END IF;

      IF integration_owner_id IS DISTINCT FROM NEW.user_id
         OR integration_provider IS DISTINCT FROM NEW.provider THEN
        RAISE EXCEPTION 'AI assignment identity does not match integration owner/provider';
      END IF;

      IF NEW.revoked_at IS NULL AND integration_revoked_at IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot activate an assignment for a revoked integration';
      END IF;

      IF TG_OP = 'UPDATE' THEN
        IF NEW.user_id IS DISTINCT FROM OLD.user_id
           OR NEW.workspace_id IS DISTINCT FROM OLD.workspace_id
           OR NEW.integration_id IS DISTINCT FROM OLD.integration_id
           OR NEW.provider IS DISTINCT FROM OLD.provider
           OR NEW.assigned_at IS DISTINCT FROM OLD.assigned_at THEN
          RAISE EXCEPTION 'AI assignment identity is immutable';
        END IF;

        IF OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at THEN
          RAISE EXCEPTION 'Revoked AI assignments cannot be reactivated';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER ai_assignment_identity_guard_trigger
    BEFORE INSERT OR UPDATE ON ai_integration_workspace_assignments
    FOR EACH ROW EXECUTE FUNCTION ai_assignment_identity_guard();
    """
  end

  def down do
    execute """
    DROP TRIGGER ai_assignment_identity_guard_trigger
    ON ai_integration_workspace_assignments;
    """

    execute "DROP FUNCTION ai_assignment_identity_guard();"

    drop table(:ai_integration_workspace_assignments)

    alter table(:ai_integrations) do
      remove :available_models
    end
  end
end
