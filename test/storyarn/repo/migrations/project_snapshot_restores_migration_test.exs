defmodule Storyarn.Repo.Migrations.ProjectSnapshotRestoresMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.CreateProjectSnapshotRestores

  @migration_version 20_260_813_100_000
  @checksum String.duplicate("a", 64)
  @manifest_checksum String.duplicate("b", 64)

  if !Code.ensure_loaded?(CreateProjectSnapshotRestores) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260813100000_create_project_snapshot_restores.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "project_snapshot_restores_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    create_parent_tables!(prefix)
    seed_parent_rows!(prefix)
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    %{prefix: prefix}
  end

  test "installs the complete table, foreign-key, index, and check contract", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)

    refute column_not_null?(prefix, "requested_by_id")

    assert foreign_key_delete_action(prefix, "project_snapshot_restores_workspace_id_fkey") ==
             "c"

    assert foreign_key_delete_action(prefix, "project_snapshot_restores_project_id_fkey") ==
             "c"

    assert foreign_key_delete_action(
             prefix,
             "project_snapshot_restores_project_snapshot_id_fkey"
           ) == "n"

    assert foreign_key_delete_action(prefix, "project_snapshot_restores_requested_by_id_fkey") ==
             "n"

    assert foreign_key_delete_action(prefix, "project_snapshot_restores_oban_job_id_fkey") ==
             "n"

    assert foreign_key_delete_action(
             prefix,
             "project_snapshot_restores_storage_reservation_id_fkey"
           ) == "r"

    for index <- [
          "project_snapshot_restores_workspace_idempotency_idx",
          "project_snapshot_restores_active_project_idx",
          "project_snapshot_restores_oban_job_idx",
          "project_snapshot_restores_workspace_status_idx",
          "project_snapshot_restores_project_status_idx",
          "project_snapshot_restores_snapshot_idx",
          "project_snapshot_restores_requested_by_idx",
          "project_snapshot_restores_reservation_idx"
        ] do
      assert index_exists?(prefix, index), "missing #{index}"
    end

    active_index = index_definition(prefix, "project_snapshot_restores_active_project_idx")
    assert active_index =~ "UNIQUE INDEX"
    assert active_index =~ "queued"
    assert active_index =~ "running"
    assert active_index =~ "retrying"

    for constraint <- [
          "project_snapshot_restores_status_check",
          "project_snapshot_restores_phase_check",
          "project_snapshot_restores_target_identity_check",
          "project_snapshot_restores_reservation_identity_check",
          "project_snapshot_restores_live_references_check",
          "project_snapshot_restores_payload_shape_check",
          "project_snapshot_restores_lifecycle_shape_check"
        ] do
      assert constraint_exists?(prefix, constraint), "missing #{constraint}"
    end

    assert trigger_exists?(prefix, "project_snapshot_restores_identity_immutable")
    assert function_exists?(prefix, "storyarn_guard_project_snapshot_restore_identity")
  end

  test "active identities cannot change and terminal foreign-key deletion only anonymizes", %{
    prefix: prefix
  } do
    assert :ok = run_migration(:up, prefix)
    restore_id = insert_restore!(prefix)

    assert_integrity_constraint_violation(fn ->
      Repo.query(
        "UPDATE #{prefix}.project_snapshot_restores SET requested_by_id = 2 WHERE id = $1",
        [restore_id],
        mode: :savepoint
      )
    end)

    assert_integrity_constraint_violation(fn ->
      Repo.query(
        "UPDATE #{prefix}.project_snapshot_restores SET requested_by_id = NULL WHERE id = $1",
        [restore_id],
        mode: :savepoint
      )
    end)

    assert_integrity_constraint_violation(fn ->
      Repo.query(
        "UPDATE #{prefix}.project_snapshot_restores SET archive_checksum = $2 WHERE id = $1",
        [restore_id, String.duplicate("c", 64)],
        mode: :savepoint
      )
    end)

    assert_integrity_constraint_violation(fn ->
      Repo.query("DELETE FROM #{prefix}.users WHERE id = 1", [], mode: :savepoint)
    end)

    assert_integrity_constraint_violation(fn ->
      Repo.query("DELETE FROM #{prefix}.project_snapshots WHERE id = 1", [], mode: :savepoint)
    end)

    Repo.query!("""
    UPDATE #{prefix}.project_snapshot_restores
    SET status = 'failed',
        phase = 'failed',
        attempt = 1,
        claimed_at = requested_at,
        failed_at = requested_at,
        failure_code = 'restore_failed'
    WHERE id = #{restore_id}
    """)

    Repo.query!("DELETE FROM #{prefix}.project_snapshots WHERE id = 1")
    Repo.query!("DELETE FROM #{prefix}.users WHERE id = 1")

    assert Repo.query!(
             "SELECT project_snapshot_id, requested_by_id FROM #{prefix}.project_snapshot_restores WHERE id = $1",
             [restore_id]
           ).rows == [[nil, nil]]

    assert_integrity_constraint_violation(fn ->
      Repo.query(
        "UPDATE #{prefix}.project_snapshot_restores SET requested_by_id = 2 WHERE id = $1",
        [restore_id],
        mode: :savepoint
      )
    end)
  end

  test "database idempotency and active-project uniqueness are workspace scoped", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    insert_restore!(prefix)

    assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
             insert_restore(prefix)

    assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
             insert_restore(prefix,
               idempotency_key: "00000000-0000-4000-8000-000000000099"
             )

    assert {:ok, _result} =
             insert_restore(prefix,
               workspace_id: 2,
               project_id: 2,
               project_snapshot_id: 2
             )
  end

  test "target and lifecycle checks fail closed on malformed rows", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)

    assert_check_violation(fn ->
      insert_restore(prefix, archive_storage_key: "manifest.json")
    end)

    assert_check_violation(fn ->
      insert_restore(prefix, archive_checksum: "not-a-digest")
    end)

    assert_check_violation(fn ->
      insert_restore(prefix, status: "queued", phase: "preflight")
    end)

    assert_check_violation(fn -> insert_restore(prefix, requested_by_id: nil) end)
    assert_check_violation(fn -> insert_restore(prefix, project_snapshot_id: nil) end)
  end

  test "empty rollback removes all restore DDL and can be applied again", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    assert :ok = run_migration(:down, prefix)

    refute table_exists?(prefix, "project_snapshot_restores")
    refute function_exists?(prefix, "storyarn_guard_project_snapshot_restore_identity")

    assert :ok = run_migration(:up, prefix)
    assert {:ok, _result} = insert_restore(prefix)
  end

  defp create_parent_tables!(prefix) do
    for table <- ~w(users workspaces projects project_snapshots workspace_storage_reservations) do
      Repo.query!("CREATE TABLE #{prefix}.#{table} (id bigserial PRIMARY KEY)")
    end

    Repo.query!("CREATE TABLE #{prefix}.oban_jobs (id bigint PRIMARY KEY)")
  end

  defp seed_parent_rows!(prefix) do
    for table <- ~w(users workspaces projects project_snapshots) do
      Repo.query!("INSERT INTO #{prefix}.#{table} (id) VALUES (1), (2)")
    end
  end

  defp insert_restore!(prefix, overrides \\ []) do
    {:ok, %Postgrex.Result{rows: [[id]]}} = insert_restore(prefix, overrides)
    id
  end

  defp insert_restore(prefix, overrides \\ []) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    attrs =
      Keyword.merge(
        [
          workspace_id: 1,
          project_id: 1,
          project_snapshot_id: 1,
          requested_by_id: 1,
          idempotency_key: "00000000-0000-4000-8000-000000000001",
          status: "queued",
          phase: "queued",
          generation: 1,
          attempt: 0,
          archive_storage_key: "snapshot.zip",
          archive_size_bytes: 10,
          archive_checksum: @checksum,
          manifest_storage_key: "manifest.json",
          manifest_size_bytes: 5,
          manifest_checksum: @manifest_checksum
        ],
        overrides
      )

    Repo.query(
      """
      INSERT INTO #{prefix}.project_snapshot_restores (
        workspace_id, project_id, project_snapshot_id, requested_by_id,
        idempotency_key, status, phase, generation, attempt,
        snapshot_lifecycle_generation, snapshot_accounting_generation,
        archive_storage_key, archive_size_bytes, archive_checksum,
        manifest_storage_key, manifest_size_bytes, manifest_checksum,
        requested_at, state_updated_at, inserted_at, updated_at
      )
      VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, 1, 1,
        $10, $11, $12, $13, $14, $15, $16, $16, $16, $16
      )
      RETURNING id
      """,
      [
        attrs[:workspace_id],
        attrs[:project_id],
        attrs[:project_snapshot_id],
        attrs[:requested_by_id],
        Ecto.UUID.dump!(attrs[:idempotency_key]),
        attrs[:status],
        attrs[:phase],
        attrs[:generation],
        attrs[:attempt],
        attrs[:archive_storage_key],
        attrs[:archive_size_bytes],
        attrs[:archive_checksum],
        attrs[:manifest_storage_key],
        attrs[:manifest_size_bytes],
        attrs[:manifest_checksum],
        now
      ],
      mode: :savepoint
    )
  end

  defp run_migration(direction, prefix) do
    runner_direction = if direction == :up, do: :forward, else: :backward

    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      CreateProjectSnapshotRestores,
      runner_direction,
      :change,
      direction,
      prefix: prefix,
      log: false
    )
  end

  defp assert_check_violation(fun) do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} = fun.()
  end

  defp assert_integrity_constraint_violation(fun) do
    assert {:error, %Postgrex.Error{postgres: %{code: :integrity_constraint_violation}}} =
             fun.()
  end

  defp column_not_null?(prefix, column) do
    %Postgrex.Result{rows: [[not_null?]]} =
      Repo.query!(
        """
        SELECT attribute.attnotnull
        FROM pg_attribute AS attribute
        JOIN pg_class AS relation ON relation.oid = attribute.attrelid
        JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
        WHERE namespace.nspname = $1
          AND relation.relname = 'project_snapshot_restores'
          AND attribute.attname = $2
        """,
        [prefix, column]
      )

    not_null?
  end

  defp foreign_key_delete_action(prefix, constraint) do
    %Postgrex.Result{rows: [[action]]} =
      Repo.query!(
        """
        SELECT constraint_row.confdeltype::text
        FROM pg_constraint AS constraint_row
        JOIN pg_namespace AS namespace_row
          ON namespace_row.oid = constraint_row.connamespace
        WHERE namespace_row.nspname = $1 AND constraint_row.conname = $2
        """,
        [prefix, constraint]
      )

    action
  end

  defp table_exists?(prefix, table) do
    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!("SELECT to_regclass($1) IS NOT NULL", ["#{prefix}.#{table}"])

    exists?
  end

  defp constraint_exists?(prefix, constraint) do
    catalog_object_exists?(prefix, constraint, "pg_constraint")
  end

  defp index_exists?(prefix, index) do
    catalog_object_exists?(prefix, index, "pg_class")
  end

  defp catalog_object_exists?(prefix, name, catalog) do
    name_column = if catalog == "pg_constraint", do: "conname", else: "relname"
    namespace_column = if catalog == "pg_constraint", do: "connamespace", else: "relnamespace"

    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM #{catalog} AS object_row
          JOIN pg_namespace AS namespace_row
            ON namespace_row.oid = object_row.#{namespace_column}
          WHERE namespace_row.nspname = $1 AND object_row.#{name_column} = $2
        )
        """,
        [prefix, name]
      )

    exists?
  end

  defp index_definition(prefix, index) do
    %Postgrex.Result{rows: [[definition]]} =
      Repo.query!(
        """
        SELECT pg_get_indexdef(index_row.oid)
        FROM pg_class AS index_row
        JOIN pg_namespace AS namespace_row ON namespace_row.oid = index_row.relnamespace
        WHERE namespace_row.nspname = $1 AND index_row.relname = $2
        """,
        [prefix, index]
      )

    definition
  end

  defp trigger_exists?(prefix, trigger) do
    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_trigger AS trigger_row
          JOIN pg_class AS table_row ON table_row.oid = trigger_row.tgrelid
          JOIN pg_namespace AS namespace_row ON namespace_row.oid = table_row.relnamespace
          WHERE namespace_row.nspname = $1 AND trigger_row.tgname = $2
        )
        """,
        [prefix, trigger]
      )

    exists?
  end

  defp function_exists?(prefix, function) do
    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_proc AS function_row
          JOIN pg_namespace AS namespace_row ON namespace_row.oid = function_row.pronamespace
          WHERE namespace_row.nspname = $1 AND function_row.proname = $2
        )
        """,
        [prefix, function]
      )

    exists?
  end
end
