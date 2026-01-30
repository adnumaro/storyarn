defmodule Storyarn.Repo.Migrations.CreateWorkspaceInvitations do
  use Ecto.Migration

  def change do
    create table(:workspace_invitations) do
      add :email, :string, null: false
      add :token, :binary, null: false
      add :role, :string, null: false, default: "member"
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :invited_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:workspace_invitations, [:workspace_id])
    create unique_index(:workspace_invitations, [:token])
    create index(:workspace_invitations, [:email, :workspace_id])
  end
end
