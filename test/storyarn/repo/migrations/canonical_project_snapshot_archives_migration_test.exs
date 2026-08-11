defmodule Storyarn.Repo.Migrations.CanonicalProjectSnapshotArchivesMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.AddCanonicalProjectSnapshotArchives

  @migration_version 20_260_811_120_000
  @archive_index "project_snapshots_archive_storage_key_index"

  if !Code.ensure_loaded?(AddCanonicalProjectSnapshotArchives) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260811120000_add_canonical_project_snapshot_archives.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "canonical_snapshot_archive_migration_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    create_v1_schema!(prefix)
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    %{prefix: prefix}
  end

  test "up preserves v1 rows and enforces the v2 archive contract", %{prefix: prefix} do
    assert {:ok, _result} = insert_v1_snapshot(prefix)
    assert :ok = run_migration(:up, prefix)

    assert [[1, nil, nil, nil]] =
             query_rows!("""
             SELECT format_version, archive_storage_key, archive_size_bytes, archive_checksum
             FROM #{prefix}.project_snapshots
             WHERE format_version = 1
             """)

    assert {:ok, _result} = insert_v2_snapshot(prefix, "V2VALID000000001")
    assert index_exists?(prefix, @archive_index)

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_v2_snapshot(prefix, "V2BADKEY00000001",
               archive_storage_key: "projects/2/snapshots/archives/v2/ready/V2BADKEY00000001/not-a-snapshot.zip"
             )

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_v2_snapshot(prefix, "V2BADCOUNT000001", object_count: 3)

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_v2_snapshot(prefix, "V2BADACCT0000001", accounted_size_bytes: 11)

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_v2_snapshot(prefix, "V2NOMANIFEST0000", manifest_storage_key: nil)

    assert constraint_definition(prefix, "project_snapshots_object_target") =~
             "manifest_storage_key IS NOT NULL"

    assert constraint_definition(prefix, "project_snapshots_ready_object_set") =~
             "manifest_storage_key IS NOT NULL"

    assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
             insert_v2_snapshot(prefix, "V2VALID000000001")
  end

  test "an empty down removes v2 DDL and the migration can be applied again", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    assert column_exists?(prefix, "project_snapshots", "archive_storage_key")
    assert index_exists?(prefix, @archive_index)

    assert :ok = run_migration(:down, prefix)
    refute column_exists?(prefix, "project_snapshots", "archive_storage_key")
    refute index_exists?(prefix, @archive_index)
    assert column_not_null?(prefix, "project_snapshots", "project_storage_key")

    assert :ok = run_migration(:up, prefix)
    assert column_exists?(prefix, "project_snapshots", "archive_storage_key")
    assert constraint_exists?(prefix, "project_snapshots_archive_format")
    assert index_exists?(prefix, @archive_index)
  end

  test "down with v2 evidence fails before DDL and preserves the row", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    assert {:ok, _result} = insert_v2_snapshot(prefix, "V2ROLLBACK000001")

    error =
      assert_raise Postgrex.Error, fn ->
        run_migration(:down, prefix)
      end

    assert error.postgres.code == :object_not_in_prerequisite_state
    assert error.postgres.pg_code == "55000"
    assert query_rows!("SELECT count(*) FROM #{prefix}.project_snapshots WHERE format_version = 2") == [[1]]
    assert column_exists?(prefix, "project_snapshots", "archive_storage_key")
    assert constraint_exists?(prefix, "project_snapshots_archive_format")
    assert constraint_exists?(prefix, "project_snapshots_object_format_version")
    assert index_exists?(prefix, @archive_index)
  end

  defp create_v1_schema!(prefix) do
    Repo.query!("""
    CREATE TABLE #{prefix}.project_snapshots (
      id bigserial PRIMARY KEY,
      project_id bigint NOT NULL,
      project_storage_key varchar(255) NOT NULL,
      project_size_bytes bigint,
      project_checksum varchar(64),
      format_version integer NOT NULL,
      object_prefix varchar(500),
      manifest_storage_key varchar(520),
      manifest_size_bytes bigint,
      manifest_checksum varchar(64),
      total_size_bytes bigint,
      object_count integer,
      asset_count integer,
      blob_count integer,
      mode text NOT NULL,
      lifecycle_state text NOT NULL,
      integrity_state text NOT NULL,
      accounted_size_bytes bigint,
      asset_blob_size_bytes bigint,
      CONSTRAINT project_snapshots_object_format_version
        CHECK (format_version IS NULL OR format_version = 1),
      CONSTRAINT project_snapshots_object_counts
        CHECK (
          (object_count IS NULL AND asset_count IS NULL AND blob_count IS NULL) OR
          (object_count IS NOT NULL AND asset_count IS NOT NULL AND blob_count IS NOT NULL AND
           object_count = blob_count + 2 AND blob_count >= 0 AND asset_count >= blob_count)
        ),
      CONSTRAINT project_snapshots_accounting_identity
        CHECK (
          format_version IS NOT NULL AND format_version = 1 AND
          mode IS NOT NULL AND lifecycle_state IS NOT NULL AND integrity_state IS NOT NULL
        ),
      CONSTRAINT project_snapshots_object_target
        CHECK (
          object_prefix IS NOT NULL AND
          object_prefix ~ ('^projects/' || project_id ||
            '/snapshots/object-sets/v1/ready/[A-Za-z0-9_-]{16}$') AND
          project_storage_key IS NOT NULL AND project_storage_key = object_prefix || '/project.json' AND
          manifest_storage_key IS NOT NULL AND manifest_storage_key = object_prefix || '/manifest.json'
        ),
      CONSTRAINT project_snapshots_ready_object_set
        CHECK (
          lifecycle_state <> 'ready' OR
          (format_version = 1 AND object_prefix IS NOT NULL AND btrim(object_prefix) <> '' AND
           object_prefix ~ ('^projects/' || project_id ||
             '/snapshots/object-sets/v1/ready/[A-Za-z0-9_-]{16}$') AND
           project_storage_key IS NOT NULL AND project_storage_key = object_prefix || '/project.json' AND
           project_size_bytes IS NOT NULL AND project_size_bytes > 0 AND
           project_checksum IS NOT NULL AND project_checksum ~ '^[0-9a-f]{64}$' AND
           manifest_storage_key IS NOT NULL AND manifest_storage_key = object_prefix || '/manifest.json' AND
           manifest_size_bytes IS NOT NULL AND manifest_size_bytes > 0 AND
           manifest_checksum IS NOT NULL AND manifest_checksum ~ '^[0-9a-f]{64}$' AND
           total_size_bytes IS NOT NULL AND total_size_bytes > 0 AND object_count IS NOT NULL AND
           asset_count IS NOT NULL AND blob_count IS NOT NULL)
        ),
      CONSTRAINT project_snapshots_full_ready_accounting
        CHECK (
          mode <> 'full' OR lifecycle_state <> 'ready' OR
          (total_size_bytes IS NOT NULL AND manifest_size_bytes IS NOT NULL AND
           accounted_size_bytes = total_size_bytes AND
           total_size_bytes = project_size_bytes + manifest_size_bytes + asset_blob_size_bytes)
        )
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.snapshot_object_publication_claims (
      object_prefix text,
      inventory_digest text,
      status text,
      storage_reservation_id_snapshot bigint,
      lease_expires_at timestamp(0) with time zone,
      CONSTRAINT snapshot_object_publication_claims_identity CHECK (true)
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.workspace_storage_reservations (
      kind text,
      cleanup_object_prefix text,
      project_id_snapshot bigint,
      storage_namespace text,
      CONSTRAINT workspace_storage_reservations_cleanup_object_prefix CHECK (true)
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.storage_cleanup_requests (
      id bigserial PRIMARY KEY,
      storage_keys text[] NOT NULL,
      inserted_at timestamp(0) with time zone NOT NULL DEFAULT clock_timestamp()
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.storage_cleanup_ownership_receipts (
      cleanup_request_id bigint,
      storage_keys text[],
      recorded_at timestamp(0) with time zone
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.storage_cleanup_ownership_namespaces (
      cleanup_request_id bigint,
      object_prefix text,
      CONSTRAINT storage_cleanup_ownership_namespaces_canonical_prefix CHECK (true),
      UNIQUE (cleanup_request_id, object_prefix)
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.snapshot_cleanup_intents (
      workspace_id_snapshot bigint,
      project_id_snapshot bigint,
      project_snapshot_id_snapshot bigint,
      deletion_generation bigint,
      mode text,
      origin text,
      reason text,
      authority_kind text,
      authority_actor_id bigint,
      ready_prefix text,
      staging_prefix text,
      inventory_digest text,
      object_count integer,
      estimated_cleanup_bytes bigint,
      storage_keys text[] DEFAULT '{}',
      remaining_storage_keys text[] DEFAULT '{}',
      status text,
      retry_count integer,
      processing_generation integer,
      required_delete_passes integer,
      completed_delete_passes integer,
      next_delete_pass_at timestamp(0) with time zone,
      completed_at timestamp(0) with time zone,
      terminal_at timestamp(0) with time zone,
      CONSTRAINT snapshot_cleanup_intents_identity CHECK (true)
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
  end

  defp insert_v1_snapshot(prefix) do
    object_prefix = "projects/1/snapshots/object-sets/v1/ready/LEGACYTOKEN00001"

    Repo.query(
      """
      INSERT INTO #{prefix}.project_snapshots (
        project_id, project_storage_key, project_size_bytes, project_checksum,
        format_version, object_prefix, manifest_storage_key, manifest_size_bytes,
        manifest_checksum, total_size_bytes, object_count, asset_count, blob_count,
        mode, lifecycle_state, integrity_state, accounted_size_bytes, asset_blob_size_bytes
      )
      VALUES ($1, $2, 4, $3, 1, $4, $5, 2, $6, 12, 3, 1, 1,
              'full', 'ready', 'verified', 12, 6)
      """,
      [
        1,
        object_prefix <> "/project.json",
        String.duplicate("a", 64),
        object_prefix,
        object_prefix <> "/manifest.json",
        String.duplicate("b", 64)
      ],
      mode: :savepoint
    )
  end

  defp insert_v2_snapshot(prefix, token, overrides \\ []) do
    true = byte_size(token) == 16
    object_prefix = "projects/2/snapshots/archives/v2/ready/#{token}"

    values = %{
      archive_storage_key: object_prefix <> "/snapshot.zip",
      manifest_storage_key: object_prefix <> "/manifest.json",
      object_count: 2,
      accounted_size_bytes: 12
    }

    values = Enum.into(overrides, values)

    Repo.query(
      """
      INSERT INTO #{prefix}.project_snapshots (
        project_id, project_storage_key, project_size_bytes, project_checksum,
        format_version, object_prefix, manifest_storage_key, manifest_size_bytes,
        manifest_checksum, total_size_bytes, object_count, asset_count, blob_count,
        mode, lifecycle_state, integrity_state, accounted_size_bytes, asset_blob_size_bytes,
        archive_storage_key, archive_size_bytes, archive_checksum
      )
      VALUES (2, NULL, 3, $1, 2, $2, $3, 2, $4, 12, $5, 2, 1,
              'full', 'ready', 'verified', $6, 41, $7, 10, $8)
      """,
      [
        String.duplicate("c", 64),
        object_prefix,
        values.manifest_storage_key,
        String.duplicate("d", 64),
        values.object_count,
        values.accounted_size_bytes,
        values.archive_storage_key,
        String.duplicate("e", 64)
      ],
      mode: :savepoint
    )
  end

  defp run_migration(direction, prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      AddCanonicalProjectSnapshotArchives,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
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

  defp constraint_exists?(prefix, constraint_name) do
    query_rows!("""
    SELECT EXISTS (
      SELECT 1
      FROM pg_constraint AS constraint_row
      JOIN pg_namespace AS namespace_row ON namespace_row.oid = constraint_row.connamespace
      WHERE namespace_row.nspname = '#{prefix}' AND constraint_row.conname = '#{constraint_name}'
    )
    """) == [[true]]
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

  defp index_exists?(prefix, index_name) do
    query_rows!("""
    SELECT EXISTS (
      SELECT 1
      FROM pg_class AS relation_row
      JOIN pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
      WHERE namespace_row.nspname = '#{prefix}' AND relation_row.relname = '#{index_name}' AND
            relation_row.relkind = 'i'
    )
    """) == [[true]]
  end
end
