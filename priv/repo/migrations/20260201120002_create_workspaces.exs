defmodule Storyarn.Repo.Migrations.CreateWorkspaces do
  use Ecto.Migration

  def change do
    create table(:workspaces) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :banner_url, :string
      add :color, :string
      add :owner_id, references(:users, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:workspaces, [:slug])
    create index(:workspaces, [:owner_id])

    create table(:workspace_memberships) do
      add :role, :string, null: false
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:workspace_memberships, [:workspace_id])
    create index(:workspace_memberships, [:user_id])
    create unique_index(:workspace_memberships, [:workspace_id, :user_id])

    create table(:workspace_invitations) do
      add :email, :citext, null: false
      add :role, :string, null: false, default: "member"
      add :token, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :invited_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:workspace_invitations, [:workspace_id])
    create unique_index(:workspace_invitations, [:token])
    create unique_index(:workspace_invitations, [:workspace_id, :email])
  end
end
