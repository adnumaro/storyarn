defmodule Storyarn.Repo.Migrations.AddIdeationRounds do
  use Ecto.Migration

  def change do
    create table(:ideation_rounds) do
      add :recovery_identity, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :session_id, references(:ideation_sessions, on_delete: :delete_all), null: false
      add :number, :integer, null: false
      add :prompt, :text
      add :status, :string, null: false, default: "planned"
      add :started_at, :utc_datetime_usec
      add :closed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ideation_rounds, [:session_id, :number])
    create unique_index(:ideation_rounds, [:id, :session_id])

    create unique_index(:ideation_rounds, [:session_id],
             where: "status = 'active'",
             name: :ideation_rounds_one_active_per_session
           )

    create index(:ideation_rounds, [:session_id, :id])
    create constraint(:ideation_rounds, :ideation_rounds_number_positive, check: "number > 0")

    create constraint(:ideation_rounds, :ideation_rounds_prompt_length,
             check: "char_length(prompt) <= 2000"
           )

    create constraint(:ideation_rounds, :ideation_rounds_lifecycle_valid,
             check: """
             (status = 'planned' AND started_at IS NULL AND closed_at IS NULL) OR
             (status = 'active' AND started_at IS NOT NULL AND closed_at IS NULL) OR
             (status = 'closed' AND started_at IS NOT NULL AND closed_at IS NOT NULL AND closed_at >= started_at)
             """
           )

    alter table(:ideation_ideas) do
      add :round_id,
          references(:ideation_rounds, with: [session_id: :session_id], on_delete: :nothing)

      add :late_contribution, :boolean, null: false, default: false
    end

    create index(:ideation_ideas, [:session_id, :round_id, :id])

    create constraint(:ideation_ideas, :ideation_ideas_late_round_required,
             check: "round_id IS NOT NULL OR NOT late_contribution"
           )
  end
end
