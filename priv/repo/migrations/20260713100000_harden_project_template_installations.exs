defmodule Storyarn.Repo.Migrations.HardenProjectTemplateInstallations do
  use Ecto.Migration

  def up do
    alter table(:project_template_installs) do
      modify :installed_at, :utc_datetime, null: true

      add :oban_job_id, references(:oban_jobs, on_delete: :nilify_all)
      add :status, :string, null: false, default: "completed"
      add :stage, :string, null: false, default: "completed"
      add :project_name, :string
      add :source, :string, null: false, default: "internal"
      add :idempotency_key, :string
      add :error_code, :string
      add :error_message, :text
      add :error_report, :map, null: false, default: %{}
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
    end

    execute """
    UPDATE project_template_installs AS installs
    SET project_name = projects.name,
        started_at = installs.inserted_at,
        completed_at = installs.installed_at
    FROM projects
    WHERE projects.id = installs.project_id
    """

    alter table(:project_template_installs) do
      modify :project_name, :string, null: false
    end

    create constraint(:project_template_installs, :project_template_installs_status_check,
             check: "status IN ('queued', 'running', 'retrying', 'completed', 'failed')"
           )

    create constraint(:project_template_installs, :project_template_installs_stage_check,
             check:
               "stage IN ('queued', 'verifying', 'materializing', 'retrying', 'completed', 'failed')"
           )

    create constraint(:project_template_installs, :project_template_installs_source_check,
             check: "source IN ('workspace_dashboard', 'template_show', 'internal')"
           )

    create constraint(:project_template_installs, :project_template_installs_state_check,
             check: """
             (status = 'completed' AND stage = 'completed' AND installed_at IS NOT NULL AND completed_at IS NOT NULL)
             OR (status = 'failed' AND stage = 'failed' AND installed_at IS NULL AND completed_at IS NOT NULL)
             OR (status IN ('queued', 'running', 'retrying') AND installed_at IS NULL AND completed_at IS NULL)
             """
           )

    create index(:project_template_installs, [:workspace_id, :status, :inserted_at],
             name: :template_installs_workspace_status_idx
           )

    create index(:project_template_installs, [:user_id, :status, :inserted_at],
             name: :template_installs_user_status_idx
           )

    create index(:project_template_installs, [:oban_job_id],
             name: :template_installs_oban_job_idx
           )

    create unique_index(:project_template_installs, [:idempotency_key],
             where: "idempotency_key IS NOT NULL AND status IN ('queued', 'running', 'retrying')",
             name: :project_template_installs_active_idempotency_unique
           )
  end

  def down do
    drop_if_exists index(:project_template_installs, [:idempotency_key],
                     name: :project_template_installs_active_idempotency_unique
                   )

    drop_if_exists index(:project_template_installs, [:oban_job_id],
                     name: :template_installs_oban_job_idx
                   )

    drop_if_exists index(:project_template_installs, [:user_id, :status, :inserted_at],
                     name: :template_installs_user_status_idx
                   )

    drop_if_exists index(:project_template_installs, [:workspace_id, :status, :inserted_at],
                     name: :template_installs_workspace_status_idx
                   )

    drop constraint(:project_template_installs, :project_template_installs_state_check)
    drop constraint(:project_template_installs, :project_template_installs_source_check)
    drop constraint(:project_template_installs, :project_template_installs_stage_check)
    drop constraint(:project_template_installs, :project_template_installs_status_check)

    execute "DELETE FROM project_template_installs WHERE installed_at IS NULL"

    alter table(:project_template_installs) do
      remove :completed_at
      remove :started_at
      remove :error_report
      remove :error_message
      remove :error_code
      remove :idempotency_key
      remove :source
      remove :project_name
      remove :stage
      remove :status
      remove :oban_job_id

      modify :installed_at, :utc_datetime, null: false
    end
  end
end
