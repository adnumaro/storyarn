defmodule Storyarn.Repo.Migrations.IdeationRoundPrivacyMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo.Migrations.IdeationRoundPrivacy

  @version 20_260_915_100_000

  if !Code.ensure_loaded?(IdeationRoundPrivacy) do
    Code.require_file(
      Path.expand("../../../../priv/repo/migrations/20260915100000_ideation_round_privacy.exs", __DIR__)
    )
  end

  setup do
    prefix = "ideation_round_privacy_migration_test"
    Repo.query!("CREATE SCHEMA ideation_round_privacy_migration_test")
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    create_legacy_schema()
    %{prefix: prefix}
  end

  test "upgrade keeps detached synthesis private and gives every group a stable round without removing history", %{
    prefix: prefix
  } do
    Repo.query!("""
    INSERT INTO ideation_sessions VALUES (1, '{"private_mode":true}'), (2, '{"private_mode":false}')
    """)

    # Round order, rather than the numeric database ID, determines the fallback.
    Repo.query!("""
    INSERT INTO ideation_rounds VALUES (20, 1, 1, 'closed'), (10, 1, 2, 'active'), (30, 2, 1, 'active')
    """)

    Repo.query!("INSERT INTO ideation_ideas VALUES (1, 20), (2, 10), (3, NULL)")
    Repo.query!("INSERT INTO ideation_groups VALUES (1, 1), (2, 1), (3, 1), (4, 2), (5, 1)")

    Repo.query!("""
    INSERT INTO ideation_group_memberships VALUES
      (1, 1, 1, '2026-09-01'), (2, 1, 2, '2026-09-02'),
      (3, 2, 1, NULL), (4, 2, 2, '2026-09-02'),
      (5, 5, 3, '2026-09-02')
    """)

    assert :ok = run_migration(prefix)

    assert [[1, 10, true], [2, 20, true], [3, 20, true], [4, 30, false], [5, 20, true]] ==
             Repo.query!("""
             SELECT g.id, g.round_id, r.private FROM ideation_groups g
             JOIN ideation_rounds r ON r.id = g.round_id ORDER BY g.id
             """).rows

    assert [[5, 4]] ==
             Repo.query!("SELECT COUNT(*), COUNT(removed_at) FROM ideation_group_memberships").rows

    assert [[false], [false]] ==
             Repo.query!("SELECT configuration ? 'private_mode' FROM ideation_sessions ORDER BY id").rows
  end

  defp create_legacy_schema do
    Repo.query!("CREATE TABLE ideation_sessions (id bigint PRIMARY KEY, configuration jsonb NOT NULL)")

    Repo.query!("""
    CREATE TABLE ideation_rounds (id bigint PRIMARY KEY, session_id bigint, number integer, status text)
    """)

    Repo.query!("CREATE TABLE ideation_groups (id bigint PRIMARY KEY, session_id bigint)")
    Repo.query!("CREATE TABLE ideation_ideas (id bigint PRIMARY KEY, round_id bigint)")

    Repo.query!("""
    CREATE TABLE ideation_group_memberships (
      id bigint PRIMARY KEY, group_id bigint, idea_id bigint, removed_at timestamp
    )
    """)

    Repo.query!("""
    CREATE TABLE ideation_timers (
      session_id bigint, status text, reveal_on_expiry boolean,
      version bigint, configuration_version bigint, duration_seconds integer, remaining_seconds integer,
      CONSTRAINT ideation_timers_values_valid CHECK (version > 0)
    )
    """)
  end

  defp run_migration(prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @version,
      IdeationRoundPrivacy,
      :forward,
      :up,
      :up,
      prefix: prefix,
      log: false
    )
  end
end
