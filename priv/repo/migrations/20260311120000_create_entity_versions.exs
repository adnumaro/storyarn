defmodule Storyarn.Repo.Migrations.CreateEntityVersions do
  use Ecto.Migration

  def change do
    create table(:entity_versions) do
      add :entity_type, :string, null: false
      add :entity_id, :integer, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :version_number, :integer, null: false
      add :title, :string, size: 255
      add :description, :text
      add :change_summary, :string
      add :storage_key, :string, null: false
      add :snapshot_size_bytes, :integer, null: false
      add :is_auto, :boolean, default: false, null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps(updated_at: false, type: :utc_datetime)
    end

    create unique_index(:entity_versions, [:entity_type, :entity_id, :version_number],
             name: :entity_versions_type_id_number_unique
           )

    create index(:entity_versions, [:entity_type, :entity_id, :inserted_at])
    create index(:entity_versions, [:project_id])
  end
end
