defmodule Storyarn.Repo.Migrations.ProjectSnapshotRestoreContractVersionMigrationTest do
  use Storyarn.DataCase, async: false

  alias Ecto.Migration.Runner
  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.AddProjectSnapshotRestoreContractVersion
  alias Storyarn.Repo.Migrations.AddRestoreCleanupStorageKeys

  @migration_version 20_260_813_104_000
  @cleanup_migration_version 20_260_813_103_000

  if !Code.ensure_loaded?(AddProjectSnapshotRestoreContractVersion) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260813104000_add_project_snapshot_restore_contract_version.exs",
        __DIR__
      )
    )
  end

  if !Code.ensure_loaded?(AddRestoreCleanupStorageKeys) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260813103000_add_restore_cleanup_storage_keys.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "snapshot_restore_contract_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    create_pre_migration_table!(prefix)
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    assert :ok = run_cleanup_migration(:up, prefix)
    %{prefix: prefix}
  end

  test "keeps historical snapshots ineligible and marks only the capture transition", %{prefix: prefix} do
    uncaptured_id = insert_snapshot!(prefix)
    already_captured_id = insert_snapshot!(prefix, captured?: true)

    assert :ok = run_migration(:up, prefix)
    assert restore_contract_version(prefix, uncaptured_id) == nil
    assert restore_contract_version(prefix, already_captured_id) == nil

    assert {:ok, _result} = materialize_capture(prefix, uncaptured_id)
    assert restore_contract_version(prefix, uncaptured_id) == 1

    assert_integrity_violation(fn -> clear_restore_contract(prefix, uncaptured_id) end)
    assert_integrity_violation(fn -> promote_existing_capture(prefix, already_captured_id) end)
  end

  test "accepts only version one backed by capture metadata", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)

    assert {:ok, _result} = insert_snapshot(prefix, captured?: true, restore_contract_version: 1)

    assert_check_violation(fn ->
      insert_snapshot(prefix, restore_contract_version: 1)
    end)

    assert_check_violation(fn ->
      insert_snapshot(prefix, captured?: true, restore_contract_version: 2)
    end)

    assert column_contract(prefix) == {true, nil}
  end

  test "round-trips down and up while no restore evidence exists", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    assert project_snapshot_column_exists?(prefix, "restore_contract_version")

    assert :ok = run_migration(:down, prefix)
    refute project_snapshot_column_exists?(prefix, "restore_contract_version")

    assert :ok = run_migration(:up, prefix)
    assert column_contract(prefix) == {true, nil}
  end

  test "rejects rollback before DDL after a snapshot gains restore-contract evidence", %{prefix: prefix} do
    snapshot_id = insert_snapshot!(prefix)
    assert :ok = run_migration(:up, prefix)
    assert {:ok, _result} = materialize_capture(prefix, snapshot_id)

    assert_raise Ecto.MigrationError, ~r/cannot be rolled back/, fn ->
      run_migration(:down, prefix)
    end

    assert project_snapshot_column_exists?(prefix, "restore_contract_version")
    assert restore_contract_version(prefix, snapshot_id) == 1
    assert_integrity_violation(fn -> clear_restore_contract(prefix, snapshot_id) end)
  end

  test "blocks a multi-migration rollback before prior cleanup evidence can strand the schema", %{
    prefix: prefix
  } do
    assert :ok = run_migration(:up, prefix)
    cleanup_key = "projects/1/restores/1/blobs/#{String.duplicate("a", 64)}"
    insert_cleanup_evidence!(prefix, cleanup_key)

    assert_raise Ecto.MigrationError, ~r/cleanup-inventory evidence exists/, fn ->
      run_restore_feature_rollback(prefix)
    end

    refute_received :cleanup_migration_down_started
    assert project_snapshot_column_exists?(prefix, "restore_contract_version")
    assert table_column_exists?(prefix, "workspace_storage_reservations", "cleanup_storage_keys")

    assert Repo.query!("SELECT cleanup_storage_keys FROM #{prefix}.workspace_storage_reservations").rows == [
             [[cleanup_key]]
           ]
  end

  defp create_pre_migration_table!(prefix) do
    Repo.query!("""
    CREATE TABLE #{prefix}.project_snapshots (
      id bigserial PRIMARY KEY,
      format_version integer NOT NULL DEFAULT 2,
      lifecycle_state text NOT NULL DEFAULT 'pending',
      capture_digest varchar(64),
      captured_at timestamp(0) without time zone
    )
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.workspace_storage_reservations (
      id bigserial PRIMARY KEY,
      kind text,
      status text,
      storage_started_at timestamp(0) without time zone,
      cleanup_inventory_digest varchar(64),
      cleanup_inventory_count integer
    )
    """)
  end

  defp insert_cleanup_evidence!(prefix, cleanup_key) do
    digest =
      cleanup_key
      |> then(&"#{byte_size(&1)}:#{&1}")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    Repo.query!(
      """
      INSERT INTO #{prefix}.workspace_storage_reservations (
        kind, status, storage_started_at, cleanup_inventory_digest,
        cleanup_inventory_count, cleanup_storage_keys
      )
      VALUES ('restore_staging', 'active', $1, $2, 1, $3)
      """,
      [~N[2026-08-14 12:00:00], digest, [cleanup_key]]
    )
  end

  defp insert_snapshot!(prefix, opts \\ []) do
    captured? = Keyword.get(opts, :captured?, false)

    {capture_digest, captured_at} =
      if captured?,
        do: {String.duplicate("a", 64), ~N[2026-08-13 10:00:00]},
        else: {nil, nil}

    %Postgrex.Result{rows: [[id]]} =
      Repo.query!(
        """
        INSERT INTO #{prefix}.project_snapshots (capture_digest, captured_at)
        VALUES ($1, $2)
        RETURNING id
        """,
        [capture_digest, captured_at]
      )

    id
  end

  defp insert_snapshot(prefix, opts) do
    captured? = Keyword.get(opts, :captured?, false)
    restore_contract_version = Keyword.get(opts, :restore_contract_version)

    {capture_digest, captured_at} =
      if captured?,
        do: {String.duplicate("a", 64), ~N[2026-08-13 10:00:00]},
        else: {nil, nil}

    Repo.query(
      """
      INSERT INTO #{prefix}.project_snapshots (
        capture_digest, captured_at, restore_contract_version
      )
      VALUES ($1, $2, $3)
      RETURNING id
      """,
      [capture_digest, captured_at, restore_contract_version],
      mode: :savepoint
    )
  end

  defp materialize_capture(prefix, id) do
    Repo.query(
      """
      UPDATE #{prefix}.project_snapshots
      SET capture_digest = $2, captured_at = $3, restore_contract_version = 1
      WHERE id = $1
      """,
      [id, String.duplicate("b", 64), ~N[2026-08-13 11:00:00]],
      mode: :savepoint
    )
  end

  defp clear_restore_contract(prefix, id) do
    Repo.query(
      "UPDATE #{prefix}.project_snapshots SET restore_contract_version = NULL WHERE id = $1",
      [id],
      mode: :savepoint
    )
  end

  defp promote_existing_capture(prefix, id) do
    Repo.query(
      "UPDATE #{prefix}.project_snapshots SET restore_contract_version = 1 WHERE id = $1",
      [id],
      mode: :savepoint
    )
  end

  defp restore_contract_version(prefix, id) do
    %Postgrex.Result{rows: [[version]]} =
      Repo.query!("SELECT restore_contract_version FROM #{prefix}.project_snapshots WHERE id = $1", [id])

    version
  end

  defp column_contract(prefix) do
    %Postgrex.Result{rows: [[nullable, default]]} =
      Repo.query!(
        """
        SELECT attribute.is_nullable, attribute.column_default
        FROM information_schema.columns AS attribute
        WHERE attribute.table_schema = $1 AND attribute.table_name = 'project_snapshots' AND
              attribute.column_name = 'restore_contract_version'
        """,
        [prefix]
      )

    {nullable == "YES", default}
  end

  defp project_snapshot_column_exists?(prefix, column) do
    table_column_exists?(prefix, "project_snapshots", column)
  end

  defp table_column_exists?(prefix, table, column) do
    Repo.query!(
      """
      SELECT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = $1 AND table_name = $2 AND column_name = $3
      )
      """,
      [prefix, table, column]
    ).rows == [[true]]
  end

  defp assert_check_violation(fun) do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} = fun.()
  end

  defp assert_integrity_violation(fun) do
    assert {:error, %Postgrex.Error{postgres: %{code: :integrity_constraint_violation}}} = fun.()
  end

  defp run_migration(direction, prefix) do
    Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      AddProjectSnapshotRestoreContractVersion,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end

  defp run_cleanup_migration(direction, prefix) do
    Runner.run(
      Repo,
      Repo.config(),
      @cleanup_migration_version,
      AddRestoreCleanupStorageKeys,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end

  defp run_restore_feature_rollback(prefix) do
    with :ok <- run_migration(:down, prefix) do
      send(self(), :cleanup_migration_down_started)
      run_cleanup_migration(:down, prefix)
    end
  end
end
