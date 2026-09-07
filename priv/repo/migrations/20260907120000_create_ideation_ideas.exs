defmodule Storyarn.Repo.Migrations.CreateIdeationIdeas do
  use Ecto.Migration

  def change do
    create table(:ideation_ideas) do
      add :session_id, references(:ideation_sessions, on_delete: :delete_all), null: false
      add :author_id, references(:users, on_delete: :nilify_all)
      add :author_kind, :string, null: false, default: "human"
      add :creation_key, :uuid, null: false
      add :revision, :integer, null: false, default: 1
      add :published_revision, :integer
      add :state, :string, null: false, default: "active"
      add :publication_consent, :string, null: false, default: "author_only"
      add :configuration_version, :integer, null: false
      add :source_idea_id, references(:ideation_ideas, on_delete: :nilify_all)
      add :source_revision, :integer
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ideation_ideas, [:session_id, :author_id, :creation_key])
    create index(:ideation_ideas, [:session_id, :id])
    create index(:ideation_ideas, [:source_idea_id])
    create constraint(:ideation_ideas, :ideation_idea_revision_positive, check: "revision > 0")

    create constraint(:ideation_ideas, :ideation_idea_author_kind_valid,
             check: "author_kind IN ('human', 'ai')"
           )

    create constraint(:ideation_ideas, :ideation_idea_configuration_positive,
             check: "configuration_version > 0"
           )

    create constraint(:ideation_ideas, :ideation_idea_source_positive,
             check: "source_revision IS NULL OR source_revision > 0"
           )

    create constraint(:ideation_ideas, :ideation_idea_publication_valid,
             check:
               "published_revision IS NULL OR (published_revision > 0 AND published_revision <= revision)"
           )

    create constraint(:ideation_ideas, :ideation_idea_state_valid,
             check: "state IN ('active', 'parked', 'discarded')"
           )

    create constraint(:ideation_ideas, :ideation_idea_consent_valid,
             check: "publication_consent IN ('author_only', 'facilitator_assisted')"
           )

    create table(:ideation_idea_revisions) do
      add :idea_id, references(:ideation_ideas, on_delete: :delete_all), null: false
      add :number, :integer, null: false
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :title, :binary
      add :body, :binary, null: false
      add :state, :string, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:ideation_idea_revisions, [:idea_id, :number])

    create constraint(:ideation_idea_revisions, :ideation_idea_revision_number_positive,
             check: "number > 0"
           )

    create table(:ideation_idea_edits) do
      add :idea_id, references(:ideation_ideas, on_delete: :delete_all), null: false
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :request_key, :uuid, null: false
      add :fingerprint, :binary, null: false
      add :outcome, :string, null: false
      add :base_revision, :integer, null: false
      add :result_revision, :integer, null: false
      add :title, :binary
      add :body, :binary
      add :state, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:ideation_idea_edits, [:idea_id, :actor_id, :request_key])
    create index(:ideation_idea_edits, [:idea_id, :id])

    create constraint(:ideation_idea_edits, :ideation_idea_edit_revisions_valid,
             check: "base_revision >= 0 AND result_revision > 0"
           )

    create constraint(:ideation_idea_edits, :ideation_idea_edit_outcome_valid,
             check:
               "(outcome = 'saved' AND body IS NULL) OR (outcome = 'conflict' AND body IS NOT NULL)"
           )

    create table(:ideation_reveal_operations) do
      add :session_id, references(:ideation_sessions, on_delete: :delete_all), null: false
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :request_key, :uuid, null: false
      add :selection, :map, null: false
      add :manifest, {:array, :map}, null: false, default: []
      add :status, :string, null: false, default: "prepared"
      add :completed_at, :utc_datetime
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ideation_reveal_operations, [:session_id, :actor_id, :request_key])

    create constraint(:ideation_reveal_operations, :ideation_reveal_status_valid,
             check:
               "(status = 'prepared' AND completed_at IS NULL) OR (status = 'completed' AND completed_at IS NOT NULL)"
           )

    create table(:ideation_idea_publications) do
      add :idea_id, references(:ideation_ideas, on_delete: :delete_all), null: false
      add :revision, :integer, null: false

      add :operation_id, references(:ideation_reveal_operations, on_delete: :delete_all),
        null: false

      add :actor_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:ideation_idea_publications, [:idea_id, :revision])
    create index(:ideation_idea_publications, [:operation_id])

    create constraint(:ideation_idea_publications, :ideation_publication_revision_positive,
             check: "revision > 0"
           )
  end
end
