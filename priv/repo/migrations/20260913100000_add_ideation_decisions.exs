defmodule Storyarn.Repo.Migrations.AddIdeationDecisions do
  use Ecto.Migration

  def change do
    create table(:ideation_decisions) do
      add :recovery_identity, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :session_id, references(:ideation_sessions, on_delete: :delete_all), null: false
      add :author_id, references(:users, on_delete: :nilify_all)
      add :version, :integer, null: false, default: 1
      add :status, :string, null: false, default: "proposed"
      add :accepted_version, :integer
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ideation_decisions, [:id, :session_id])
    create index(:ideation_decisions, [:session_id, :id])

    create constraint(:ideation_decisions, :ideation_decisions_state_valid,
             check:
               "version BETWEEN 1 AND 100 AND status IN ('proposed', 'accepted') AND " <>
                 "(accepted_version IS NULL OR accepted_version BETWEEN 1 AND version) AND " <>
                 "((status = 'accepted' AND accepted_version IS NOT NULL AND accepted_version = version) OR " <>
                 "(status = 'proposed' AND (accepted_version IS NULL OR accepted_version < version)))"
           )

    create table(:ideation_decision_revisions) do
      add :recovery_identity, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :session_id, references(:ideation_sessions, on_delete: :delete_all), null: false

      add :decision_id,
          references(:ideation_decisions,
            with: [session_id: :session_id],
            on_delete: :delete_all
          ),
          null: false

      add :number, :integer, null: false
      add :operation, :string, null: false
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :responsible_id, references(:users, on_delete: :nilify_all)
      add :title, :binary, null: false
      add :conclusion, :binary, null: false
      add :reason, :binary, null: false
      add :sources, :map, null: false
      add :source_context, :binary, null: false
      add :request_key, :uuid, null: false
      add :fingerprint, :binary, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:ideation_decision_revisions, [:decision_id, :number])
    create unique_index(:ideation_decision_revisions, [:session_id, :actor_id, :request_key])

    create constraint(:ideation_decision_revisions, :ideation_decision_revisions_valid,
             check:
               "number BETWEEN 1 AND 100 AND operation IN ('propose', 'revise', 'accept') AND " <>
                 "((number = 1 AND operation = 'propose') OR (number > 1 AND operation != 'propose')) AND " <>
                 "octet_length(fingerprint) = 32 AND jsonb_typeof(sources) = 'object' AND sources ? 'items' AND " <>
                 "jsonb_typeof(sources->'items') = 'array' AND " <>
                 "jsonb_array_length(sources->'items') BETWEEN 1 AND 20"
           )

    execute(
      """
      ALTER TABLE ideation_decisions ADD CONSTRAINT ideation_decisions_current_revision
      FOREIGN KEY (id, version) REFERENCES ideation_decision_revisions(decision_id, number)
      DEFERRABLE INITIALLY DEFERRED
      """,
      "ALTER TABLE ideation_decisions DROP CONSTRAINT ideation_decisions_current_revision"
    )

    execute(
      """
      ALTER TABLE ideation_decisions ADD CONSTRAINT ideation_decisions_accepted_revision
      FOREIGN KEY (id, accepted_version) REFERENCES ideation_decision_revisions(decision_id, number)
      DEFERRABLE INITIALLY DEFERRED
      """,
      "ALTER TABLE ideation_decisions DROP CONSTRAINT ideation_decisions_accepted_revision"
    )
  end
end
