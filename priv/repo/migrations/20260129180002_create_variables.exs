defmodule Storyarn.Repo.Migrations.CreateVariables do
  use Ecto.Migration

  def change do
    create table(:variables) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :default_value, :string
      add :description, :text
      add :category, :string
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:variables, [:project_id])
    create unique_index(:variables, [:project_id, :name])
  end
end
