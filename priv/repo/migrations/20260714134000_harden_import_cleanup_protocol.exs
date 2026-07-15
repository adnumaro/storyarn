defmodule Storyarn.Repo.Migrations.HardenImportCleanupProtocol do
  use Ecto.Migration

  def up do
    alter table(:import_plan_cleanup_requests) do
      add :generation, :integer, null: false, default: 0
    end

    drop constraint(
           :import_plan_cleanup_requests,
           :import_plan_cleanup_requests_state_fields_check
         )

    drop constraint(:import_plan_cleanup_requests, :import_plan_cleanup_requests_state_check)

    create constraint(:import_plan_cleanup_requests, :import_plan_cleanup_requests_state_check,
             check: "state IN ('reserved', 'retained', 'pending', 'deleting', 'completed')"
           )

    create constraint(
             :import_plan_cleanup_requests,
             :import_plan_cleanup_requests_state_fields_check,
             check: """
             (state = 'reserved' AND cleanup_after IS NOT NULL AND completed_at IS NULL)
             OR (state = 'retained' AND cleanup_after IS NULL AND completed_at IS NULL)
             OR (state = 'pending' AND cleanup_after IS NOT NULL AND completed_at IS NULL)
             OR (state = 'deleting' AND cleanup_after IS NOT NULL AND completed_at IS NULL)
             OR (state = 'completed' AND cleanup_after IS NULL AND completed_at IS NOT NULL)
             """
           )

    create constraint(
             :import_plan_cleanup_requests,
             :import_plan_cleanup_requests_generation_check,
             check: "generation >= 0"
           )

    alter table(:project_import_attempts) do
      modify :idempotency_key, :string, null: true
    end

    execute """
    UPDATE project_import_attempts
    SET user_id = NULL, idempotency_key = NULL
    WHERE status IN ('completed', 'failed', 'expired')
    """

    create constraint(
             :project_import_attempts,
             :project_import_attempts_terminal_privacy_check,
             check: """
             (status IN ('ready', 'queued', 'running', 'retrying') AND idempotency_key IS NOT NULL)
             OR (status IN ('completed', 'failed', 'expired') AND idempotency_key IS NULL AND user_id IS NULL)
             """
           )

    drop_if_exists index(:project_import_attempts, [:expires_at],
                     name: :project_import_attempts_expiry_idx
                   )

    create index(:project_import_attempts, [:expires_at],
             where: "status IN ('ready', 'queued', 'running', 'retrying')",
             name: :project_import_attempts_expiry_idx
           )
  end

  def down do
    drop_if_exists index(:project_import_attempts, [:expires_at],
                     name: :project_import_attempts_expiry_idx
                   )

    create index(:project_import_attempts, [:expires_at],
             where: "status IN ('ready', 'failed', 'completed')",
             name: :project_import_attempts_expiry_idx
           )

    drop constraint(:project_import_attempts, :project_import_attempts_terminal_privacy_check)

    execute """
    UPDATE project_import_attempts
    SET idempotency_key = md5(random()::text || clock_timestamp()::text || id::text) ||
                          md5(id::text || clock_timestamp()::text || random()::text)
    WHERE idempotency_key IS NULL
    """

    alter table(:project_import_attempts) do
      modify :idempotency_key, :string, null: false
    end

    drop constraint(:import_plan_cleanup_requests, :import_plan_cleanup_requests_generation_check)

    drop constraint(
           :import_plan_cleanup_requests,
           :import_plan_cleanup_requests_state_fields_check
         )

    drop constraint(:import_plan_cleanup_requests, :import_plan_cleanup_requests_state_check)

    execute """
    UPDATE import_plan_cleanup_requests
    SET state = 'pending',
        cleanup_after = COALESCE(cleanup_after, CURRENT_TIMESTAMP),
        completed_at = NULL
    WHERE state = 'deleting'
    """

    create constraint(:import_plan_cleanup_requests, :import_plan_cleanup_requests_state_check,
             check: "state IN ('reserved', 'retained', 'pending', 'completed')"
           )

    create constraint(
             :import_plan_cleanup_requests,
             :import_plan_cleanup_requests_state_fields_check,
             check: """
             (state = 'reserved' AND cleanup_after IS NOT NULL AND completed_at IS NULL)
             OR (state = 'retained' AND cleanup_after IS NULL AND completed_at IS NULL)
             OR (state = 'pending' AND cleanup_after IS NOT NULL AND completed_at IS NULL)
             OR (state = 'completed' AND cleanup_after IS NULL AND completed_at IS NOT NULL)
             """
           )

    alter table(:import_plan_cleanup_requests) do
      remove :generation
    end
  end
end
