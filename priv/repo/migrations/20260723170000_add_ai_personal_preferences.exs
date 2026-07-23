defmodule Storyarn.Repo.Migrations.AddAiPersonalPreferences do
  use Ecto.Migration

  def up do
    create table(:ai_personal_preferences) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :integration_id, references(:ai_integrations, on_delete: :delete_all), null: false
      add :slot, :string, null: false
      add :provider, :string, null: false
      add :model, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :ai_personal_preferences,
             [:user_id, :workspace_id, :slot],
             name: :ai_personal_preferences_user_workspace_slot_index
           )

    create index(:ai_personal_preferences, [:integration_id],
             name: :ai_personal_preferences_integration_index
           )

    create constraint(
             :ai_personal_preferences,
             :ai_personal_preferences_slot_allowed,
             check: "slot IN ('general_assistant', 'writing_assistant', 'illustrator', 'voice')"
           )

    create constraint(
             :ai_personal_preferences,
             :ai_personal_preferences_provider_not_blank,
             check: "char_length(provider) > 0"
           )

    create constraint(
             :ai_personal_preferences,
             :ai_personal_preferences_model_not_blank,
             check: "char_length(model) > 0"
           )

    execute """
    CREATE FUNCTION ai_personal_preference_identity_guard() RETURNS trigger AS $$
    DECLARE
      integration_owner_id bigint;
      integration_provider text;
      active_assignment_exists boolean;
      workspace_membership_exists boolean;
    BEGIN
      SELECT user_id, provider
        INTO integration_owner_id, integration_provider
        FROM ai_integrations
       WHERE id = NEW.integration_id;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'AI preference integration does not exist';
      END IF;

      IF integration_owner_id IS DISTINCT FROM NEW.user_id
         OR integration_provider IS DISTINCT FROM NEW.provider THEN
        RAISE EXCEPTION 'AI preference identity does not match integration owner/provider';
      END IF;

      SELECT EXISTS(
        SELECT 1
          FROM ai_integration_workspace_assignments
         WHERE user_id = NEW.user_id
           AND workspace_id = NEW.workspace_id
           AND integration_id = NEW.integration_id
           AND revoked_at IS NULL
      ) INTO active_assignment_exists;

      IF NOT active_assignment_exists THEN
        RAISE EXCEPTION 'AI preference requires an active workspace assignment';
      END IF;

      SELECT EXISTS(
        SELECT 1
          FROM workspace_memberships
         WHERE user_id = NEW.user_id
           AND workspace_id = NEW.workspace_id
      ) INTO workspace_membership_exists;

      IF NOT workspace_membership_exists THEN
        RAISE EXCEPTION 'AI preference actor is not a workspace member';
      END IF;

      IF TG_OP = 'UPDATE' THEN
        IF NEW.user_id IS DISTINCT FROM OLD.user_id
           OR NEW.workspace_id IS DISTINCT FROM OLD.workspace_id
           OR NEW.slot IS DISTINCT FROM OLD.slot THEN
          RAISE EXCEPTION 'AI preference actor, workspace, and slot are immutable';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER ai_personal_preference_identity_guard_trigger
    BEFORE INSERT OR UPDATE ON ai_personal_preferences
    FOR EACH ROW EXECUTE FUNCTION ai_personal_preference_identity_guard();
    """
  end

  def down do
    execute """
    DROP TRIGGER ai_personal_preference_identity_guard_trigger
    ON ai_personal_preferences;
    """

    execute "DROP FUNCTION ai_personal_preference_identity_guard();"

    drop table(:ai_personal_preferences)
  end
end
