defmodule Storyarn.Repo.Migrations.RebuildIdeationDecisions do
  use Ecto.Migration

  @moduledoc """
  Rebuilds brainstorming decisions as an object: what the team agreed to do
  (a verb), which Sheets, Flows and Scenes it affects, who applies it next, and
  a per-target application record. Withdrawn and superseded decisions stay in
  the history instead of disappearing.

  Nothing is carried over: the product has no users, and a decision recorded
  without a verb or affected content cannot be expressed in the new model.
  Irreversible for the same reason.
  """

  @operations "'propose', 'revise', 'accept', 'register', 'withdraw', 'supersede'"
  @verbs "'create', 'change', 'test', 'keep', 'discard'"
  @states "'not_applied', 'partially_applied', 'applied', 'no_change_needed'"

  def up do
    execute("DROP TABLE ideation_decision_revisions, ideation_decisions CASCADE")

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

    # A pending revision is a proposal over an agreement still in force.
    create constraint(:ideation_decisions, :ideation_decisions_state_valid,
             check:
               "version BETWEEN 1 AND 100 AND " <>
                 "(accepted_version IS NULL OR accepted_version BETWEEN 1 AND version) AND " <>
                 "((status = 'proposed' AND (accepted_version IS NULL OR accepted_version < version)) OR " <>
                 "(status = 'accepted' AND accepted_version IS NOT NULL) OR " <>
                 "(status = 'withdrawn' AND accepted_version IS NULL) OR " <>
                 "(status = 'superseded' AND accepted_version IS NOT NULL))"
           )

    create table(:ideation_decision_revisions) do
      add :recovery_identity, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :session_id, references(:ideation_sessions, on_delete: :delete_all), null: false

      add :decision_id,
          references(:ideation_decisions, with: [session_id: :session_id], on_delete: :delete_all),
          null: false

      add :number, :integer, null: false
      add :operation, :string, null: false
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :responsible_id, references(:users, on_delete: :nilify_all)
      add :verb, :string, null: false
      add :title, :binary, null: false
      add :conclusion, :binary, null: false
      add :reason, :binary
      add :sources, :map, null: false
      add :source_context, :binary, null: false
      add :targets, :map, null: false
      add :target_context, :binary, null: false
      add :next_action, :binary
      add :next_action_owner_id, references(:users, on_delete: :nilify_all)
      add :round_id, references(:ideation_rounds, with: [session_id: :session_id], on_delete: :nothing)
      add :replaces_id, references(:ideation_decisions, with: [session_id: :session_id], on_delete: :nothing)
      add :superseded_by_id, references(:ideation_decisions, with: [session_id: :session_id], on_delete: :nothing)
      add :request_key, :uuid, null: false
      add :fingerprint, :binary, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:ideation_decision_revisions, [:decision_id, :number])
    create unique_index(:ideation_decision_revisions, [:session_id, :actor_id, :request_key])
    create index(:ideation_decision_revisions, [:replaces_id], where: "replaces_id IS NOT NULL")

    create constraint(:ideation_decision_revisions, :ideation_decision_revisions_valid,
             check:
               "number BETWEEN 1 AND 100 AND operation IN (#{@operations}) AND verb IN (#{@verbs}) AND " <>
                 "((number = 1 AND operation = 'propose') OR (number > 1 AND operation != 'propose')) AND " <>
                 "(operation = 'supersede') = (superseded_by_id IS NOT NULL) AND " <>
                 "(replaces_id IS NULL OR replaces_id != decision_id) AND " <>
                 "octet_length(fingerprint) = 32 AND jsonb_typeof(sources) = 'object' AND sources ? 'items' AND " <>
                 "jsonb_typeof(sources->'items') = 'array' AND " <>
                 "jsonb_array_length(sources->'items') BETWEEN 1 AND 20 AND " <>
                 "jsonb_typeof(targets) = 'object' AND targets ? 'items' AND " <>
                 "jsonb_typeof(targets->'items') = 'array' AND jsonb_array_length(targets->'items') <= 5"
           )

    execute("""
    ALTER TABLE ideation_decisions ADD CONSTRAINT ideation_decisions_current_revision
    FOREIGN KEY (id, version) REFERENCES ideation_decision_revisions(decision_id, number)
    DEFERRABLE INITIALLY DEFERRED
    """)

    execute("""
    ALTER TABLE ideation_decisions ADD CONSTRAINT ideation_decisions_accepted_revision
    FOREIGN KEY (id, accepted_version) REFERENCES ideation_decision_revisions(decision_id, number)
    DEFERRABLE INITIALLY DEFERRED
    """)

    # Declarations are statements about one agreement. Accepting a revision
    # starts a new agreement with nothing declared, so every target reads as
    # not applied again while the earlier statements stay in the history.
    create table(:ideation_decision_applications) do
      add :recovery_identity, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :session_id, references(:ideation_sessions, on_delete: :delete_all), null: false

      add :decision_id,
          references(:ideation_decisions, with: [session_id: :session_id], on_delete: :delete_all),
          null: false

      add :agreement, :integer, null: false
      add :target_key, :uuid
      add :state, :string, null: false
      add :note, :binary
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :request_key, :uuid, null: false
      add :fingerprint, :binary, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:ideation_decision_applications, [:decision_id, :agreement, :id])
    create unique_index(:ideation_decision_applications, [:session_id, :actor_id, :request_key])

    create constraint(:ideation_decision_applications, :ideation_decision_applications_valid,
             check: "state IN (#{@states}) AND agreement BETWEEN 1 AND 100 AND octet_length(fingerprint) = 32"
           )

    execute("""
    ALTER TABLE ideation_decision_applications ADD CONSTRAINT ideation_decision_applications_agreement
    FOREIGN KEY (decision_id, agreement) REFERENCES ideation_decision_revisions(decision_id, number)
    """)
  end

  def down do
    raise Ecto.MigrationError,
      message: "RebuildIdeationDecisions is irreversible: decisions from the earlier model cannot be expressed."
  end
end
