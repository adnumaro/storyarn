defmodule Storyarn.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :settings, :map, default: %{}
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :owner_id, references(:users, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:projects, [:workspace_id])
    create index(:projects, [:owner_id])
    create unique_index(:projects, [:workspace_id, :slug])

    create table(:project_memberships) do
      add :role, :string, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:project_memberships, [:project_id])
    create index(:project_memberships, [:user_id])
    create unique_index(:project_memberships, [:project_id, :user_id])

    create table(:project_invitations) do
      add :email, :citext, null: false
      add :role, :string, null: false, default: "editor"
      add :token, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :invited_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:project_invitations, [:project_id])
    create unique_index(:project_invitations, [:token])
    create unique_index(:project_invitations, [:project_id, :email])
  end
end
