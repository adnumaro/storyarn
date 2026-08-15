defmodule Storyarn.Repo.Migrations.HardenAiIntegrationAuditNilification do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION ai_integration_audits_append_only() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'ai_integration_audits is append-only (DELETE blocked)';
      END IF;

      IF pg_trigger_depth() > 1
         AND NEW.id = OLD.id
         AND NEW.user_id IS NULL
         AND OLD.user_id IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM public.users WHERE id = OLD.user_id)
         AND NEW.actor_id = OLD.actor_id
         AND NEW.provider = OLD.provider
         AND NEW.action = OLD.action
         AND NEW.metadata = OLD.metadata
         AND NEW.inserted_at = OLD.inserted_at THEN
        RETURN NEW;
      END IF;

      RAISE EXCEPTION 'ai_integration_audits is append-only (UPDATE blocked)';
    END;
    $$ LANGUAGE plpgsql
    SET search_path = pg_catalog, pg_temp;
    """
  end

  def down do
    execute """
    CREATE OR REPLACE FUNCTION ai_integration_audits_append_only() RETURNS trigger AS $$
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
  end
end
