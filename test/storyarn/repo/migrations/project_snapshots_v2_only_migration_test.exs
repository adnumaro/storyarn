defmodule Storyarn.Repo.Migrations.ProjectSnapshotsV2OnlyMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.MakeProjectSnapshotsV2Only

  @migration_version 20_260_811_180_000
  if !Code.ensure_loaded?(MakeProjectSnapshotsV2Only) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260811180000_make_project_snapshots_v2_only.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "project_snapshots_v2_only_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    create_schema!(prefix)
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    %{prefix: prefix}
  end

  test "preserves v2 rows, retires v1 semantics, and enforces full archive snapshots", %{
    prefix: prefix
  } do
    assert {:ok, _result} = insert_queued_v2(prefix, "ARCHIVEV2TOKEN01")
    insert_terminal_v1_cleanup_evidence!(prefix)

    Repo.query!("""
    INSERT INTO #{prefix}.oban_jobs (worker, queue, state)
    VALUES ('Storyarn.Workers.BuildProjectSnapshotWorker', 'snapshots', 'completed')
    """)

    assert :ok = run_migration(:up, prefix)

    assert query_rows!("SELECT count(*) FROM #{prefix}.project_snapshots") == [[1]]
    assert query_rows!("SELECT count(*) FROM #{prefix}.oban_jobs") == [[1]]
    assert column_exists?(prefix, "project_snapshots", "project_storage_key")
    assert column_exists?(prefix, "workspace_storage_reservations", "source_asset_count")
    assert column_not_null?(prefix, "project_snapshots", "format_version")
    assert column_not_null?(prefix, "project_snapshots", "mode")
    assert column_default(prefix, "project_snapshots", "format_version") == "2"
    assert column_default(prefix, "project_snapshots", "mode") == "'full'::character varying"

    assert constraint_definition(prefix, "project_snapshots_object_format_version") =~
             "format_version = 2"

    refute constraint_definition(prefix, "project_snapshots_object_target") =~ "object-sets"
    refute constraint_definition(prefix, "project_snapshots_mode") =~ "linked"

    assert constraint_definition(prefix, "workspace_storage_reservations_kind") =~
             "snapshot_build"

    refute constraint_definition(prefix, "workspace_storage_reservations_kind") =~
             "linked_to_full_conversion"

    assert query_rows!("SELECT count(*) FROM #{prefix}.storage_cleanup_ownership_receipts") == [[1]]
    assert query_rows!("SELECT count(*) FROM #{prefix}.storage_cleanup_ownership_namespaces") == [[1]]

    assert {:ok, _result} = insert_queued_v2(prefix, "ARCHIVEV2TOKEN02", defaults?: true)

    assert_check_violation(fn ->
      insert_queued_v2(prefix, "ARCHIVEV2TOKEN03", format_version: 1)
    end)

    assert_check_violation(fn ->
      insert_queued_v2(prefix, "ARCHIVEV2TOKEN04", mode: "linked")
    end)
  end

  test "fails before DDL for every live v1 or linked ownership surface", %{prefix: prefix} do
    legacy_cases = [
      {
        "snapshot row",
        fn ->
          Repo.query!("""
          INSERT INTO #{prefix}.project_snapshots (project_id, format_version, mode)
          VALUES (1, 1, 'full')
          """)
        end,
        fn -> Repo.query!("DELETE FROM #{prefix}.project_snapshots") end
      },
      {
        "publication claim",
        fn ->
          Repo.query!("""
          INSERT INTO #{prefix}.snapshot_object_publication_claims (object_prefix)
          VALUES ('projects/1/snapshots/object-sets/v1/ready/LEGACYTOKEN00001')
          """)
        end,
        fn -> Repo.query!("DELETE FROM #{prefix}.snapshot_object_publication_claims") end
      },
      {
        "linked conversion reservation",
        fn ->
          Repo.query!("""
          INSERT INTO #{prefix}.workspace_storage_reservations (kind, cleanup_object_prefix)
          VALUES (
            'linked_to_full_conversion',
            'projects/1/snapshots/object-sets/v1/ready/LEGACYTOKEN00001'
          )
          """)
        end,
        fn -> Repo.query!("DELETE FROM #{prefix}.workspace_storage_reservations") end
      },
      {
        "snapshot cleanup intent",
        fn ->
          Repo.query!("""
          INSERT INTO #{prefix}.snapshot_cleanup_intents (mode, ready_prefix, staging_prefix)
          VALUES (
            'full',
            'projects/1/snapshots/object-sets/v1/ready/LEGACYTOKEN00001',
            'projects/1/snapshots/object-sets/v1/staging/LEGACYTOKEN00001'
          )
          """)
        end,
        fn -> Repo.query!("DELETE FROM #{prefix}.snapshot_cleanup_intents") end
      },
      {
        "outstanding storage cleanup",
        fn ->
          Repo.query!("""
          INSERT INTO #{prefix}.storage_cleanup_requests (storage_keys)
          VALUES (ARRAY[
            'projects/1/snapshots/object-sets/v1/ready/LEGACYTOKEN00001/project.json'
          ])
          """)
        end,
        fn -> Repo.query!("DELETE FROM #{prefix}.storage_cleanup_requests") end
      },
      {
        "queued canonical build",
        fn ->
          Repo.query!("""
          INSERT INTO #{prefix}.oban_jobs (worker, queue, state)
          VALUES (
            'Storyarn.Workers.BuildProjectSnapshotWorker',
            'snapshot_archives',
            'available'
          )
          """)
        end,
        fn -> Repo.query!("DELETE FROM #{prefix}.oban_jobs") end
      },
      {
        "active build outside the known queues",
        fn ->
          Repo.query!("""
          INSERT INTO #{prefix}.oban_jobs (worker, queue, state)
          VALUES (
            'Storyarn.Workers.BuildProjectSnapshotWorker',
            'misrouted_snapshots',
            'executing'
          )
          """)
        end,
        fn -> Repo.query!("DELETE FROM #{prefix}.oban_jobs") end
      },
      {
        "active generic cleanup carrying retired snapshot keys",
        fn ->
          Repo.query!("""
          INSERT INTO #{prefix}.oban_jobs (worker, queue, state, args)
          VALUES (
            'Storyarn.Workers.DeleteStorageObjectsWorker',
            'storage_cleanup',
            'retryable',
            '{"storage_keys":["projects/1/snapshots/object-sets/v1/ready/LEGACYTOKEN00001/project.json"]}'::jsonb
          )
          """)
        end,
        fn -> Repo.query!("DELETE FROM #{prefix}.oban_jobs") end
      }
    ]

    for {label, seed!, clear!} <- legacy_cases do
      seed!.()

      error = assert_raise Postgrex.Error, fn -> run_migration(:up, prefix) end

      assert error.postgres.code == :object_not_in_prerequisite_state,
             "expected #{label} to block the migration"

      assert error.postgres.pg_code == "55000"
      assert column_exists?(prefix, "project_snapshots", "project_storage_key")
      assert column_exists?(prefix, "workspace_storage_reservations", "source_asset_count")

      clear!.()
    end

    assert :ok = run_migration(:up, prefix)
  end

  test "terminal legacy audit evidence survives but new v1 cleanup is rejected", %{prefix: prefix} do
    insert_terminal_v1_cleanup_evidence!(prefix)
    assert :ok = run_migration(:up, prefix)

    assert_check_violation(fn ->
      Repo.query(
        """
        INSERT INTO #{prefix}.storage_cleanup_requests (storage_keys)
        VALUES (ARRAY[
          'projects/1/snapshots/object-sets/v1/ready/LEGACYTOKEN00002/project.json'
        ])
        """,
        [],
        mode: :savepoint
      )
    end)

    assert_check_violation(fn ->
      Repo.query(
        """
        INSERT INTO #{prefix}.storage_cleanup_requests (storage_keys)
        VALUES (ARRAY[
          'projects/1/snapshots/archives/v2/ready/ARCHIVEV2TOKEN05/snapshot.zip',
          'projects/1/snapshots/object-sets/v1/ready/LEGACYTOKEN00002/project.json'
        ])
        """,
        [],
        mode: :savepoint
      )
    end)

    assert query_rows!("SELECT count(*) FROM #{prefix}.storage_cleanup_ownership_receipts") == [[1]]

    assert {:ok, %Postgrex.Result{rows: [[v2_request_id]]}} =
             Repo.query("""
             INSERT INTO #{prefix}.storage_cleanup_requests (storage_keys)
             VALUES (ARRAY[
               'projects/1/snapshots/archives/v2/ready/ARCHIVEV2TOKEN05/snapshot.zip'
             ])
             RETURNING id
             """)

    assert query_rows!("""
           SELECT count(*)
           FROM #{prefix}.storage_cleanup_ownership_receipts
           WHERE cleanup_request_id = #{v2_request_id}
           """) == [[1]]

    assert query_rows!("""
           SELECT object_prefix
           FROM #{prefix}.storage_cleanup_ownership_namespaces
           WHERE cleanup_request_id = #{v2_request_id}
           """) == [["projects/1/snapshots/archives/v2/ready/ARCHIVEV2TOKEN05"]]
  end

  test "rollback is explicitly irreversible", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)

    assert_raise Ecto.MigrationError, ~r/irreversible/, fn ->
      run_migration(:down, prefix)
    end

    assert column_exists?(prefix, "project_snapshots", "project_storage_key")
  end

  defp create_schema!(prefix) do
    Repo.query!("""
    CREATE TABLE #{prefix}.project_snapshots (
      id bigserial PRIMARY KEY,
      project_id bigint,
      format_version integer,
      mode varchar(255),
      lifecycle_state varchar(255),
      integrity_state varchar(255),
      object_prefix varchar(500),
      project_storage_key varchar(520),
      archive_storage_key varchar(520),
      archive_size_bytes bigint,
      archive_checksum varchar(64),
      project_size_bytes bigint,
      project_checksum varchar(64),
      manifest_storage_key varchar(520),
      manifest_size_bytes bigint,
      manifest_checksum varchar(64),
      total_size_bytes bigint,
      object_count integer,
      asset_count integer,
      blob_count integer,
      capture_digest varchar(64),
      captured_at timestamp(0) without time zone,
      progress_total_bytes bigint DEFAULT 0,
      accounted_size_bytes bigint,
      storage_reservation_id bigint,
      CONSTRAINT project_snapshots_object_format_version CHECK (true),
      CONSTRAINT project_snapshots_archive_format CHECK (true),
      CONSTRAINT project_snapshots_object_counts CHECK (true),
      CONSTRAINT project_snapshots_mode CHECK (true),
      CONSTRAINT project_snapshots_mode_integrity CHECK (true),
      CONSTRAINT project_snapshots_accounting_identity CHECK (true),
      CONSTRAINT project_snapshots_object_target CHECK (true),
      CONSTRAINT project_snapshots_ready_object_set CHECK (true),
      CONSTRAINT project_snapshots_full_ready_accounting CHECK (true),
      CONSTRAINT project_snapshots_linked_asset_bytes CHECK (true),
      CONSTRAINT project_snapshots_linked_ready_accounting CHECK (true)
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.snapshot_object_publication_claims (
      object_prefix varchar(500),
      inventory_digest varchar(64),
      status varchar(255),
      storage_reservation_id_snapshot bigint,
      lease_expires_at timestamp(0) without time zone,
      CONSTRAINT snapshot_object_publication_claims_identity CHECK (true)
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.workspace_storage_reservations (
      id bigserial PRIMARY KEY,
      kind varchar(255),
      status varchar(255),
      cleanup_object_prefix varchar(500),
      project_snapshot_id_snapshot bigint,
      reserved_bytes bigint,
      actual_bytes bigint,
      generation integer,
      accounting_version integer,
      expires_at timestamp(0) without time zone,
      accounting_measured_at timestamp(0) without time zone,
      storage_namespace varchar(500),
      project_id_snapshot bigint,
      lease_token uuid,
      source_asset_count bigint,
      CONSTRAINT workspace_storage_reservations_kind CHECK (true),
      CONSTRAINT workspace_storage_reservations_positive_values CHECK (true),
      CONSTRAINT workspace_storage_reservations_source_inventory CHECK (true),
      CONSTRAINT workspace_storage_reservations_namespace CHECK (true),
      CONSTRAINT workspace_storage_reservations_cleanup_object_prefix CHECK (true)
    )
    """)

    Repo.query!("""
    CREATE UNIQUE INDEX workspace_storage_reservations_ready_prefix_idx
    ON #{prefix}.workspace_storage_reservations (cleanup_object_prefix)
    WHERE kind IN ('snapshot_build', 'linked_to_full_conversion')
    """)

    Repo.query!("""
    CREATE UNIQUE INDEX workspace_storage_reservations_active_snapshot_operation_idx
    ON #{prefix}.workspace_storage_reservations (project_snapshot_id_snapshot)
    WHERE status = 'active' AND kind IN ('snapshot_build', 'linked_to_full_conversion')
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.snapshot_cleanup_intents (
      workspace_id_snapshot bigint,
      project_id_snapshot bigint,
      project_snapshot_id_snapshot bigint,
      deletion_generation bigint,
      mode varchar(255),
      origin varchar(255),
      reason varchar(255),
      authority_kind varchar(255),
      authority_actor_id bigint,
      ready_prefix varchar(500),
      staging_prefix varchar(500),
      inventory_digest varchar(64),
      object_count integer,
      estimated_cleanup_bytes bigint,
      storage_keys text[],
      remaining_storage_keys text[],
      status varchar(255),
      retry_count integer,
      processing_generation bigint,
      required_delete_passes integer,
      completed_delete_passes integer,
      next_delete_pass_at timestamp(0) without time zone,
      completed_at timestamp(0) without time zone,
      terminal_at timestamp(0) without time zone,
      CONSTRAINT snapshot_cleanup_intents_identity CHECK (true)
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.storage_cleanup_requests (
      id bigserial PRIMARY KEY,
      storage_keys text[] NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL DEFAULT clock_timestamp()
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.storage_cleanup_ownership_receipts (
      cleanup_request_id bigint PRIMARY KEY,
      storage_keys text[] NOT NULL,
      recorded_at timestamp(0) without time zone NOT NULL
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.storage_cleanup_ownership_namespaces (
      cleanup_request_id bigint NOT NULL,
      object_prefix text NOT NULL,
      CONSTRAINT storage_cleanup_ownership_namespaces_canonical_prefix CHECK (true),
      UNIQUE (cleanup_request_id, object_prefix)
    )
    """)

    Repo.query!("""
    CREATE FUNCTION #{prefix}.storyarn_capture_storage_cleanup_ownership_receipt()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      RETURN NEW;
    END;
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER storage_cleanup_requests_capture_ownership_receipt
    AFTER INSERT ON #{prefix}.storage_cleanup_requests
    FOR EACH ROW
    EXECUTE FUNCTION #{prefix}.storyarn_capture_storage_cleanup_ownership_receipt()
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.oban_jobs (
      id bigserial PRIMARY KEY,
      worker text,
      queue text,
      state text,
      args jsonb NOT NULL DEFAULT '{}'::jsonb
    )
    """)
  end

  defp insert_queued_v2(prefix, token, opts \\ []) do
    true = byte_size(token) == 16
    object_prefix = "projects/1/snapshots/archives/v2/ready/#{token}"
    defaults? = Keyword.get(opts, :defaults?, false)
    format_version = Keyword.get(opts, :format_version, 2)
    mode = Keyword.get(opts, :mode, "full")

    {identity_columns, identity_values, identity_params} =
      if defaults? do
        {"", "", []}
      else
        {", format_version, mode", ", $4, $5", [format_version, mode]}
      end

    Repo.query(
      """
      INSERT INTO #{prefix}.project_snapshots (
        project_id, lifecycle_state, integrity_state,
        object_prefix, archive_storage_key, manifest_storage_key
        #{identity_columns}
      )
      VALUES (1, 'pending', 'unknown', $1, $2, $3 #{identity_values})
      """,
      [object_prefix, object_prefix <> "/snapshot.zip", object_prefix <> "/manifest.json"] ++
        identity_params,
      mode: :savepoint
    )
  end

  defp insert_terminal_v1_cleanup_evidence!(prefix) do
    Repo.query!("""
    INSERT INTO #{prefix}.storage_cleanup_ownership_receipts (
      cleanup_request_id,
      storage_keys,
      recorded_at
    )
    VALUES (
      9001,
      ARRAY['projects/1/snapshots/object-sets/v1/ready/LEGACYTOKEN00001/project.json'],
      clock_timestamp()
    )
    """)

    Repo.query!("""
    INSERT INTO #{prefix}.storage_cleanup_ownership_namespaces (
      cleanup_request_id,
      object_prefix
    )
    VALUES (9001, 'projects/1/snapshots/object-sets/v1/ready/LEGACYTOKEN00001')
    """)
  end

  defp run_migration(direction, prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      MakeProjectSnapshotsV2Only,
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

  defp query_rows!(sql), do: Repo.query!(sql).rows

  defp column_exists?(prefix, table, column) do
    query_rows!("""
    SELECT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = '#{prefix}' AND table_name = '#{table}' AND column_name = '#{column}'
    )
    """) == [[true]]
  end

  defp column_not_null?(prefix, table, column) do
    query_rows!("""
    SELECT is_nullable = 'NO'
    FROM information_schema.columns
    WHERE table_schema = '#{prefix}' AND table_name = '#{table}' AND column_name = '#{column}'
    """) == [[true]]
  end

  defp column_default(prefix, table, column) do
    [[default]] =
      query_rows!("""
      SELECT column_default
      FROM information_schema.columns
      WHERE table_schema = '#{prefix}' AND table_name = '#{table}' AND column_name = '#{column}'
      """)

    default
  end

  defp constraint_definition(prefix, constraint_name) do
    [[definition]] =
      query_rows!("""
      SELECT pg_get_constraintdef(constraint_row.oid)
      FROM pg_constraint AS constraint_row
      JOIN pg_namespace AS namespace_row ON namespace_row.oid = constraint_row.connamespace
      WHERE namespace_row.nspname = '#{prefix}' AND constraint_row.conname = '#{constraint_name}'
      """)

    definition
  end
end
