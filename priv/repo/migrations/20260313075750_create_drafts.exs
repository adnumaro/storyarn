defmodule Storyarn.Repo.Migrations.CreateDrafts do
  use Ecto.Migration

  def change do
    # Create the drafts table
    create table(:drafts) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :entity_type, :string, null: false
      add :source_entity_id, :integer, null: false
      add :source_version_number, :integer
      add :name, :string, null: false
      add :status, :string, null: false, default: "active"
      add :created_by_id, references(:users, on_delete: :delete_all), null: false
      add :merged_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:drafts, [:project_id, :created_by_id, :status])
    create index(:drafts, [:source_entity_id, :entity_type])

    # Add draft_id to entity tables
    alter table(:sheets) do
      add :draft_id, references(:drafts, on_delete: :delete_all)
    end

    alter table(:flows) do
      add :draft_id, references(:drafts, on_delete: :delete_all)
    end

    alter table(:scenes) do
      add :draft_id, references(:drafts, on_delete: :delete_all)
    end

    create index(:sheets, [:draft_id], where: "draft_id IS NOT NULL")
    create index(:flows, [:draft_id], where: "draft_id IS NOT NULL")
    create index(:scenes, [:draft_id], where: "draft_id IS NOT NULL")
  end
end
