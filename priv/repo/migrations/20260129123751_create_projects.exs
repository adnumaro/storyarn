defmodule Storyarn.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :name, :string, null: false
      add :description, :text
      add :owner_id, references(:users, on_delete: :delete_all), null: false
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:projects, [:owner_id])
  end
end
