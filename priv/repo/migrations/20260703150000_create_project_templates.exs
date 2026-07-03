defmodule Storyarn.Repo.Migrations.CreateProjectTemplates do
  use Ecto.Migration

  def change do
    create table(:project_templates) do
      add :owner_id, references(:users, on_delete: :nilify_all)
      add :source_project_id, references(:projects, on_delete: :nilify_all)
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :visibility, :string, null: false, default: "private"
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    create constraint(:project_templates, :project_templates_visibility_check,
             check: "visibility IN ('private', 'public')"
           )

    create constraint(:project_templates, :project_templates_status_check,
             check: "status IN ('active', 'archived')"
           )

    create index(:project_templates, [:owner_id])
    create index(:project_templates, [:source_project_id])
    create index(:project_templates, [:visibility, :status])

    create unique_index(:project_templates, [:owner_id, :slug],
             where: "owner_id IS NOT NULL",
             name: :project_templates_owner_slug_unique
           )

    create unique_index(:project_templates, [:slug],
             where: "owner_id IS NULL",
             name: :project_templates_public_slug_unique
           )

    create table(:project_template_versions) do
      add :project_template_id, references(:project_templates, on_delete: :delete_all),
        null: false

      add :version_number, :integer, null: false
      add :source_project_id, references(:projects, on_delete: :nilify_all)
      add :snapshot_storage_key, :string, null: false
      add :asset_manifest_storage_key, :string, null: false
      add :checksum, :string, size: 64, null: false
      add :entity_counts, :map, null: false, default: %{}
      add :audit_report, :map, null: false, default: %{}
      add :published_by_id, references(:users, on_delete: :nilify_all)
      add :published_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:project_template_versions, :project_template_versions_version_number_check,
             check: "version_number > 0"
           )

    create unique_index(:project_template_versions, [:project_template_id, :version_number],
             name: :project_template_versions_template_version_unique
           )

    create index(:project_template_versions, [:project_template_id])
    create index(:project_template_versions, [:source_project_id])
    create index(:project_template_versions, [:published_by_id])

    alter table(:project_templates) do
      add :current_version_id, references(:project_template_versions, on_delete: :nilify_all)
    end

    create index(:project_templates, [:current_version_id])

    create table(:project_template_installs) do
      add :project_template_version_id, references(:project_template_versions), null: false
      add :user_id, references(:users), null: false
      add :workspace_id, references(:workspaces), null: false
      add :project_id, references(:projects, on_delete: :nilify_all)
      add :installed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:project_template_installs, [:project_template_version_id])
    create index(:project_template_installs, [:user_id])
    create index(:project_template_installs, [:workspace_id])
    create index(:project_template_installs, [:project_id])

    alter table(:projects) do
      add :created_from_template_version_id,
          references(:project_template_versions, on_delete: :nilify_all)
    end

    create index(:projects, [:created_from_template_version_id])
  end
end
