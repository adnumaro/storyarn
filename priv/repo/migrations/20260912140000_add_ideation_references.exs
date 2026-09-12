defmodule Storyarn.Repo.Migrations.AddIdeationReferences do
  use Ecto.Migration

  def change do
    create table(:ideation_references) do
      add :recovery_identity, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :session_id, references(:ideation_sessions, on_delete: :delete_all), null: false

      add :idea_id,
          references(:ideation_ideas, with: [session_id: :session_id], on_delete: :delete_all)

      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :target_type, :string, null: false
      add :target_id, :bigint
      add :target_identity, :string, null: false
      add :relation, :string, null: false
      add :version, :integer, null: false, default: 1
      add :context, :map, null: false
      add :deleted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ideation_references, [:id, :session_id])
    create index(:ideation_references, [:session_id, :idea_id, :id])

    create index(:ideation_references, [:target_type, :target_id, :session_id],
             where: "deleted_at IS NULL"
           )

    create unique_index(
             :ideation_references,
             [:session_id, "COALESCE(idea_id, 0)", :target_type, :target_id, :relation],
             where: "deleted_at IS NULL AND target_id IS NOT NULL",
             name: :ideation_references_active_target
           )

    create constraint(:ideation_references, :ideation_references_valid,
             check:
               "version > 0 AND (target_id IS NULL OR target_id > 0) AND " <>
                 "target_type IN ('sheet', 'flow', 'scene', 'asset', 'localization') AND " <>
                 "relation IN ('origin', 'reference', 'affects', 'result', 'work')"
           )

    create table(:ideation_reference_revisions) do
      add :recovery_identity, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :session_id, references(:ideation_sessions, on_delete: :delete_all), null: false

      add :reference_id,
          references(:ideation_references,
            with: [session_id: :session_id],
            on_delete: :delete_all
          ),
          null: false

      add :actor_id, references(:users, on_delete: :nilify_all)
      add :number, :integer, null: false
      add :operation, :string, null: false
      add :request_key, :uuid, null: false
      add :fingerprint, :binary, null: false
      add :context, :map, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:ideation_reference_revisions, [:reference_id, :number])
    create unique_index(:ideation_reference_revisions, [:session_id, :actor_id, :request_key])

    create constraint(:ideation_reference_revisions, :ideation_reference_revisions_valid,
             check: "number > 0 AND operation IN ('create', 'refresh', 'remove')"
           )
  end
end
