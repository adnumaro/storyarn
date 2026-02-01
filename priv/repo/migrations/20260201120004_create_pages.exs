defmodule Storyarn.Repo.Migrations.CreatePages do
  use Ecto.Migration

  def change do
    create table(:pages) do
      add :name, :string, null: false
      add :icon, :string, default: "page"
      add :position, :integer, default: 0
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :parent_id, references(:pages, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:pages, [:project_id])
    create index(:pages, [:parent_id])
    create index(:pages, [:project_id, :parent_id, :position])

    create table(:blocks) do
      add :type, :string, null: false
      add :position, :integer, default: 0
      add :config, :map, default: %{}
      add :value, :map, default: %{}
      add :page_id, references(:pages, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:blocks, [:page_id])
    create index(:blocks, [:page_id, :position])
  end
end
