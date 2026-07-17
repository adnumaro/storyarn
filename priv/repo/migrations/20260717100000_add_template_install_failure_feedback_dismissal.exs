defmodule Storyarn.Repo.Migrations.AddTemplateInstallFailureFeedbackDismissal do
  @moduledoc false
  use Ecto.Migration

  def up do
    alter table(:project_template_installs) do
      add :feedback_dismissed_at, :utc_datetime
    end

    # Older releases could leave a partial project attached to a failed
    # installation. Soft-delete it only when every tenant and provenance field
    # agrees with the failed installation and no successful/current install or
    # template publication has adopted the project. The conservative exclusions
    # deliberately prefer an orphaned historical row over deleting a project
    # whose ownership is ambiguous.
    execute """
    LOCK TABLE project_templates,
               project_template_versions,
               project_template_publications
    IN SHARE ROW EXCLUSIVE MODE
    """

    execute """
    WITH failed_projects AS (
      SELECT DISTINCT ON (failed.project_id)
             failed.project_id,
             failed.project_template_version_id,
             failed.user_id,
             failed.workspace_id
      FROM project_template_installs AS failed
      JOIN projects AS project
        ON project.id = failed.project_id
       AND project.workspace_id = failed.workspace_id
       AND project.owner_id = failed.user_id
       AND project.created_from_template_version_id = failed.project_template_version_id
      WHERE failed.status = 'failed'
        AND failed.project_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM project_template_installs AS other_install
          WHERE other_install.project_id = failed.project_id
            AND other_install.status != 'failed'
        )
        AND NOT EXISTS (
          SELECT 1
          FROM project_templates AS template
          WHERE template.source_project_id = failed.project_id
        )
        AND NOT EXISTS (
          SELECT 1
          FROM project_template_versions AS version
          WHERE version.source_project_id = failed.project_id
        )
        AND NOT EXISTS (
          SELECT 1
          FROM project_template_publications AS publication
          WHERE publication.source_project_id = failed.project_id
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
      AND project.workspace_id = failed_projects.workspace_id
      AND project.owner_id = failed_projects.user_id
      AND project.created_from_template_version_id =
          failed_projects.project_template_version_id
      AND project.deleted_at IS NULL
    """

    # Failed installations cannot own a project after this migration. Historical
    # failures are marked dismissed because they predate the transient modal.
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
