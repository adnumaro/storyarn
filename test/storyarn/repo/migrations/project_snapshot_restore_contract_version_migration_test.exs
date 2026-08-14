defmodule Storyarn.Repo.Migrations.ProjectSnapshotRestoreContractVersionMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.AddProjectSnapshotRestoreContractVersion

  @migration_version 20_260_813_104_000

  if !Code.ensure_loaded?(AddProjectSnapshotRestoreContractVersion) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260813104000_add_project_snapshot_restore_contract_version.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "snapshot_restore_contract_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    create_pre_migration_table!(prefix)
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
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

  defp assert_check_violation(fun) do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} = fun.()
  end

  defp assert_integrity_violation(fun) do
    assert {:error, %Postgrex.Error{postgres: %{code: :integrity_constraint_violation}}} = fun.()
  end

  defp run_migration(direction, prefix) do
    Ecto.Migration.Runner.run(
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
end
