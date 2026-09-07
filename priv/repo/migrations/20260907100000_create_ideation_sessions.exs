defmodule Storyarn.Repo.Migrations.CreateIdeationSessions do
  use Ecto.Migration

  def change do
    create table(:ideation_sessions) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :facilitator_id, references(:users, on_delete: :nilify_all)
      add :decision_owner_id, references(:users, on_delete: :nilify_all)
      add :title, :string, size: 160, null: false
      add :objective, :text
      add :context, :text
      add :status, :string, null: false, default: "open"
      add :archived_at, :utc_datetime
      add :revision, :integer, null: false, default: 1
      add :configuration_version, :integer, null: false, default: 1
      add :configuration, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create index(:ideation_sessions, [:project_id, :status, :id])

    create constraint(:ideation_sessions, :ideation_session_status,
             check:
               "(status = 'open' AND archived_at IS NULL) OR (status = 'archived' AND archived_at IS NOT NULL)"
           )

    create constraint(:ideation_sessions, :ideation_session_versions,
             check: "revision > 0 AND configuration_version > 0"
           )

    create table(:ideation_session_revisions) do
      add :session_id, references(:ideation_sessions, on_delete: :delete_all), null: false
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :number, :integer, null: false
      add :action, :string, null: false
      add :snapshot, :map, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:ideation_session_revisions, [:session_id, :number])
    create index(:ideation_session_revisions, [:session_id, :id])
  end
end
