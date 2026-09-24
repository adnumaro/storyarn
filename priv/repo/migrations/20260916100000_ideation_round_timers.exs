defmodule Storyarn.Repo.Migrations.IdeationRoundTimers do
  use Ecto.Migration

  # The countdown belongs to one round. Every session already has at least one
  # round, so an existing clock joins the round in progress, or the last one.
  def up do
    alter table(:ideation_timers) do
      add :round_id, references(:ideation_rounds, on_delete: :delete_all)
    end

    execute """
    UPDATE ideation_timers t SET round_id = r.id
    FROM (
      SELECT DISTINCT ON (session_id) id, session_id FROM ideation_rounds
      ORDER BY session_id, (status = 'active') DESC, number DESC
    ) r
    WHERE r.session_id = t.session_id
    """

    execute "ALTER TABLE ideation_timers ALTER COLUMN round_id SET NOT NULL"

    drop unique_index(:ideation_timers, [:session_id])
    create index(:ideation_timers, [:session_id])
    create unique_index(:ideation_timers, [:round_id])

    create unique_index(:ideation_timers, [:session_id],
             where: "status IN ('running', 'paused')",
             name: :ideation_timers_one_live_per_session
           )
  end

  def down do
    drop index(:ideation_timers, [:session_id], name: :ideation_timers_one_live_per_session)
    drop unique_index(:ideation_timers, [:round_id])
    drop index(:ideation_timers, [:session_id])

    execute """
    DELETE FROM ideation_timers t USING ideation_timers other
    WHERE t.session_id = other.session_id AND t.id < other.id
    """

    create unique_index(:ideation_timers, [:session_id])

    alter table(:ideation_timers) do
      remove :round_id
    end
  end
end
