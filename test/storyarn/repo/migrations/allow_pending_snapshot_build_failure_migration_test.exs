defmodule Storyarn.Repo.Migrations.AllowPendingSnapshotBuildFailureMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.AllowPendingSnapshotBuildFailure

  @migration_version 20_260_811_150_000

  if !Code.ensure_loaded?(AllowPendingSnapshotBuildFailure) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260811150000_allow_pending_snapshot_build_failure.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "pending_snapshot_failure_migration_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    create_schema!(prefix)
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    %{prefix: prefix}
  end

  test "up admits pending to failed and down restores the prior transition set", %{prefix: prefix} do
    pending_id = insert_pending!(prefix)
    assert :ok = run_migration(:up, prefix)
    assert {:ok, _result} = transition(prefix, pending_id, "failed")

    assert :ok = run_migration(:down, prefix)
    another_pending_id = insert_pending!(prefix)

    assert {:error, %Postgrex.Error{postgres: %{code: :integrity_constraint_violation}}} =
             transition(prefix, another_pending_id, "failed")

    assert {:ok, _result} = transition(prefix, another_pending_id, "building")
  end

  defp create_schema!(prefix) do
    Repo.query!("""
    CREATE TABLE #{prefix}.project_snapshots (
      id bigserial PRIMARY KEY,
      lifecycle_state text NOT NULL,
      lifecycle_generation bigint NOT NULL,
      cancel_requested_at timestamp(0) without time zone,
      state_updated_at timestamp(0) without time zone NOT NULL
    )
    """)

    Repo.query!("""
    CREATE FUNCTION #{prefix}.storyarn_guard_project_snapshot_lifecycle()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF TG_OP = 'INSERT' THEN
        RETURN NEW;
      END IF;

      IF NOT (
        NEW.lifecycle_generation = OLD.lifecycle_generation AND (
          NEW.lifecycle_state = OLD.lifecycle_state OR
          (OLD.lifecycle_state = 'pending' AND NEW.lifecycle_state IN ('building', 'cancelled'))
        )
      ) THEN
        RAISE EXCEPTION 'project snapshot lifecycle transition is stale or invalid'
          USING ERRCODE = 'integrity_constraint_violation';
      END IF;

      RETURN NEW;
    END;
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER project_snapshots_lifecycle_guard
    BEFORE INSERT OR UPDATE ON #{prefix}.project_snapshots
    FOR EACH ROW
    EXECUTE FUNCTION #{prefix}.storyarn_guard_project_snapshot_lifecycle()
    """)
  end

  defp insert_pending!(prefix) do
    %Postgrex.Result{rows: [[id]]} =
      Repo.query!("""
      INSERT INTO #{prefix}.project_snapshots (
        lifecycle_state, lifecycle_generation, state_updated_at
      )
      VALUES ('pending', 1, clock_timestamp())
      RETURNING id
      """)

    id
  end

  defp transition(prefix, id, state) do
    Repo.query(
      "UPDATE #{prefix}.project_snapshots SET lifecycle_state = $2 WHERE id = $1",
      [id, state],
      mode: :savepoint
    )
  end

  defp run_migration(direction, prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      AllowPendingSnapshotBuildFailure,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end
end
