defmodule Storyarn.Repo.Migrations.IdeationRoundTimersMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo.Migrations.IdeationRoundTimers

  @version 20_260_916_100_000

  if !Code.ensure_loaded?(IdeationRoundTimers) do
    Code.require_file(Path.expand("../../../../priv/repo/migrations/20260916100000_ideation_round_timers.exs", __DIR__))
  end

  setup do
    prefix = "ideation_round_timers_migration_test"
    Repo.query!("CREATE SCHEMA ideation_round_timers_migration_test")
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    create_legacy_schema()
    %{prefix: prefix}
  end

  test "upgrade hands each session clock to the round in progress, or to the last round, and keeps one live clock", %{
    prefix: prefix
  } do
    Repo.query!("INSERT INTO ideation_sessions VALUES (1), (2), (3)")

    # Round order, rather than the numeric database ID, decides the last round.
    Repo.query!("""
    INSERT INTO ideation_rounds VALUES
      (10, 1, 1, 'closed'), (20, 1, 2, 'active'),
      (40, 2, 1, 'closed'), (30, 2, 2, 'closed'),
      (50, 3, 1, 'active')
    """)

    Repo.query!("INSERT INTO ideation_timers VALUES (1, 1, 'running'), (2, 2, 'cancelled')")

    assert :ok = run_migration(prefix)

    assert [[1, 20, "running"], [2, 30, "cancelled"]] ==
             Repo.query!("SELECT id, round_id, status FROM ideation_timers ORDER BY id").rows

    assert [["NO"]] ==
             Repo.query!(
               "SELECT is_nullable FROM information_schema.columns WHERE table_schema = $1 AND table_name = 'ideation_timers' AND column_name = 'round_id'",
               [prefix]
             ).rows

    assert [
             ["ideation_timers_one_live_per_session"],
             ["ideation_timers_round_id_index"],
             ["ideation_timers_session_id_index"]
           ] ==
             Repo.query!(
               "SELECT indexname FROM pg_indexes WHERE schemaname = $1 AND tablename = 'ideation_timers' AND indexname <> 'ideation_timers_pkey' ORDER BY indexname",
               [prefix]
             ).rows

    # A second clock on one round, or a second live clock in one session, is refused.
    assert {:error, %Postgrex.Error{postgres: %{constraint: "ideation_timers_round_id_index"}}} =
             Repo.query("INSERT INTO ideation_timers VALUES (3, 1, 'cancelled', 20)")

    assert {:error, %Postgrex.Error{postgres: %{constraint: "ideation_timers_one_live_per_session"}}} =
             Repo.query("INSERT INTO ideation_timers VALUES (3, 1, 'paused', 10)")
  end

  defp create_legacy_schema do
    Repo.query!("CREATE TABLE ideation_sessions (id bigint PRIMARY KEY)")

    Repo.query!("""
    CREATE TABLE ideation_rounds (id bigint PRIMARY KEY, session_id bigint, number integer, status text)
    """)

    Repo.query!("CREATE TABLE ideation_timers (id bigint PRIMARY KEY, session_id bigint, status text)")
    Repo.query!("CREATE UNIQUE INDEX ideation_timers_session_id_index ON ideation_timers (session_id)")
  end

  defp run_migration(prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @version,
      IdeationRoundTimers,
      :forward,
      :up,
      :up,
      prefix: prefix,
      log: false
    )
  end
end
