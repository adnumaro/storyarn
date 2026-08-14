defmodule Storyarn.Repo.Migrations.RestoreCleanupStorageKeysMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.AddRestoreCleanupStorageKeys

  @migration_version 20_260_813_103_000
  @constraint "workspace_storage_reservations_cleanup_storage_keys"
  @index "workspace_storage_reservations_active_restore_cleanup_keys_idx"

  if !Code.ensure_loaded?(AddRestoreCleanupStorageKeys) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260813103000_add_restore_cleanup_storage_keys.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "restore_cleanup_keys_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")

    Repo.query!("""
    CREATE TABLE #{prefix}.workspace_storage_reservations (
      id bigserial PRIMARY KEY,
      kind text NOT NULL,
      status text NOT NULL,
      storage_started_at timestamp(0) without time zone,
      cleanup_inventory_digest text,
      cleanup_inventory_count integer
    )
    """)

    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    %{prefix: prefix}
  end

  test "stores exact restore inventories and indexes only active in-flight rows", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)

    assert {:ok, _result} = insert_row(prefix, "restore_staging", "active", ["a", "b"], 2)

    assert {:ok, _result} =
             insert_row(prefix, "restore_staging", "committed", ["retained"], 1)

    assert {:ok, _result} =
             insert_row(prefix, "restore_staging", "committed", nil, 1)

    assert index_definition(prefix, @index) =~ "USING gin (cleanup_storage_keys)"
    assert index_definition(prefix, @index) =~ "status = 'active'"
    assert index_definition(prefix, @index) =~ "kind = 'restore_staging'"

    definition = constraint_definition(prefix, @constraint)
    assert definition =~ "cardinality(cleanup_storage_keys) <= 30000"
    assert definition =~ "16777216"
    assert definition =~ "cleanup_inventory_count = cardinality(cleanup_storage_keys)"
  end

  test "persisted cleanup inventories are immutable", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)

    assert {:ok, %Postgrex.Result{rows: [[id]]}} =
             insert_row(prefix, "restore_staging", "active", ["a"], 1)

    assert {:error, %Postgrex.Error{postgres: %{code: :integrity_constraint_violation}}} =
             Repo.query(
               """
               UPDATE #{prefix}.workspace_storage_reservations
               SET cleanup_storage_keys = ARRAY['b']::text[]
               WHERE id = $1
               """,
               [id],
               mode: :savepoint
             )
  end

  test "rejects missing, cross-kind, pre-start, null, empty, and count-mismatched inventories", %{
    prefix: prefix
  } do
    assert :ok = run_migration(:up, prefix)

    for result <- [
          insert_row(prefix, "restore_staging", "active", nil, 1),
          insert_row(prefix, "snapshot_build", "active", ["a"], 1),
          insert_row(prefix, "restore_staging", "active", ["a"], 1, storage_started?: false),
          insert_row(prefix, "restore_staging", "active", [], 0),
          insert_row(prefix, "restore_staging", "active", ["a", "b"], 1),
          insert_row(prefix, "restore_staging", "active", [""], 1),
          insert_row(prefix, "restore_staging", "active", [nil], 1)
        ] do
      assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} = result
    end
  end

  test "accepts the format maximum and rejects one key beyond it", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    maximum = Enum.map(1..30_000, &"k#{&1}")

    assert {:ok, _result} =
             insert_row(prefix, "restore_staging", "active", maximum, length(maximum))

    too_many = ["overflow" | maximum]

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             insert_row(prefix, "restore_staging", "active", too_many, length(too_many))
  end

  test "down removes empty DDL, reapplies, and fails closed once evidence exists", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    assert :ok = run_migration(:down, prefix)
    refute column_exists?(prefix, "cleanup_storage_keys")
    refute index_exists?(prefix, @index)

    assert :ok = run_migration(:up, prefix)
    assert {:ok, _result} = insert_row(prefix, "restore_staging", "active", ["a"], 1)

    assert_raise Ecto.MigrationError, ~r/cannot be rolled back/, fn ->
      run_migration(:down, prefix)
    end

    assert column_exists?(prefix, "cleanup_storage_keys")
    assert index_exists?(prefix, @index)
    assert constraint_exists?(prefix, @constraint)
  end

  defp insert_row(prefix, kind, status, cleanup_storage_keys, cleanup_inventory_count, opts \\ []) do
    storage_started_at =
      if Keyword.get(opts, :storage_started?, true),
        do: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Repo.query(
      """
      INSERT INTO #{prefix}.workspace_storage_reservations (
        kind, status, storage_started_at, cleanup_inventory_digest,
        cleanup_inventory_count, cleanup_storage_keys
      )
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING id
      """,
      [kind, status, storage_started_at, String.duplicate("a", 64), cleanup_inventory_count, cleanup_storage_keys],
      mode: :savepoint
    )
  end

  defp run_migration(direction, prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      AddRestoreCleanupStorageKeys,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end

  defp constraint_definition(prefix, constraint) do
    %Postgrex.Result{rows: [[definition]]} =
      Repo.query!(
        """
        SELECT pg_get_constraintdef(constraint_row.oid)
        FROM pg_constraint AS constraint_row
        JOIN pg_namespace AS namespace_row ON namespace_row.oid = constraint_row.connamespace
        WHERE namespace_row.nspname = $1 AND constraint_row.conname = $2
        """,
        [prefix, constraint]
      )

    definition
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

  defp constraint_exists?(prefix, constraint) do
    catalog_exists?(prefix, constraint, "pg_constraint", "connamespace", "conname")
  end

  defp index_exists?(prefix, index) do
    catalog_exists?(prefix, index, "pg_class", "relnamespace", "relname")
  end

  defp catalog_exists?(prefix, name, catalog, namespace_column, name_column) do
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

  defp column_exists?(prefix, column) do
    %Postgrex.Result{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_attribute AS attribute
          JOIN pg_class AS table_row ON table_row.oid = attribute.attrelid
          JOIN pg_namespace AS namespace_row ON namespace_row.oid = table_row.relnamespace
          WHERE namespace_row.nspname = $1
            AND table_row.relname = 'workspace_storage_reservations'
            AND attribute.attname = $2
            AND NOT attribute.attisdropped
        )
        """,
        [prefix, column]
      )

    exists?
  end
end
