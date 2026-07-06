defmodule Storyarn.Repo.Migrations.HardenProjectTemplateRelations do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE project_template_installs DROP CONSTRAINT project_template_installs_project_template_version_id_fkey"

    execute """
    ALTER TABLE project_template_installs
    ADD CONSTRAINT project_template_installs_project_template_version_id_fkey
    FOREIGN KEY (project_template_version_id)
    REFERENCES project_template_versions(id)
    ON DELETE CASCADE
    """

    execute "ALTER TABLE project_template_installs DROP CONSTRAINT project_template_installs_user_id_fkey"
    execute "ALTER TABLE project_template_installs ALTER COLUMN user_id DROP NOT NULL"

    execute """
    ALTER TABLE project_template_installs
    ADD CONSTRAINT project_template_installs_user_id_fkey
    FOREIGN KEY (user_id)
    REFERENCES users(id)
    ON DELETE SET NULL
    """

    execute "ALTER TABLE project_template_installs DROP CONSTRAINT project_template_installs_workspace_id_fkey"
    execute "ALTER TABLE project_template_installs ALTER COLUMN workspace_id DROP NOT NULL"

    execute """
    ALTER TABLE project_template_installs
    ADD CONSTRAINT project_template_installs_workspace_id_fkey
    FOREIGN KEY (workspace_id)
    REFERENCES workspaces(id)
    ON DELETE SET NULL
    """

    drop_if_exists index(:project_template_publications, [:owner_id, :source_project_id],
                     name: :project_template_publications_active_new_source_unique
                   )

    create unique_index(:project_template_publications, [:source_project_id],
             where: "mode = 'new' AND status IN ('queued', 'running', 'retrying')",
             name: :project_template_publications_active_new_source_unique
           )
  end

  def down do
    drop_if_exists index(:project_template_publications, [:source_project_id],
                     name: :project_template_publications_active_new_source_unique
                   )

    create unique_index(:project_template_publications, [:owner_id, :source_project_id],
             where: "mode = 'new' AND status IN ('queued', 'running', 'retrying')",
             name: :project_template_publications_active_new_source_unique
           )

    execute "ALTER TABLE project_template_installs DROP CONSTRAINT project_template_installs_workspace_id_fkey"
    execute "ALTER TABLE project_template_installs ALTER COLUMN workspace_id SET NOT NULL"

    execute """
    ALTER TABLE project_template_installs
    ADD CONSTRAINT project_template_installs_workspace_id_fkey
    FOREIGN KEY (workspace_id)
    REFERENCES workspaces(id)
    """

    execute "ALTER TABLE project_template_installs DROP CONSTRAINT project_template_installs_user_id_fkey"
    execute "ALTER TABLE project_template_installs ALTER COLUMN user_id SET NOT NULL"

    execute """
    ALTER TABLE project_template_installs
    ADD CONSTRAINT project_template_installs_user_id_fkey
    FOREIGN KEY (user_id)
    REFERENCES users(id)
    """

    execute "ALTER TABLE project_template_installs DROP CONSTRAINT project_template_installs_project_template_version_id_fkey"

    execute """
    ALTER TABLE project_template_installs
    ADD CONSTRAINT project_template_installs_project_template_version_id_fkey
    FOREIGN KEY (project_template_version_id)
    REFERENCES project_template_versions(id)
    """
  end
end
