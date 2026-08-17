defmodule Storyarn.Repo.Migrations.DropSnapshotContentHealthColumnsMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.DropSnapshotContentHealthColumns

  @migration_version 20_260_817_130_000

  if !Code.ensure_loaded?(DropSnapshotContentHealthColumns) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260817130000_drop_snapshot_content_health_columns.exs",
        __DIR__
      )
    )
  end

  test "final schema has no snapshot health columns" do
    prefix = Repo.query!("SELECT current_schema()").rows |> hd() |> hd()
    assert health_columns(prefix) == []
  end

  test "upgrade removes the inert columns left by the deployed migration" do
    prefix = "drop_snapshot_health_columns_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")

    Repo.query!("CREATE TABLE #{prefix}.project_snapshots (content_health jsonb NOT NULL DEFAULT '{}'::jsonb)")

    Repo.query!("CREATE TABLE #{prefix}.project_snapshot_captures (content_health jsonb NOT NULL DEFAULT '{}'::jsonb)")

    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])

    assert :ok = run_migration(prefix)
    assert health_columns(prefix) == []
  end

  defp health_columns(prefix) do
    Repo.query!(
      """
      SELECT table_name, column_name
      FROM information_schema.columns
      WHERE table_schema = $1 AND
            table_name IN ('project_snapshots', 'project_snapshot_captures') AND
            column_name = 'content_health'
      ORDER BY table_name
      """,
      [prefix]
    ).rows
  end

  defp run_migration(prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      DropSnapshotContentHealthColumns,
      :forward,
      :up,
      :up,
      prefix: prefix,
      log: false
    )
  end
end
