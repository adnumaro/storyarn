defmodule Storyarn.Repo.Migrations.AddIdeationGroups do
  use Ecto.Migration

  def change do
    create table(:ideation_groups) do
      add :recovery_identity, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :session_id, references(:ideation_sessions, on_delete: :delete_all), null: false
      add :author_id, references(:users, on_delete: :nilify_all)
      add :title, :binary
      add :synthesis, :binary
      add :version, :integer, null: false, default: 1
      add :canvas, :map, null: false, default: %{}
      add :deleted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ideation_groups, [:id, :session_id])
    create index(:ideation_groups, [:session_id, :id])
    create constraint(:ideation_groups, :ideation_groups_version_positive, check: "version > 0")

    create unique_index(:ideation_ideas, [:id, :session_id])

    create table(:ideation_group_memberships) do
      add :recovery_identity, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :session_id, references(:ideation_sessions, on_delete: :delete_all), null: false

      add :group_id,
          references(:ideation_groups, with: [session_id: :session_id], on_delete: :delete_all),
          null: false

      add :idea_id,
          references(:ideation_ideas, with: [session_id: :session_id], on_delete: :delete_all),
          null: false

      add :source_revision, :integer, null: false
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :removed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:ideation_group_memberships, [:idea_id],
             where: "removed_at IS NULL",
             name: :ideation_group_memberships_one_active_group
           )

    create index(:ideation_group_memberships, [:group_id, :id])

    create constraint(:ideation_group_memberships, :ideation_group_memberships_revision_positive,
             check: "source_revision > 0"
           )

    create table(:ideation_group_revisions) do
      add :recovery_identity, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :session_id, references(:ideation_sessions, on_delete: :delete_all), null: false

      add :group_id,
          references(:ideation_groups, with: [session_id: :session_id], on_delete: :delete_all),
          null: false

      add :actor_id, references(:users, on_delete: :nilify_all)
      add :number, :integer, null: false
      add :operation, :string, null: false
      add :request_key, :uuid, null: false
      add :fingerprint, :binary, null: false
      add :title, :binary
      add :synthesis, :binary
      add :canvas, :map, null: false, default: %{}
      add :idea_ids, {:array, :bigint}, null: false, default: []
      add :sources, :map, null: false, default: %{}
      add :deleted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:ideation_group_revisions, [:group_id, :number])
    create unique_index(:ideation_group_revisions, [:session_id, :actor_id, :request_key])

    create constraint(:ideation_group_revisions, :ideation_group_revisions_operation_valid,
             check:
               "number > 0 AND operation IN ('create', 'update', 'move', 'delete', 'restore')"
           )
  end
end
