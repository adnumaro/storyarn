defmodule Storyarn.Repo.Migrations.AddIdeationRecoveryIdentity do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :recovery_identity, :uuid, null: false, default: fragment("gen_random_uuid()")
    end

    create unique_index(:users, [:recovery_identity])

    create table(:ideation_recovery_captures, primary_key: false) do
      add :project_id, references(:projects, on_delete: :delete_all), primary_key: true
      add :digest, :binary, null: false
      add :capsule, :map, null: false
    end

    alter table(:ideation_ideas) do
      add :creation_source_id, :bigint
    end

    execute "UPDATE ideation_ideas SET creation_source_id = source_idea_id"

    alter table(:ideation_sessions) do
      add :deleted_at, :utc_datetime_usec
    end
  end

  def down do
    drop table(:ideation_recovery_captures)
    alter table(:ideation_sessions), do: remove(:deleted_at)
    alter table(:ideation_ideas), do: remove(:creation_source_id)
    drop unique_index(:users, [:recovery_identity])
    alter table(:users), do: remove(:recovery_identity)
  end
end
