defmodule Storyarn.Repo.Migrations.CreateProjectSnapshots do
  use Ecto.Migration

  def change do
    create table(:project_snapshots) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :version_number, :integer, null: false
      add :title, :string
      add :description, :string
      add :storage_key, :string, null: false
      add :snapshot_size_bytes, :integer, null: false
      add :entity_counts, :map, default: %{}
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps(updated_at: false, type: :utc_datetime)
    end

    create unique_index(:project_snapshots, [:project_id, :version_number])
    create index(:project_snapshots, [:project_id])
  end
end
