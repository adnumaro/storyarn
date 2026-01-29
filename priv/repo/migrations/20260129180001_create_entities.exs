defmodule Storyarn.Repo.Migrations.CreateEntities do
  use Ecto.Migration

  def change do
    create table(:entities) do
      add :display_name, :string, null: false
      add :technical_name, :string, null: false
      add :color, :string
      add :description, :text
      add :data, :map, default: %{}
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :template_id, references(:entity_templates, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:entities, [:project_id])
    create index(:entities, [:template_id])
    create unique_index(:entities, [:project_id, :technical_name])
  end
end
