defmodule Storyarn.ReleaseSnapshotCutoverTest do
  use Storyarn.DataCase, async: false

  alias Ecto.Migration.Runner
  alias Storyarn.Platform.Release
  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.AddSnapshotStorageAccounting
  alias Storyarn.Repo.Migrations.AllowZeroByteSnapshotExportLeases
  alias Storyarn.Repo.Migrations.FenceStorageCleanupWriters
  alias Storyarn.Repo.Migrations.MakeProjectSnapshotsV2Only

  @storage_accounting_migration 20_260_804_120_000
  @lifecycle_migration 20_260_805_130_000
  @barrier_migration 20_260_810_130_000
  @v2_only_migration 20_260_811_180_000
  @scaffolding_cleanup_migration 20_260_812_100_000
  @exact_multipart_cleanup_migration 20_260_903_190_000
  @release_gate :enforce_snapshot_lifecycle_release_gate
  @cleanup_authorization_config :project_snapshot_scaffolding_cleanup_authorization
  @cleanup_authorization "20260812100000"
  @exact_cleanup_authorization_config :exact_multipart_cleanup_cutover_authorization
  @exact_cleanup_authorization "20260903190000"
  @exact_cleanup_queues ~w(
    imports
    imports_maintenance
    snapshot_archives
    snapshot_restores
    snapshot_imports
    snapshots_maintenance
    storage_cleanup
    future_storage_writer
  )
  @authorization_probe_migration 90_000_000_000_001
  @cleanup_authorization_probe_migration 90_000_000_000_002
  @exact_cleanup_authorization_probe_migration 90_000_000_000_003

  defmodule MigrationAuthorizationProbe do
    @moduledoc false

    def authorized?(authorization_key) do
      Process.get(authorization_key, false) == true or
        Enum.any?(
          List.wrap(Process.get(:"$callers")),
          &authorized_caller?(&1, authorization_key)
        )
    end

    defp authorized_caller?(pid, authorization_key) when is_pid(pid) and node(pid) == node() do
      case Process.info(pid, :dictionary) do
        {:dictionary, dictionary} ->
          List.keyfind(dictionary, authorization_key, 0) == {authorization_key, true}

        nil ->
          false
      end
    end

    defp authorized_caller?(_pid, _authorization_key), do: false
  end

  defmodule AuthorizationProbeMigration do
    @moduledoc false
    use Ecto.Migration

    alias Storyarn.ReleaseSnapshotCutoverTest.MigrationAuthorizationProbe

    @authorization_key :storyarn_snapshot_cutover_authorized_v1

    def up do
      if !MigrationAuthorizationProbe.authorized?(@authorization_key),
        do: raise("snapshot lifecycle authorization missing")

      execute("CREATE TABLE snapshot_cutover_authorization_probe (id bigint PRIMARY KEY)")
    end
  end

  defmodule CleanupAuthorizationProbeMigration do
    @moduledoc false
    use Ecto.Migration

    alias Storyarn.ReleaseSnapshotCutoverTest.MigrationAuthorizationProbe

    @authorization_key :storyarn_snapshot_scaffolding_cleanup_authorized_v1

    def up do
      if !MigrationAuthorizationProbe.authorized?(@authorization_key),
        do: raise("cleanup authorization missing")

      execute("CREATE TABLE snapshot_scaffolding_cleanup_authorization_probe (id bigint PRIMARY KEY)")
    end
  end

  defmodule ExactCleanupAuthorizationProbeMigration do
    @moduledoc false
    use Ecto.Migration

    alias Storyarn.ReleaseSnapshotCutoverTest.MigrationAuthorizationProbe

    @authorization_key :storyarn_exact_multipart_cleanup_cutover_authorized_v1

    def up do
      if !MigrationAuthorizationProbe.authorized?(@authorization_key),
        do: raise("exact multipart cleanup authorization missing")

      execute("CREATE TABLE exact_multipart_cleanup_authorization_probe (id bigint PRIMARY KEY)")
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

  if !Code.ensure_loaded?(MakeProjectSnapshotsV2Only) do
    Code.require_file(
      Path.expand(
        "../../priv/repo/migrations/20260811180000_make_project_snapshots_v2_only.exs",
        __DIR__
      )
    )
  end

  if !Code.ensure_loaded?(FenceStorageCleanupWriters) do
    Code.require_file(
      Path.expand(
        "../../priv/repo/migrations/20260903190000_fence_storage_cleanup_writers.exs",
        __DIR__
      )
    )
  end

  setup do
    previous = Application.get_env(:storyarn, @release_gate)
    previous_cleanup_authorization = Application.get_env(:storyarn, @cleanup_authorization_config)

    previous_exact_cleanup_authorization =
      Application.get_env(:storyarn, @exact_cleanup_authorization_config)

    Application.put_env(:storyarn, @release_gate, true)
    Application.delete_env(:storyarn, @cleanup_authorization_config)

    Application.put_env(
      :storyarn,
      @exact_cleanup_authorization_config,
      @exact_cleanup_authorization
    )

    on_exit(fn ->
      restore_application_env(@release_gate, previous)
      restore_application_env(@cleanup_authorization_config, previous_cleanup_authorization)

      restore_application_env(
        @exact_cleanup_authorization_config,
        previous_exact_cleanup_authorization
      )
    end)

    :ok
  end

  test "a fresh installation authorizes the historical migration task" do
    use_isolated_schema!()
    create_schema_migrations!()

    with_exact_cleanup_authorization(nil, fn ->
      assert :migrated = Release.run_project_snapshot_migrations(Repo, fn -> :migrated end)
    end)
  end

  test "a non-empty database requires the exact one-release multipart cleanup authorization" do
    use_isolated_schema!()

    create_schema_migrations!([
      @storage_accounting_migration,
      @lifecycle_migration,
      @barrier_migration,
      @v2_only_migration,
      @scaffolding_cleanup_migration
    ])

    Repo.query!("CREATE TABLE exact_multipart_cutover_evidence (id bigint PRIMARY KEY)")

    for invalid <- [nil, "wrong"] do
      with_exact_cleanup_authorization(invalid, fn ->
        assert_raise RuntimeError, ~r/EXACT_MULTIPART_CLEANUP_CUTOVER_AUTHORIZATION/, fn ->
          Release.run_project_snapshot_migrations(Repo, fn -> :unreachable end)
        end
      end)
    end

    assert :migrated = Release.run_project_snapshot_migrations(Repo, fn -> :migrated end)
  end

  test "an already-applied exact multipart cleanup no longer requires authorization" do
    use_isolated_schema!()

    create_schema_migrations!([
      @storage_accounting_migration,
      @lifecycle_migration,
      @barrier_migration,
      @v2_only_migration,
      @scaffolding_cleanup_migration,
      @exact_multipart_cleanup_migration
    ])

    Repo.query!("CREATE TABLE exact_multipart_cutover_evidence (id bigint PRIMARY KEY)")

    with_exact_cleanup_authorization(nil, fn ->
      assert :migrated = Release.run_project_snapshot_migrations(Repo, fn -> :migrated end)
    end)
  end

  test "the applied FSM migration does not bypass the additive writer-fence cutover" do
    use_isolated_schema!()

    create_schema_migrations!([
      @storage_accounting_migration,
      @lifecycle_migration,
      @barrier_migration,
      @v2_only_migration,
      @scaffolding_cleanup_migration,
      20_260_903_133_000
    ])

    with_exact_cleanup_authorization("20260903133000", fn ->
      assert_raise RuntimeError, ~r/EXACT_MULTIPART_CLEANUP_CUTOVER_AUTHORIZATION=20260903190000/, fn ->
        Release.run_project_snapshot_migrations(Repo, fn -> :unreachable end)
      end
    end)
  end

  test "incremental writer fencing backfills ownership without resetting in-flight FSM state" do
    prefix = use_isolated_schema!()

    create_schema_migrations!([
      @storage_accounting_migration,
      @lifecycle_migration,
      @barrier_migration,
      @v2_only_migration,
      @scaffolding_cleanup_migration,
      20_260_903_133_000
    ])

    Repo.query!(
      "CREATE TABLE storage_cleanup_requests (LIKE public.storage_cleanup_requests INCLUDING DEFAULTS INCLUDING CONSTRAINTS, PRIMARY KEY (id))"
    )

    Repo.query!(
      "CREATE TABLE storage_cleanup_multipart_uploads (LIKE public.storage_cleanup_multipart_uploads INCLUDING DEFAULTS INCLUDING CONSTRAINTS, PRIMARY KEY (id), FOREIGN KEY (cleanup_request_id) REFERENCES storage_cleanup_requests(id) ON DELETE CASCADE)"
    )

    Repo.query!("CREATE TABLE oban_jobs (id bigint PRIMARY KEY, state text NOT NULL)")

    Repo.query!(
      "CREATE TABLE storage_cleanup_ownership_receipts (cleanup_request_id bigint PRIMARY KEY, storage_keys text[] NOT NULL CHECK (cardinality(storage_keys) > 0), recorded_at timestamp NOT NULL)"
    )

    Repo.query!(
      "CREATE TABLE storage_cleanup_ownership_namespaces (cleanup_request_id bigint NOT NULL REFERENCES storage_cleanup_ownership_receipts(cleanup_request_id) ON DELETE RESTRICT, object_prefix text NOT NULL, PRIMARY KEY (cleanup_request_id, object_prefix))"
    )

    key = "workspace-snapshot-imports/v1/1/00000000-0000-0000-0000-000000000001/snapshot.zip"

    Repo.query!(
      """
      INSERT INTO storage_cleanup_requests
        (id, storage_keys, owner_kind, provider_namespace_fingerprint,
         multipart_cleanup_phase, multipart_cleanup_generation, multipart_cleanup_cursor,
         multipart_cleanup_inventory_complete, multipart_cleanup_claim_token,
         multipart_cleanup_claim_expires_at, inserted_at, updated_at)
      VALUES (1, ARRAY[$1]::text[], 'storage_compensation', repeat('a', 64),
              'delete', 7, 2, true, '00000000-0000-0000-0000-000000000002',
              now() + interval '10 minutes', now(), now())
      """,
      [key]
    )

    Repo.query!(
      """
      INSERT INTO storage_cleanup_multipart_uploads
        (id, cleanup_request_id, storage_key, upload_id, reference_digest,
         last_aborted_generation, last_absent_generation, inserted_at, updated_at)
      VALUES (1, 1, $1, 'retained-upload-id', repeat('b', 64), 7, 6, now(), now())
      """,
      [key]
    )

    before_request = Repo.query!("SELECT row_to_json(request) FROM storage_cleanup_requests AS request").rows
    before_upload = Repo.query!("SELECT row_to_json(upload) FROM storage_cleanup_multipart_uploads AS upload").rows

    Release.run_project_snapshot_migrations(Repo, fn ->
      Runner.run(Repo, Repo.config(), @exact_multipart_cleanup_migration, FenceStorageCleanupWriters, :forward, :up, :up,
        prefix: prefix,
        log: false
      )
    end)

    assert Repo.query!("SELECT row_to_json(request) FROM storage_cleanup_requests AS request").rows == before_request

    assert Repo.query!("SELECT row_to_json(upload) FROM storage_cleanup_multipart_uploads AS upload").rows ==
             before_upload

    assert Repo.query!("SELECT cleanup_request_id, storage_keys FROM storage_cleanup_ownership_receipts").rows == [
             [1, [key]]
           ]

    assert Repo.query!(
             "SELECT to_regclass('storage_cleanup_requests_storage_keys_gin_idx') IS NOT NULL, to_regclass('storage_cleanup_ownership_receipts_storage_keys_gin_idx') IS NOT NULL"
           ).rows == [[true, true]]
  end

  test "a mixed-case prefix reaches the frozen migration ABI and applies real DDL" do
    prefix = use_mixed_case_schema!()
    create_schema_migrations!(@storage_accounting_migration)

    Repo.query!("CREATE TABLE project_snapshots (id bigint PRIMARY KEY)")
    Repo.query!("CREATE TABLE entity_versions (id bigint PRIMARY KEY)")

    Repo.query!("""
    CREATE TABLE oban_jobs (
      id bigserial PRIMARY KEY,
      worker text NOT NULL,
      queue text NOT NULL,
      state text NOT NULL,
      args jsonb NOT NULL DEFAULT '{}'::jsonb
    )
    """)

    Repo.query!("""
    CREATE TABLE workspace_storage_reservations
    (LIKE public.workspace_storage_reservations INCLUDING ALL)
    """)

    assert :ok =
             Runner.run(
               Repo,
               Repo.config(),
               @barrier_migration,
               AllowZeroByteSnapshotExportLeases,
               :forward,
               :down,
               :down,
               prefix: prefix,
               log: false
             )

    Repo.query!("""
    ALTER TABLE project_snapshots
    ADD CONSTRAINT project_snapshots_cutover_quiescent CHECK (FALSE)
    """)

    Repo.query!("""
    ALTER TABLE oban_jobs
    ADD CONSTRAINT oban_jobs_snapshot_cutover_quiescent
    CHECK (
      state NOT IN ('available', 'scheduled', 'executing', 'retryable') OR
      worker NOT IN (
        'Storyarn.Workers.BuildProjectSnapshotWorker',
        'Storyarn.Workers.DailySnapshotWorker',
        'Storyarn.Workers.SnapshotRetentionWorker',
        'Storyarn.Workers.RestoreProjectWorker',
        'Storyarn.Workers.RecoverProjectWorker'
      )
    )
    """)

    with_release_gate(false, fn ->
      assert :ok =
               Release.run_project_snapshot_migrations(Repo, fn ->
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
               end)
    end)

    assert constraint_exists?("project_snapshots_cutover_quiescent")
    assert constraint_exists?("oban_jobs_snapshot_cutover_quiescent")

    assert constraint_exists?("workspace_storage_reservations_zero_byte_snapshot_export_lease")
  end

  test "a completed v2-only rollout requires the exact one-release cleanup authorization" do
    use_isolated_schema!()

    create_schema_migrations!([
      @storage_accounting_migration,
      @lifecycle_migration,
      @barrier_migration,
      @v2_only_migration
    ])

    Repo.query!("CREATE TABLE project_snapshots (format_version integer, mode text)")
    Repo.query!("INSERT INTO project_snapshots (format_version, mode) VALUES (2, 'full')")

    assert_raise RuntimeError, ~r/PROJECT_SNAPSHOT_SCAFFOLDING_CLEANUP_AUTHORIZATION/, fn ->
      Release.run_project_snapshot_migrations(Repo, fn -> :unreachable end)
    end

    with_cleanup_authorization("wrong", fn ->
      assert_raise RuntimeError, ~r/PROJECT_SNAPSHOT_SCAFFOLDING_CLEANUP_AUTHORIZATION/, fn ->
        Release.run_project_snapshot_migrations(Repo, fn -> :unreachable end)
      end
    end)

    with_cleanup_authorization(@cleanup_authorization, fn ->
      assert :migrated = Release.run_project_snapshot_migrations(Repo, fn -> :migrated end)
    end)
  end

  test "the cleanup authorization cannot skip the preceding v2-only release" do
    use_isolated_schema!()
    create_schema_migrations!(@storage_accounting_migration)

    with_cleanup_authorization(@cleanup_authorization, fn ->
      assert_raise RuntimeError, ~r/deploy the preceding release first/, fn ->
        Release.run_project_snapshot_migrations(Repo, fn -> :unreachable end)
      end
    end)
  end

  test "an already-applied cleanup no longer requires the temporary authorization" do
    use_isolated_schema!()

    create_schema_migrations!([
      @storage_accounting_migration,
      @lifecycle_migration,
      @barrier_migration,
      @v2_only_migration,
      @scaffolding_cleanup_migration
    ])

    assert :migrated = Release.run_project_snapshot_migrations(Repo, fn -> :migrated end)
  end

  test "a v2-only marker without its destructive prerequisites fails closed" do
    use_isolated_schema!()
    create_schema_migrations!(@v2_only_migration)

    assert_raise RuntimeError, ~r/inconsistent_snapshot_v2_migration_history/, fn ->
      Release.run_project_snapshot_migrations(Repo, fn -> :unreachable end)
    end
  end

  test "a cleanup marker without its destructive prerequisites fails before migration DDL" do
    use_isolated_schema!()

    migration_history = [
      @storage_accounting_migration,
      @lifecycle_migration,
      @barrier_migration,
      @scaffolding_cleanup_migration
    ]

    create_schema_migrations!(migration_history)
    Repo.query!("CREATE TABLE release_preflight_evidence (id bigint PRIMARY KEY, evidence text)")
    Repo.query!("INSERT INTO release_preflight_evidence (id, evidence) VALUES (1, 'preserved')")

    assert_raise RuntimeError, ~r/inconsistent_snapshot_scaffolding_cleanup_history/, fn ->
      Release.run_project_snapshot_migrations(Repo, fn ->
        send(self(), :migration_runner_invoked)
        Repo.query!("ALTER TABLE release_preflight_evidence ADD COLUMN mutated boolean")
      end)
    end

    refute_received :migration_runner_invoked
    refute column_exists?("release_preflight_evidence", "mutated")

    assert Repo.query!("SELECT id, evidence FROM release_preflight_evidence").rows == [
             [1, "preserved"]
           ]

    assert Repo.query!("SELECT version FROM schema_migrations ORDER BY version").rows ==
             Enum.map(Enum.sort(migration_history), &[&1])
  end

  test "the current-main barrier migration rejects a direct production migrator before DDL" do
    prefix = use_isolated_schema!()
    Repo.query!("CREATE TABLE project_snapshots (id bigint PRIMARY KEY)")
    Repo.query!("CREATE TABLE oban_jobs (id bigint PRIMARY KEY, worker text, state text)")

    assert_raise RuntimeError, ~r/must run through \/app\/bin\/migrate/, fn ->
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

  test "the final v2-only migration rejects a direct production migrator before DDL" do
    prefix = use_isolated_schema!()

    assert_raise RuntimeError, ~r/must run through \/app\/bin\/migrate/, fn ->
      Runner.run(
        Repo,
        Repo.config(),
        @v2_only_migration,
        MakeProjectSnapshotsV2Only,
        :forward,
        :up,
        :up,
        prefix: prefix,
        log: false
      )
    end

    assert snapshot_cutover_constraint_count(prefix) == 0
  end

  test "cutover migrations do not call live release-task functions" do
    migration_files = [
      "20260804120000_add_snapshot_storage_accounting.exs",
      "20260805130000_harden_snapshot_lifecycle_cleanup.exs",
      "20260810130000_allow_zero_byte_snapshot_export_leases.exs",
      "20260811180000_make_project_snapshots_v2_only.exs",
      "20260812100000_remove_transitional_snapshot_cutover_scaffolding.exs",
      "20260903190000_fence_storage_cleanup_writers.exs"
    ]

    for migration_file <- migration_files do
      source =
        "../../priv/repo/migrations/#{migration_file}"
        |> Path.expand(__DIR__)
        |> File.read!()

      refute source =~ "Storyarn.Platform.Release.",
             "#{migration_file} must remain independent of live release-task functions"
    end
  end

  test "the exact cleanup migration preserves the retired snapshot-key ratchet" do
    source =
      "../../priv/repo/migrations/20260903190000_fence_storage_cleanup_writers.exs"
      |> Path.expand(__DIR__)
      |> File.read!()

    assert source =~ "/snapshots/object-sets/v1/"
    assert source =~ "/storage-reservations/v1/linked-to-full-conversion/"
    assert source =~ "regexp_replace(raw_key.storage_key, '^__storyarn_force_delete__:', '')"
    assert source =~ "retired v1/linked snapshot cleanup ownership is not accepted"
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

               fn ->
                 Runner.run(
                   Repo,
                   Repo.config(),
                   @cleanup_authorization_probe_migration,
                   CleanupAuthorizationProbeMigration,
                   :forward,
                   :up,
                   :up,
                   prefix: prefix,
                   log: false
                 )
               end
               |> Task.async()
               |> Task.await()

               fn ->
                 Runner.run(
                   Repo,
                   Repo.config(),
                   @exact_cleanup_authorization_probe_migration,
                   ExactCleanupAuthorizationProbeMigration,
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

    assert Repo.query!("SELECT to_regclass('snapshot_scaffolding_cleanup_authorization_probe') IS NOT NULL").rows == [
             [true]
           ]

    assert Repo.query!("SELECT to_regclass('exact_multipart_cleanup_authorization_probe') IS NOT NULL").rows == [
             [true]
           ]

    refute Process.get(:storyarn_snapshot_scaffolding_cleanup_authorized_v1, false)
    refute Process.get(:storyarn_exact_multipart_cleanup_cutover_authorized_v1, false)

    insert_migration_versions!([
      @storage_accounting_migration,
      @lifecycle_migration,
      @barrier_migration,
      @v2_only_migration
    ])

    assert_raise RuntimeError, "probe failure", fn ->
      with_cleanup_authorization(@cleanup_authorization, fn ->
        Release.run_project_snapshot_migrations(Repo, fn -> raise "probe failure" end)
      end)
    end

    refute Process.get(:storyarn_snapshot_scaffolding_cleanup_authorized_v1, false)
    refute Process.get(:storyarn_exact_multipart_cleanup_cutover_authorized_v1, false)
  end

  test "the exact multipart cleanup migration rejects direct production execution before DDL" do
    prefix = use_isolated_schema!()
    Repo.query!("CREATE TABLE storage_cleanup_requests (id bigint PRIMARY KEY)")

    assert_raise RuntimeError, ~r/must run through \/app\/bin\/migrate/, fn ->
      Runner.run(
        Repo,
        Repo.config(),
        @exact_multipart_cleanup_migration,
        FenceStorageCleanupWriters,
        :forward,
        :up,
        :up,
        prefix: prefix,
        log: false
      )
    end

    assert Repo.query!("SELECT to_regclass('storage_cleanup_requests_storage_keys_gin_idx') IS NULL").rows == [[true]]
  end

  test "the exact multipart cleanup rollback also rejects direct production execution" do
    prefix = use_isolated_schema!()

    assert_raise RuntimeError, ~r/must run through \/app\/bin\/migrate/, fn ->
      Runner.run(
        Repo,
        Repo.config(),
        @exact_multipart_cleanup_migration,
        FenceStorageCleanupWriters,
        :backward,
        :down,
        :down,
        prefix: prefix,
        log: false
      )
    end
  end

  test "the release-authorized exact multipart cleanup rollback is irreversible" do
    prefix = use_isolated_schema!()
    create_schema_migrations!()

    assert_raise Ecto.MigrationError, ~r/is irreversible/, fn ->
      Release.run_project_snapshot_migrations(Repo, fn ->
        Runner.run(
          Repo,
          Repo.config(),
          @exact_multipart_cleanup_migration,
          FenceStorageCleanupWriters,
          :backward,
          :down,
          :down,
          prefix: prefix,
          log: false
        )
      end)
    end
  end

  for queue <- @exact_cleanup_queues do
    test "the exact multipart cleanup migration rejects an executing #{queue} job before DDL" do
      queue = unquote(queue)
      prefix = use_isolated_schema!()

      create_schema_migrations!([
        @storage_accounting_migration,
        @lifecycle_migration,
        @barrier_migration,
        @v2_only_migration,
        @scaffolding_cleanup_migration
      ])

      Repo.query!("CREATE TABLE storage_cleanup_requests (id bigint PRIMARY KEY)")

      Repo.query!("""
      CREATE TABLE oban_jobs (
        id bigserial PRIMARY KEY,
        queue text NOT NULL,
        state text NOT NULL
      )
      """)

      Repo.query!("INSERT INTO oban_jobs (queue, state) VALUES ($1, 'executing')", [queue])

      assert_raise Ecto.MigrationError, ~r/requires no executing jobs/, fn ->
        Release.run_project_snapshot_migrations(Repo, fn ->
          Runner.run(
            Repo,
            Repo.config(),
            @exact_multipart_cleanup_migration,
            FenceStorageCleanupWriters,
            :forward,
            :up,
            :up,
            prefix: prefix,
            log: false
          )
        end)
      end

      assert Repo.query!("SELECT to_regclass('storage_cleanup_requests_storage_keys_gin_idx') IS NULL").rows == [[true]]
    end
  end

  test "the first destructive snapshot migration rejects direct production execution before mutation" do
    prefix = use_isolated_schema!()

    Repo.query!("CREATE TABLE project_snapshots (id bigint PRIMARY KEY, evidence text)")
    Repo.query!("CREATE TABLE entity_versions (id bigint PRIMARY KEY, evidence text)")
    Repo.query!("INSERT INTO project_snapshots (id, evidence) VALUES (1, 'snapshot-v1')")
    Repo.query!("INSERT INTO entity_versions (id, evidence) VALUES (1, 'entity-v1')")

    assert_raise RuntimeError, ~r/must run through \/app\/bin\/migrate/, fn ->
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

  defp use_isolated_schema! do
    prefix = "release_snapshot_cutover_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    Repo.query!("SELECT set_config('search_path', $1, true)", [prefix])
    prefix
  end

  defp use_mixed_case_schema! do
    prefix = "ReleaseSnapshotCutover#{System.unique_integer([:positive])}"
    Repo.query!(~s(CREATE SCHEMA "#{prefix}"))
    Repo.query!("SELECT set_config('search_path', $1, true)", [~s("#{prefix}")])
    prefix
  end

  defp create_schema_migrations!(versions \\ []) do
    Repo.query!("CREATE TABLE schema_migrations (version bigint PRIMARY KEY)")
    insert_migration_versions!(versions)
  end

  defp insert_migration_versions!(versions) do
    versions
    |> List.wrap()
    |> Enum.each(fn version ->
      Repo.query!("INSERT INTO schema_migrations (version) VALUES ($1) ON CONFLICT DO NOTHING", [version])
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

  defp constraint_exists?(constraint) do
    Repo.query!(
      """
      SELECT EXISTS (
        SELECT 1
        FROM pg_constraint AS constraint_row
        JOIN pg_namespace AS namespace_row
          ON namespace_row.oid = constraint_row.connamespace
        WHERE namespace_row.nspname = current_schema()
          AND constraint_row.conname = $1
      )
      """,
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
            'oban_jobs_snapshot_cutover_quiescent',
            'entity_versions_cutover_quiescent'
          )
        """,
        [prefix]
      ).rows

    count
  end

  defp with_release_gate(value, fun) do
    with_application_env(@release_gate, value, fun)
  end

  defp with_cleanup_authorization(value, fun) do
    with_application_env(@cleanup_authorization_config, value, fun)
  end

  defp with_exact_cleanup_authorization(value, fun) do
    with_application_env(@exact_cleanup_authorization_config, value, fun)
  end

  defp with_application_env(key, value, fun) do
    previous = Application.get_env(:storyarn, key, :missing)
    Application.put_env(:storyarn, key, value)

    try do
      fun.()
    after
      restore_application_env(key, previous)
    end
  end

  defp restore_application_env(key, :missing), do: Application.delete_env(:storyarn, key)
  defp restore_application_env(key, nil), do: Application.delete_env(:storyarn, key)
  defp restore_application_env(key, value), do: Application.put_env(:storyarn, key, value)
end
