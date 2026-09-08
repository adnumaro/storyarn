defmodule Storyarn.Repo.Migrations.AddIdeationTimers do
  use Ecto.Migration

  def change do
    alter table(:ideation_sessions) do
      add :contributions_open, :boolean, null: false, default: true
    end

    create table(:ideation_timers) do
      add :recovery_identity, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :session_id, references(:ideation_sessions, on_delete: :delete_all), null: false
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :version, :bigint, null: false, default: 1
      add :status, :string, null: false
      add :deadline_at, :utc_datetime_usec
      add :remaining_seconds, :integer, null: false
      add :duration_seconds, :integer, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :reveal_on_expiry, :boolean, null: false, default: false
      add :close_contributions_on_expiry, :boolean, null: false, default: false
      add :configuration_version, :integer, null: false
      add :expiry_outcome, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ideation_timers, [:session_id])
    create index(:ideation_timers, [:deadline_at], where: "status = 'running'")

    create constraint(:ideation_timers, :ideation_timers_values_valid,
             check: """
             version > 0 AND configuration_version > 0 AND
             duration_seconds BETWEEN 15 AND 86400 AND
             remaining_seconds BETWEEN 0 AND duration_seconds
             """
           )

    create constraint(:ideation_timers, :ideation_timers_lifecycle_valid,
             check: """
             (status = 'running' AND deadline_at IS NOT NULL AND remaining_seconds > 0 AND completed_at IS NULL AND expiry_outcome IS NULL) OR
             (status = 'paused' AND deadline_at IS NULL AND remaining_seconds > 0 AND completed_at IS NULL AND expiry_outcome IS NULL) OR
             (status = 'elapsed' AND deadline_at IS NULL AND remaining_seconds = 0 AND completed_at IS NOT NULL AND expiry_outcome IS NOT NULL AND expiry_outcome IN ('completed', 'skipped_authorization', 'skipped_configuration', 'skipped_session')) OR
             (status = 'cancelled' AND deadline_at IS NULL AND remaining_seconds = 0 AND completed_at IS NOT NULL AND expiry_outcome IS NULL)
             """
           )
  end
end
