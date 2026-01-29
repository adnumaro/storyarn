defmodule Storyarn.Repo.Migrations.CreateProjectInvitations do
  use Ecto.Migration

  def change do
    create table(:project_invitations) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :invited_by_id, references(:users, on_delete: :delete_all), null: false
      add :email, :citext, null: false
      add :token, :binary, null: false
      add :role, :string, null: false, default: "editor"
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:project_invitations, [:project_id])
    create index(:project_invitations, [:invited_by_id])
    create unique_index(:project_invitations, [:token])
    create index(:project_invitations, [:email])
  end
end
