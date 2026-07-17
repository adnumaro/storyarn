defmodule Storyarn.Repo.Migrations.AddTemplateInstallFailureFeedbackDismissal do
  use Ecto.Migration

  def up do
    alter table(:project_template_installs) do
      add :feedback_dismissed_at, :utc_datetime
    end

    execute """
    UPDATE project_template_installs
    SET feedback_dismissed_at = COALESCE(completed_at, updated_at)
    WHERE status = 'failed'
    """

    create constraint(
             :project_template_installs,
             :project_template_installs_feedback_dismissal_check,
             check: "feedback_dismissed_at IS NULL OR status = 'failed'"
           )

    create constraint(
             :project_template_installs,
             :project_template_installs_failed_project_check,
             check: "status != 'failed' OR project_id IS NULL"
           )

    drop_if_exists index(
                     :project_template_installs,
                     [:workspace_id, :status, desc: :completed_at, desc: :id],
                     name: :template_installs_workspace_failure_feedback_idx
                   )

    create index(
             :project_template_installs,
             [:user_id, :workspace_id, desc: :completed_at, desc: :id],
             where: "status = 'failed' AND feedback_dismissed_at IS NULL",
             name: :template_installs_pending_failure_feedback_idx
           )
  end

  def down do
    drop_if_exists index(
                     :project_template_installs,
                     [:user_id, :workspace_id, desc: :completed_at, desc: :id],
                     name: :template_installs_pending_failure_feedback_idx
                   )

    create index(
             :project_template_installs,
             [:workspace_id, :status, desc: :completed_at, desc: :id],
             name: :template_installs_workspace_failure_feedback_idx
           )

    drop constraint(:project_template_installs, :project_template_installs_failed_project_check)

    drop constraint(
           :project_template_installs,
           :project_template_installs_feedback_dismissal_check
         )

    alter table(:project_template_installs) do
      remove :feedback_dismissed_at
    end
  end
end
