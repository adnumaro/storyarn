defmodule Storyarn.Repo.Migrations.CreateProjectTemplatePublications do
  use Ecto.Migration

  def change do
    create table(:project_template_publications) do
      add :owner_id, references(:users, on_delete: :delete_all), null: false
      add :requested_by_id, references(:users, on_delete: :nilify_all)
      add :source_project_id, references(:projects, on_delete: :delete_all), null: false

      add :project_template_id, references(:project_templates, on_delete: :delete_all)

      add :project_template_version_id,
          references(:project_template_versions, on_delete: :nilify_all)

      add :oban_job_id, references(:oban_jobs, on_delete: :nilify_all)

      add :mode, :string, null: false
      add :status, :string, null: false, default: "queued"
      add :name, :string, null: false
      add :description, :text
      add :snapshot_storage_key, :string
      add :asset_manifest_storage_key, :string
      add :checksum, :string, size: 64
      add :entity_counts, :map, null: false, default: %{}
      add :audit_report, :map, null: false, default: %{}
      add :error_code, :string
      add :error_message, :text
      add :error_report, :map, null: false, default: %{}
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create constraint(:project_template_publications, :project_template_publications_mode_check,
             check: "mode IN ('new', 'update')"
           )

    create constraint(:project_template_publications, :project_template_publications_status_check,
             check: "status IN ('queued', 'running', 'retrying', 'published', 'failed')"
           )

    create index(:project_template_publications, [:owner_id, :source_project_id, :inserted_at],
             name: :template_publications_owner_source_inserted_idx
           )

    create index(:project_template_publications, [:project_template_id, :inserted_at],
             name: :template_publications_template_inserted_idx
           )

    create index(:project_template_publications, [:project_template_version_id],
             name: :template_publications_version_idx
           )

    create index(:project_template_publications, [:oban_job_id],
             name: :template_publications_oban_job_idx
           )

    create unique_index(:project_template_publications, [:project_template_id],
             where:
               "project_template_id IS NOT NULL AND status IN ('queued', 'running', 'retrying')",
             name: :project_template_publications_active_template_unique
           )

    create unique_index(:project_template_publications, [:owner_id, :source_project_id],
             where: "mode = 'new' AND status IN ('queued', 'running', 'retrying')",
             name: :project_template_publications_active_new_source_unique
           )
  end
end
