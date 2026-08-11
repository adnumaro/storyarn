defmodule Storyarn.Repo.Migrations.MultipartCleanupQuiescenceMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.AddMultipartCleanupQuiescence

  @migration_path Path.expand(
                    "../../../../priv/repo/migrations/20260811170000_add_multipart_cleanup_quiescence.exs",
                    __DIR__
                  )
  @migration_version 20_260_811_170_000
  @constraint "storage_cleanup_requests_multipart_quiescence"

  if !Code.ensure_loaded?(AddMultipartCleanupQuiescence) do
    Code.require_file(@migration_path)
  end

  setup do
    prefix = "multipart_cleanup_quiescence_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")

    Repo.query!("""
    CREATE TABLE #{prefix}.storage_cleanup_requests (
      id bigserial PRIMARY KEY,
      storage_keys text[] NOT NULL,
      inserted_at timestamp(0) with time zone NOT NULL DEFAULT clock_timestamp(),
      updated_at timestamp(0) with time zone NOT NULL DEFAULT clock_timestamp()
    )
    """)

    %{prefix: prefix}
  end

  test "adds a paired ordered durable window and rolls back cleanly", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    assert constraint_exists?(prefix, @constraint)

    assert {:ok, _result} =
             Repo.query("""
             INSERT INTO #{prefix}.storage_cleanup_requests (
               storage_keys,
               multipart_quiescence_started_at,
               multipart_quiescence_not_before
             )
             VALUES (
               ARRAY['projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip'],
               clock_timestamp(),
               clock_timestamp() + interval '5 minutes'
             )
             """)

    assert_check_violation(fn ->
      Repo.query(
        """
        INSERT INTO #{prefix}.storage_cleanup_requests (
          storage_keys,
          multipart_quiescence_started_at,
          multipart_quiescence_not_before
        )
        VALUES (ARRAY['projects/1/assets/file.png'], clock_timestamp(), NULL)
        """,
        [],
        mode: :savepoint
      )
    end)

    assert_check_violation(fn ->
      Repo.query(
        """
        INSERT INTO #{prefix}.storage_cleanup_requests (
          storage_keys,
          multipart_quiescence_started_at,
          multipart_quiescence_not_before
        )
        VALUES (
          ARRAY['projects/1/assets/file.png'],
          clock_timestamp(),
          clock_timestamp() - interval '1 second'
        )
        """,
        [],
        mode: :savepoint
      )
    end)

    assert :ok = run_migration(:down, prefix)
    refute constraint_exists?(prefix, @constraint)
    refute column_exists?(prefix, "multipart_quiescence_started_at")
    refute column_exists?(prefix, "multipart_quiescence_not_before")
  end

  defp run_migration(direction, prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      AddMultipartCleanupQuiescence,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end

  defp assert_check_violation(fun) do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} = fun.()
  end

  defp constraint_exists?(prefix, name) do
    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_constraint AS constraint_row
          JOIN pg_namespace AS namespace_row
            ON namespace_row.oid = constraint_row.connamespace
          WHERE namespace_row.nspname = $1 AND constraint_row.conname = $2
        )
        """,
        [prefix, name]
      )

    exists?
  end

  defp column_exists?(prefix, name) do
    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM information_schema.columns
          WHERE table_schema = $1 AND table_name = 'storage_cleanup_requests' AND column_name = $2
        )
        """,
        [prefix, name]
      )

    exists?
  end
end
