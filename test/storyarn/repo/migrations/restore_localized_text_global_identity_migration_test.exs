defmodule Storyarn.Repo.Migrations.RestoreLocalizedTextGlobalIdentityMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.RestoreLocalizedTextGlobalIdentity

  @migration_version 20_260_817_120_000
  @index_name "localized_texts_source_locale_unique"

  if !Code.ensure_loaded?(RestoreLocalizedTextGlobalIdentity) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260817120000_restore_localized_text_global_identity.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "restore_localized_text_identity_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    create_project_scoped_schema!(prefix)
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    %{prefix: prefix}
  end

  test "replaces the deployed project-scoped index with the global identity", %{prefix: prefix} do
    insert_text!(prefix, 11, 101)
    insert_text!(prefix, 12, 102)

    assert :ok = run_migration(prefix)

    definition = index_definition(prefix)
    refute definition =~ "project_id"
    refute definition =~ "WHERE"
  end

  test "refuses duplicates before replacing the deployed index", %{prefix: prefix} do
    insert_text!(prefix, 21, 201)
    insert_text!(prefix, 22, 201)

    assert_raise Ecto.MigrationError, ~r/must be cleaned/, fn ->
      run_migration(prefix)
    end

    definition = index_definition(prefix)
    assert definition =~ "project_id"
    assert definition =~ "archived_at IS NULL"
  end

  defp create_project_scoped_schema!(prefix) do
    Repo.query!("""
    CREATE TABLE #{prefix}.localized_texts (
      id bigserial PRIMARY KEY,
      project_id bigint NOT NULL,
      source_type text NOT NULL,
      source_id bigint NOT NULL,
      source_field text NOT NULL,
      locale_code text NOT NULL,
      archived_at timestamp(0) without time zone
    )
    """)

    Repo.query!("""
    CREATE UNIQUE INDEX #{@index_name}
    ON #{prefix}.localized_texts (
      project_id, source_type, source_id, source_field, locale_code
    )
    WHERE archived_at IS NULL
    """)
  end

  defp insert_text!(prefix, project_id, source_id) do
    Repo.query!(
      """
      INSERT INTO #{prefix}.localized_texts (
        project_id, source_type, source_id, source_field, locale_code
      )
      VALUES ($1, 'flow_node', $2, 'text', 'es')
      """,
      [project_id, source_id]
    )
  end

  defp run_migration(prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      RestoreLocalizedTextGlobalIdentity,
      :forward,
      :up,
      :up,
      prefix: prefix,
      log: false
    )
  end

  defp index_definition(prefix) do
    [[definition]] =
      Repo.query!(
        """
        SELECT pg_get_indexdef(index_row.oid)
        FROM pg_class AS index_row
        JOIN pg_namespace AS namespace_row ON namespace_row.oid = index_row.relnamespace
        WHERE namespace_row.nspname = $1 AND index_row.relname = $2
        """,
        [prefix, @index_name]
      ).rows

    definition
  end
end
