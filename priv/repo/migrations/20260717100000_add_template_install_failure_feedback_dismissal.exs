defmodule Storyarn.Repo.Migrations.AddTemplateInstallFailureFeedbackDismissal do
  @moduledoc false
  use Ecto.Migration

  def up do
    alter table(:project_template_installs) do
      add :feedback_dismissed_at, :utc_datetime
    end

    # Older releases could leave an active project attached to an installation
    # that later became failed. Soft-delete only projects whose recorded template
    # origin matches that failed installation; this avoids touching an arbitrary
    # project if a historical project_id is corrupt. Soft deletion preserves normal
    # project recovery/retention, and any completed installation also preserves it.
    execute """
    WITH failed_projects AS (
      SELECT DISTINCT ON (failed.project_id)
             failed.project_id,
             failed.project_template_version_id,
             failed.user_id
      FROM project_template_installs AS failed
      JOIN projects AS origin_project
        ON origin_project.id = failed.project_id
       AND origin_project.created_from_template_version_id = failed.project_template_version_id
      WHERE failed.status = 'failed'
        AND failed.project_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM project_template_installs AS completed
          WHERE completed.project_id = failed.project_id
            AND completed.status = 'completed'
        )
      ORDER BY failed.project_id,
               failed.completed_at DESC NULLS LAST,
               failed.id DESC
    )
    UPDATE projects AS project
    SET deleted_at = CURRENT_TIMESTAMP,
        deleted_by_id = failed_projects.user_id,
        updated_at = CURRENT_TIMESTAMP
    FROM failed_projects
    WHERE project.id = failed_projects.project_id
      AND project.created_from_template_version_id = failed_projects.project_template_version_id
      AND project.deleted_at IS NULL
    """

    execute """
    UPDATE project_template_installs
    SET feedback_dismissed_at = COALESCE(completed_at, updated_at),
        project_id = NULL
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
