defmodule Storyarn.Repo.Migrations.CreateProjectImportAttempts do
  use Ecto.Migration

  def change do
    create table(:project_import_attempts) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :oban_job_id, references(:oban_jobs, on_delete: :nilify_all)

      add :status, :string, null: false
      add :stage, :string, null: false
      add :format, :string, null: false
      add :source_kind, :string, null: false
      add :parser_version, :string, null: false
      add :conflict_strategy, :string, null: false, default: "rename"
      add :idempotency_key, :string, null: false
      add :plan_storage_key, :string, null: false
      add :counts, :map, null: false, default: %{}
      add :warning_codes, {:array, :string}, null: false, default: []
      add :error_code, :string
      add :error_message, :text
      add :error_report, :map, null: false, default: %{}
      add :expires_at, :utc_datetime, null: false
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create constraint(:project_import_attempts, :project_import_attempts_status_check,
             check:
               "status IN ('ready', 'queued', 'running', 'retrying', 'completed', 'failed', 'expired')"
           )

    create constraint(:project_import_attempts, :project_import_attempts_stage_check,
             check:
               "stage IN ('parsed', 'queued', 'materializing', 'retrying', 'completed', 'failed', 'expired')"
           )

    create constraint(:project_import_attempts, :project_import_attempts_format_check,
             check: "format IN ('yarn', 'storyarn')"
           )

    create constraint(:project_import_attempts, :project_import_attempts_source_kind_check,
             check: "source_kind IN ('file', 'archive')"
           )

    create constraint(:project_import_attempts, :project_import_attempts_conflict_strategy_check,
             check: "conflict_strategy IN ('skip', 'overwrite', 'rename')"
           )

    create constraint(:project_import_attempts, :project_import_attempts_state_check,
             check: """
             (status = 'ready' AND stage = 'parsed' AND started_at IS NULL AND completed_at IS NULL)
             OR (status = 'queued' AND stage = 'queued' AND completed_at IS NULL)
             OR (status = 'running' AND stage = 'materializing' AND started_at IS NOT NULL AND completed_at IS NULL)
             OR (status = 'retrying' AND stage = 'retrying' AND started_at IS NOT NULL AND completed_at IS NULL)
             OR (status = 'completed' AND stage = 'completed' AND started_at IS NOT NULL AND completed_at IS NOT NULL)
             OR (status = 'failed' AND stage = 'failed' AND completed_at IS NOT NULL)
             OR (status = 'expired' AND stage = 'expired' AND completed_at IS NOT NULL)
             """
           )

    create index(:project_import_attempts, [:project_id, :status, :inserted_at],
             name: :project_import_attempts_project_status_idx
           )

    create index(:project_import_attempts, [:oban_job_id],
             name: :project_import_attempts_oban_job_idx
           )

    create index(:project_import_attempts, [:expires_at],
             where: "status IN ('ready', 'failed', 'completed')",
             name: :project_import_attempts_expiry_idx
           )

    create unique_index(:project_import_attempts, [:idempotency_key],
             where: "status IN ('ready', 'queued', 'running', 'retrying')",
             name: :project_import_attempts_active_idempotency_unique
           )
  end
end
