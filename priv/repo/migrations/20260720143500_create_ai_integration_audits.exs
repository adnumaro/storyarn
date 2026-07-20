defmodule Storyarn.Repo.Migrations.CreateAiIntegrationAudits do
  use Ecto.Migration

  def up do
    create table(:ai_integration_audits) do
      # FK is nilified on user deletion for referential integrity; actor_id
      # below preserves attribution for security investigations afterwards.
      add :user_id, references(:users, on_delete: :nilify_all)
      # Immutable snapshot of the acting user's id. No FK on purpose — it must
      # survive account deletion (pseudonymous, not direct PII).
      add :actor_id, :integer, null: false
      add :provider, :string, null: false
      add :action, :string, null: false
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:ai_integration_audits, [:user_id, :inserted_at])
    create index(:ai_integration_audits, [:provider, :inserted_at])

    # Append-only enforcement at the database level. The single allowed UPDATE
    # is the FK nilify fired by user deletion (only user_id may change, and
    # only to NULL).
    execute """
    CREATE FUNCTION ai_integration_audits_append_only() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'ai_integration_audits is append-only (DELETE blocked)';
      END IF;

      IF NEW.user_id IS NULL
         AND OLD.user_id IS NOT NULL
         AND NEW.actor_id = OLD.actor_id
         AND NEW.provider = OLD.provider
         AND NEW.action = OLD.action
         AND NEW.metadata = OLD.metadata
         AND NEW.inserted_at = OLD.inserted_at THEN
        RETURN NEW;
      END IF;

      RAISE EXCEPTION 'ai_integration_audits is append-only (UPDATE blocked)';
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER ai_integration_audits_append_only_trigger
    BEFORE UPDATE OR DELETE ON ai_integration_audits
    FOR EACH ROW EXECUTE FUNCTION ai_integration_audits_append_only();
    """
  end

  def down do
    execute "DROP TRIGGER ai_integration_audits_append_only_trigger ON ai_integration_audits;"
    execute "DROP FUNCTION ai_integration_audits_append_only();"
    drop table(:ai_integration_audits)
  end
end
