defmodule Storyarn.Repo.Migrations.CreateAssets do
  use Ecto.Migration

  def change do
    create table(:assets) do
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :size, :integer, null: false
      add :key, :string, null: false
      add :url, :string
      add :metadata, :map, default: %{}
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :uploaded_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:assets, [:project_id])
    create index(:assets, [:uploaded_by_id])
    create unique_index(:assets, [:project_id, :key])
  end
end
