defmodule Storyarn.Repo.Migrations.CreateProjectMemberships do
  use Ecto.Migration

  def change do
    create table(:project_memberships) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:project_memberships, [:project_id])
    create index(:project_memberships, [:user_id])
    create unique_index(:project_memberships, [:project_id, :user_id])
  end
end
