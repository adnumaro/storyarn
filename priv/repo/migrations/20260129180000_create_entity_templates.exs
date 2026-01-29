defmodule Storyarn.Repo.Migrations.CreateEntityTemplates do
  use Ecto.Migration

  def change do
    create table(:entity_templates) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :description, :text
      add :color, :string
      add :icon, :string
      add :schema, :map, default: %{}
      add :is_default, :boolean, default: false, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:entity_templates, [:project_id])
    create index(:entity_templates, [:project_id, :type])
    create unique_index(:entity_templates, [:project_id, :name])
  end
end
