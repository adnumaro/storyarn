defmodule Storyarn.Repo.Migrations.CreateWorkspaceMemberships do
  use Ecto.Migration

  def change do
    create table(:workspace_memberships) do
      add :role, :string, null: false, default: "member"
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:workspace_memberships, [:workspace_id, :user_id])
    create index(:workspace_memberships, [:user_id])
  end
end
