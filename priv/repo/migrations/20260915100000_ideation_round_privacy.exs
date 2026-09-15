defmodule Storyarn.Repo.Migrations.IdeationRoundPrivacy do
  use Ecto.Migration

  # Private mode moves from the session to the round: the round in progress can
  # be private until the facilitator reveals it, or the timer does. Groups learn
  # their round so a hidden round hides its groups too.
  def up do
    alter table(:ideation_rounds) do
      add :private, :boolean, null: false, default: false
      add :reveal_on_expiry, :boolean, null: false, default: false
      add :revealed_at, :utc_datetime_usec
    end

    alter table(:ideation_groups) do
      add :round_id, :bigint
    end

    create index(:ideation_groups, [:round_id])

    # A private session hid every round it had; each keeps its mask until the
    # facilitator reveals it.
    execute("""
    UPDATE ideation_rounds r SET private = true
    FROM ideation_sessions s
    WHERE r.session_id = s.id
      AND COALESCE(s.configuration->>'private_mode', 'false') = 'true'
    """)

    execute("UPDATE ideation_sessions SET configuration = configuration - 'private_mode'")

    # A clock that promised to reveal at 0:00 hands that promise to the round in progress.
    execute("""
    UPDATE ideation_rounds r SET reveal_on_expiry = true
    FROM ideation_timers t
    WHERE t.session_id = r.session_id AND r.status = 'active' AND r.private
      AND t.reveal_on_expiry AND t.status IN ('running', 'paused')
    """)

    # The timer takes any duration from one second; the digits are the input.
    # The round decides the reveal at 0:00, so the clock loses its own flag.
    execute("""
    ALTER TABLE ideation_timers
      DROP COLUMN reveal_on_expiry,
      DROP CONSTRAINT ideation_timers_values_valid,
      ADD CONSTRAINT ideation_timers_values_valid CHECK (
        version > 0 AND configuration_version > 0 AND
        duration_seconds BETWEEN 1 AND 86400 AND
        remaining_seconds BETWEEN 0 AND duration_seconds
      )
    """)

    execute("""
    UPDATE ideation_groups g SET round_id = sub.round_id
    FROM (
      SELECT m.group_id, MIN(i.round_id) AS round_id
      FROM ideation_group_memberships m
      JOIN ideation_ideas i ON i.id = m.idea_id
      WHERE m.removed_at IS NULL
      GROUP BY m.group_id
    ) sub
    WHERE g.id = sub.group_id
    """)
  end

  def down do
    execute("""
    ALTER TABLE ideation_timers
      ADD COLUMN reveal_on_expiry boolean NOT NULL DEFAULT false,
      DROP CONSTRAINT ideation_timers_values_valid,
      ADD CONSTRAINT ideation_timers_values_valid CHECK (
        version > 0 AND configuration_version > 0 AND
        duration_seconds BETWEEN 1 AND 86400 AND
        remaining_seconds BETWEEN 0 AND duration_seconds
      )
    """)

    execute("""
    UPDATE ideation_sessions s SET configuration = configuration || '{"private_mode": true}'::jsonb
    FROM ideation_rounds r
    WHERE r.session_id = s.id AND r.private
    """)

    alter table(:ideation_groups) do
      remove :round_id
    end

    alter table(:ideation_rounds) do
      remove :private
      remove :reveal_on_expiry
      remove :revealed_at
    end
  end
end
