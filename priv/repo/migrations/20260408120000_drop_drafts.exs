defmodule Storyarn.Repo.Migrations.DropDrafts do
  use Ecto.Migration

  def up do
    alter table(:sheets) do
      remove_if_exists :draft_id, :bigint
    end

    alter table(:flows) do
      remove_if_exists :draft_id, :bigint
    end

    alter table(:scenes) do
      remove_if_exists :draft_id, :bigint
    end

    drop_if_exists table(:drafts)
  end

  def down do
    create table(:drafts) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :entity_type, :string, null: false
      add :source_entity_id, :bigint, null: false
      add :source_version_number, :integer, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "open"
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :merged_at, :utc_datetime
      add :last_edited_at, :utc_datetime
      add :baseline_entity_ids, :map

      timestamps(type: :utc_datetime)
    end

    create index(:drafts, [:project_id])
    create index(:drafts, [:project_id, :entity_type, :source_entity_id])
    create index(:drafts, [:status, :last_edited_at])

    alter table(:sheets) do
      add :draft_id, references(:drafts, on_delete: :delete_all)
    end

    alter table(:flows) do
      add :draft_id, references(:drafts, on_delete: :delete_all)
    end

    alter table(:scenes) do
      add :draft_id, references(:drafts, on_delete: :delete_all)
    end

    create index(:sheets, [:draft_id])
    create index(:flows, [:draft_id])
    create index(:scenes, [:draft_id])
  end
end
