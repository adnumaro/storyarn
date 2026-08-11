defmodule Storyarn.ReleaseSnapshotCutoverTest do
  use Storyarn.DataCase, async: false

  alias Ecto.Migration.Runner
  alias Storyarn.Release
  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.AddSnapshotStorageAccounting
  alias Storyarn.Repo.Migrations.AllowZeroByteSnapshotExportLeases

  @storage_accounting_migration 20_260_804_120_000
  @lifecycle_migration 20_260_805_130_000
  @barrier_migration 20_260_810_130_000
  @v2_only_migration 20_260_811_180_000
  @release_gate :enforce_snapshot_lifecycle_release_gate
  @authorization_probe_migration 90_000_000_000_001

  defmodule AuthorizationProbeMigration do
    @moduledoc false
    use Ecto.Migration

    def up do
      Release.assert_snapshot_lifecycle_migration_authorized!()
      execute("CREATE TABLE snapshot_cutover_authorization_probe (id bigint PRIMARY KEY)")
    end
  end

  if !Code.ensure_loaded?(AddSnapshotStorageAccounting) do
    Code.require_file(
      Path.expand(
        "../../priv/repo/migrations/20260804120000_add_snapshot_storage_accounting.exs",
        __DIR__
      )
    )
  end

  if !Code.ensure_loaded?(AllowZeroByteSnapshotExportLeases) do
    Code.require_file(
      Path.expand(
        "../../priv/repo/migrations/20260810130000_allow_zero_byte_snapshot_export_leases.exs",
        __DIR__
      )
    )
  end

  setup do
    previous = Application.get_env(:storyarn, @release_gate)
    Application.put_env(:storyarn, @release_gate, true)

    on_exit(fn -> restore_application_env(@release_gate, previous) end)

    :ok
  end

  test "a fresh installation passes the preflight and authorizes the historical migration task" do
    use_isolated_schema!()
    create_schema_migrations!()

    assert :migrated =
             Release.run_project_snapshot_migrations(Repo, fn ->
               assert :ok =
                        (&Release.assert_snapshot_lifecycle_migration_authorized!/0)
                        |> Task.async()
                        |> Task.await()

               :migrated
             end)

    assert_raise RuntimeError, ~r/must run through Storyarn.Release.migrate/, fn ->
      Release.assert_snapshot_lifecycle_migration_authorized!()
    end
  end

  test "the cutover barriers install idempotently and fence snapshot writes and live old workers" do
    prefix = use_isolated_schema!()
    create_schema_migrations!()
    Repo.query!("CREATE TABLE project_snapshots (id bigint PRIMARY KEY)")

    Repo.query!("""
    CREATE TABLE oban_jobs (
      id bigserial PRIMARY KEY,
      worker text NOT NULL,
      queue text NOT NULL,
      state text NOT NULL,
      args jsonb NOT NULL DEFAULT '{}'::jsonb
    )
    """)

    assert :ok =
             Release.run_project_snapshot_migrations(Repo, fn ->
               assert :ok = Release.ensure_project_snapshot_v2_cutover_barriers!(Repo, prefix)
               assert :ok = Release.ensure_project_snapshot_v2_cutover_barriers!(Repo, prefix)
             end)

    assert constraint_exists?("project_snapshots_cutover_quiescent")
    assert constraint_exists?("oban_jobs_snapshot_cutover_quiescent")

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query("INSERT INTO project_snapshots (id) VALUES (1)", [], mode: :savepoint)

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(
               "INSERT INTO oban_jobs (worker, queue, state) VALUES ($1, 'snapshots', 'available')",
               ["Storyarn.Workers.BuildProjectSnapshotWorker"],
               mode: :savepoint
             )

    assert {:ok, _result} =
             Repo.query(
               "INSERT INTO oban_jobs (worker, queue, state) VALUES ($1, 'snapshots', 'completed')",
               ["Storyarn.Workers.RestoreProjectWorker"],
               mode: :savepoint
             )
  end

  test "a pre-archive v1 snapshot blocks the release before the lifecycle migration or runner" do
    use_isolated_schema!()
    create_schema_migrations!()

    Repo.query!("""
    CREATE TABLE project_snapshots (
      format_version integer,
      mode text,
      object_prefix text
    )
    """)

    Repo.query!("""
    INSERT INTO project_snapshots (format_version, mode, object_prefix)
    VALUES (1, 'full', 'projects/1/snapshots/object-sets/v1/ready/LEGACYTOKEN00001')
    """)

    columns_before = table_columns("project_snapshots")

    assert_raise RuntimeError, ~r/requires an empty snapshot table/, fn ->
      Release.run_project_snapshot_migrations(Repo, fn ->
        send(self(), :migration_runner_called)
      end)
    end

    refute_received :migration_runner_called
    assert [[1, "full"]] = Repo.query!("SELECT format_version, mode FROM project_snapshots").rows
    assert table_columns("project_snapshots") == columns_before

    assert [[false]] =
             Repo.query!(
               "SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)",
               [@lifecycle_migration]
             ).rows
  end

  test "an archive-era v2 snapshot also blocks the empty-table cutover" do
    use_isolated_schema!()
    create_schema_migrations!()

    Repo.query!("""
    CREATE TABLE project_snapshots (
      format_version integer,
      mode text,
      object_prefix text,
      archive_storage_key text
    )
    """)

    Repo.query!("""
    INSERT INTO project_snapshots (format_version, mode, object_prefix, archive_storage_key)
    VALUES (
      2,
      'full',
      'projects/1/snapshots/archives/v2/ready/ARCHIVEV2TOKEN01',
      'projects/1/snapshots/archives/v2/ready/ARCHIVEV2TOKEN01/snapshot.zip'
    )
    """)

    assert_raise RuntimeError, ~r/requires an empty snapshot table/, fn ->
      Release.run_project_snapshot_migrations(Repo, fn -> :unreachable end)
    end
  end

  test "an already-applied v2-only migration bypasses the one-time preflight" do
    use_isolated_schema!()

    create_schema_migrations!([
      @storage_accounting_migration,
      @lifecycle_migration,
      @barrier_migration,
      @v2_only_migration
    ])

    Repo.query!("CREATE TABLE project_snapshots (format_version integer, mode text)")
    Repo.query!("INSERT INTO project_snapshots (format_version, mode) VALUES (2, 'full')")

    assert :migrated = Release.run_project_snapshot_migrations(Repo, fn -> :migrated end)
  end

  test "a v2-only marker without its destructive prerequisites fails closed" do
    use_isolated_schema!()
    create_schema_migrations!(@v2_only_migration)

    assert_raise RuntimeError, ~r/inconsistent_snapshot_v2_migration_history/, fn ->
      Release.run_project_snapshot_migrations(Repo, fn -> :unreachable end)
    end
  end

  test "production enforcement rejects a direct migration entrypoint" do
    assert_raise RuntimeError, ~r/must run through Storyarn.Release.migrate/, fn ->
      Release.assert_snapshot_lifecycle_migration_authorized!()
    end
  end

  test "the current-main barrier migration rejects a direct production migrator before DDL" do
    prefix = use_isolated_schema!()
    Repo.query!("CREATE TABLE project_snapshots (id bigint PRIMARY KEY)")
    Repo.query!("CREATE TABLE oban_jobs (id bigint PRIMARY KEY, worker text, state text)")

    assert_raise RuntimeError, ~r/must run through Storyarn.Release.migrate/, fn ->
      Runner.run(
        Repo,
        Repo.config(),
        @barrier_migration,
        AllowZeroByteSnapshotExportLeases,
        :forward,
        :up,
        :up,
        prefix: prefix,
        log: false
      )
    end

    assert snapshot_cutover_constraint_count(prefix) == 0
  end

  test "release authorization reaches an Ecto migration task and is always cleared" do
    prefix = use_isolated_schema!()
    create_schema_migrations!()

    assert :ok =
             Release.run_project_snapshot_migrations(Repo, fn ->
               fn ->
                 Runner.run(
                   Repo,
                   Repo.config(),
                   @authorization_probe_migration,
                   AuthorizationProbeMigration,
                   :forward,
                   :up,
                   :up,
                   prefix: prefix,
                   log: false
                 )
               end
               |> Task.async()
               |> Task.await()
             end)

    assert Repo.query!("SELECT to_regclass('snapshot_cutover_authorization_probe') IS NOT NULL").rows ==
             [[true]]

    assert_raise RuntimeError, ~r/must run through Storyarn.Release.migrate/, fn ->
      Release.assert_snapshot_lifecycle_migration_authorized!()
    end

    assert_raise RuntimeError, "probe failure", fn ->
      Release.run_project_snapshot_migrations(Repo, fn -> raise "probe failure" end)
    end

    assert_raise RuntimeError, ~r/must run through Storyarn.Release.migrate/, fn ->
      Release.assert_snapshot_lifecycle_migration_authorized!()
    end
  end

  test "test and development entrypoints remain ungated" do
    Application.put_env(:storyarn, @release_gate, false)
    assert :ok = Release.assert_snapshot_lifecycle_migration_authorized!()
  end

  test "the first destructive snapshot migration rejects direct production execution before mutation" do
    prefix = use_isolated_schema!()

    Repo.query!("CREATE TABLE project_snapshots (id bigint PRIMARY KEY, evidence text)")
    Repo.query!("CREATE TABLE entity_versions (id bigint PRIMARY KEY, evidence text)")
    Repo.query!("INSERT INTO project_snapshots (id, evidence) VALUES (1, 'snapshot-v1')")
    Repo.query!("INSERT INTO entity_versions (id, evidence) VALUES (1, 'entity-v1')")

    assert_raise RuntimeError, ~r/must run through Storyarn.Release.migrate/, fn ->
      Runner.run(
        Repo,
        Repo.config(),
        @storage_accounting_migration,
        AddSnapshotStorageAccounting,
        :forward,
        :change,
        :up,
        prefix: prefix,
        log: false
      )
    end

    assert [[1, "snapshot-v1"]] = Repo.query!("SELECT id, evidence FROM project_snapshots").rows
    assert [[1, "entity-v1"]] = Repo.query!("SELECT id, evidence FROM entity_versions").rows
    refute column_exists?("project_snapshots", "mode")
  end

  test "an explicit migration prefix differing from current_schema fails before touching either schema" do
    current_prefix = use_isolated_schema!()
    create_schema_migrations!()
    target_prefix = "release_snapshot_target_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{target_prefix}")
    Repo.query!("CREATE TABLE #{target_prefix}.project_snapshots (id bigint PRIMARY KEY, evidence text)")
    Repo.query!("INSERT INTO #{target_prefix}.project_snapshots VALUES (1, 'untouched')")

    public_constraints_before = snapshot_cutover_constraint_count("public")

    assert_raise RuntimeError, ~r/explicit prefix to match current_schema/, fn ->
      Release.run_project_snapshot_migrations(Repo, fn ->
        Runner.run(
          Repo,
          Repo.config(),
          @storage_accounting_migration,
          AddSnapshotStorageAccounting,
          :forward,
          :change,
          :up,
          prefix: target_prefix,
          log: false
        )
      end)
    end

    assert [[1, "untouched"]] =
             Repo.query!("SELECT id, evidence FROM #{target_prefix}.project_snapshots").rows

    assert snapshot_cutover_constraint_count(target_prefix) == 0
    assert snapshot_cutover_constraint_count(current_prefix) == 0
    assert snapshot_cutover_constraint_count("public") == public_constraints_before
  end

  test "the persistent barrier closes the write gap before the first destructive migration" do
    prefix = use_isolated_schema!()
    create_schema_migrations!()

    Repo.query!("CREATE TABLE project_snapshots (id bigint PRIMARY KEY)")

    Repo.query!("""
    CREATE TABLE oban_jobs (
      id bigint PRIMARY KEY,
      worker text,
      state text,
      args jsonb NOT NULL DEFAULT '{}'::jsonb
    )
    """)

    error =
      assert_raise Postgrex.Error, fn ->
        Release.run_project_snapshot_migrations(Repo, fn ->
          Repo.query!("INSERT INTO project_snapshots (id) VALUES (1)")

          Runner.run(
            Repo,
            Repo.config(),
            @storage_accounting_migration,
            AddSnapshotStorageAccounting,
            :forward,
            :change,
            :up,
            prefix: prefix,
            log: false
          )
        end)
      end

    assert error.postgres.code == :check_violation
    assert [] = Repo.query!("SELECT id FROM project_snapshots").rows
    refute column_exists?("project_snapshots", "mode")
  end

  defp use_isolated_schema! do
    prefix = "release_snapshot_cutover_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    Repo.query!("SELECT set_config('search_path', $1, true)", [prefix])
    prefix
  end

  defp create_schema_migrations!(versions \\ []) do
    Repo.query!("CREATE TABLE schema_migrations (version bigint PRIMARY KEY)")

    versions
    |> List.wrap()
    |> Enum.each(fn version ->
      Repo.query!("INSERT INTO schema_migrations (version) VALUES ($1)", [version])
    end)
  end

  defp column_exists?(table, column) do
    Repo.query!(
      """
      SELECT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name = $1 AND column_name = $2
      )
      """,
      [table, column]
    ).rows == [[true]]
  end

  defp table_columns(table) do
    Repo.query!(
      """
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = current_schema() AND table_name = $1
      ORDER BY ordinal_position
      """,
      [table]
    ).rows
  end

  defp constraint_exists?(constraint) do
    Repo.query!(
      "SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE connamespace = current_schema()::regnamespace AND conname = $1)",
      [constraint]
    ).rows == [[true]]
  end

  defp snapshot_cutover_constraint_count(prefix) do
    [[count]] =
      Repo.query!(
        """
        SELECT count(*)
        FROM pg_constraint AS constraint_row
        JOIN pg_namespace AS namespace_row ON namespace_row.oid = constraint_row.connamespace
        WHERE namespace_row.nspname = $1
          AND constraint_row.conname IN (
            'project_snapshots_cutover_quiescent',
            'oban_jobs_snapshot_cutover_quiescent'
          )
        """,
        [prefix]
      ).rows

    count
  end

  defp restore_application_env(key, nil), do: Application.delete_env(:storyarn, key)
  defp restore_application_env(key, value), do: Application.put_env(:storyarn, key, value)
end
