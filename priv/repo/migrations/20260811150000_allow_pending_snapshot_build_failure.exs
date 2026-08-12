defmodule Storyarn.Repo.Migrations.AllowPendingSnapshotBuildFailure do
  use Ecto.Migration

  def up, do: replace_lifecycle_guard("'building', 'failed', 'cancelled'")
  def down, do: replace_lifecycle_guard("'building', 'cancelled'")

  defp replace_lifecycle_guard(pending_targets) do
    execute("""
    CREATE OR REPLACE FUNCTION storyarn_guard_project_snapshot_lifecycle()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      same_generation_transition boolean;
      next_generation_transition boolean;
    BEGIN
      IF TG_OP = 'INSERT' THEN
        NEW.state_updated_at := date_trunc('second', timezone('UTC', clock_timestamp()));
        RETURN NEW;
      END IF;

      same_generation_transition :=
        NEW.lifecycle_generation = OLD.lifecycle_generation AND (
          NEW.lifecycle_state = OLD.lifecycle_state OR
          (OLD.lifecycle_state = 'pending' AND NEW.lifecycle_state IN (#{pending_targets})) OR
          (OLD.lifecycle_state = 'building' AND NEW.lifecycle_state IN ('verifying', 'failed', 'cancelled')) OR
          (OLD.lifecycle_state = 'verifying' AND NEW.lifecycle_state IN ('ready', 'failed', 'cancelled'))
        );

      next_generation_transition :=
        NEW.lifecycle_generation = OLD.lifecycle_generation + 1 AND (
          (NEW.lifecycle_state = 'deleting' AND OLD.lifecycle_state <> 'deleting') OR
          (NEW.lifecycle_state = 'pending' AND OLD.lifecycle_state IN ('building', 'verifying', 'failed')) OR
          (NEW.lifecycle_state = OLD.lifecycle_state AND
           OLD.lifecycle_state IN ('pending', 'building', 'verifying') AND
           OLD.cancel_requested_at IS NULL AND NEW.cancel_requested_at IS NOT NULL)
        );

      IF NOT (same_generation_transition OR next_generation_transition) THEN
        RAISE EXCEPTION 'project snapshot lifecycle transition is stale or invalid'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      NEW.state_updated_at := GREATEST(
        OLD.state_updated_at,
        date_trunc('second', timezone('UTC', clock_timestamp()))
      );

      RETURN NEW;
    END;
    $$
    """)
  end
end
