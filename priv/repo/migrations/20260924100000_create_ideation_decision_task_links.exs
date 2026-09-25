defmodule Storyarn.Repo.Migrations.CreateIdeationDecisionTaskLinks do
  use Ecto.Migration

  @moduledoc """
  Links a decision to tasks that live in an external tracker, by URL.

  Each row records one change to one link (linked, edited or unlinked); the
  latest row per link key is the link's current state, and the history keeps
  who changed what. Every link is `manual` for now: Storyarn neither reads the
  remote task nor holds credentials for it. A later provider connection adds
  its own kind instead of changing these rows.
  """

  def change do
    create table(:ideation_decision_task_links) do
      add :recovery_identity, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :session_id, references(:ideation_sessions, on_delete: :delete_all), null: false

      add :decision_id,
          references(:ideation_decisions,
            with: [session_id: :session_id],
            on_delete: :delete_all
          ),
          null: false

      add :link_key, :uuid, null: false
      add :operation, :string, null: false
      add :kind, :string, null: false
      add :url, :binary
      add :title, :binary
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :request_key, :uuid, null: false
      add :fingerprint, :binary, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:ideation_decision_task_links, [:decision_id, :link_key, :id])
    create unique_index(:ideation_decision_task_links, [:session_id, :actor_id, :request_key])

    create constraint(:ideation_decision_task_links, :ideation_decision_task_links_valid,
             check: """
             operation IN ('link', 'edit', 'unlink') AND kind = 'manual' AND octet_length(fingerprint) = 32 AND
             (operation = 'unlink') = (url IS NULL) AND (operation <> 'unlink' OR title IS NULL)
             """
           )
  end
end
