defmodule Storyarn.Repo.Migrations.LocalizedTextActiveIdentityMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.ScopeLocalizedTextIdentityToActiveProject

  @migration_version 20_260_816_130_000

  if !Code.ensure_loaded?(ScopeLocalizedTextIdentityToActiveProject) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260816130000_scope_localized_text_identity_to_active_project.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "localized_text_active_identity_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    create_pre_migration_schema!(prefix)
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    %{prefix: prefix}
  end

  test "an archived row remains unchanged while its active replacement is inserted", %{
    prefix: prefix
  } do
    archived_at = now()

    archived_id =
      insert_text!(prefix,
        project_id: 11,
        source_text: "Recovery trash",
        translated_text: "Papelera de recuperación",
        archived_at: archived_at,
        archive_reason: "version_replaced"
      )

    archived_before = text_row(prefix, archived_id)

    assert :ok = run_migration(:up, prefix)

    active_id =
      insert_text!(prefix,
        project_id: 11,
        source_text: "Snapshot state",
        translated_text: "Estado del snapshot"
      )

    assert active_id != archived_id
    assert text_row(prefix, archived_id) == archived_before

    assert [[^active_id, 11, "Snapshot state", "Estado del snapshot", nil, nil]] =
             selected_text_row(prefix, active_id)

    definition = index_definition(prefix)
    assert definition =~ "project_id"
    assert definition =~ "archived_at IS NULL"
  end

  test "active identity is isolated by project and remains unique inside one project", %{
    prefix: prefix
  } do
    assert :ok = run_migration(:up, prefix)

    first_id = insert_text!(prefix, project_id: 21, source_text: "First tenant")
    second_id = insert_text!(prefix, project_id: 22, source_text: "Second tenant")

    assert first_id != second_id

    assert_unique_violation(fn ->
      insert_text(prefix, project_id: 21, source_text: "Duplicate active identity")
    end)

    assert [[^first_id, 21, "First tenant", nil, nil, nil]] =
             selected_text_row(prefix, first_id)

    assert [[^second_id, 22, "Second tenant", nil, nil, nil]] =
             selected_text_row(prefix, second_id)
  end

  test "down fails closed once active and archived identities coexist", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    assert :ok = run_migration(:down, prefix)

    historical_definition = index_definition(prefix)
    refute historical_definition =~ "project_id"
    refute historical_definition =~ "WHERE"

    assert :ok = run_migration(:up, prefix)
    insert_text!(prefix, project_id: 31, archived_at: now(), archive_reason: "version_replaced")
    insert_text!(prefix, project_id: 31)

    assert_raise Ecto.MigrationError, ~r/cannot be rolled back/, fn ->
      run_migration(:down, prefix)
    end

    active_definition = index_definition(prefix)
    assert active_definition =~ "project_id"
    assert active_definition =~ "archived_at IS NULL"
  end

  defp create_pre_migration_schema!(prefix) do
    Repo.query!("""
    CREATE TABLE #{prefix}.localized_texts (
      id bigserial PRIMARY KEY,
      project_id bigint NOT NULL,
      source_type text NOT NULL,
      source_id bigint NOT NULL,
      source_field text NOT NULL,
      locale_code text NOT NULL,
      source_text text,
      translated_text text,
      archived_at timestamp(0) without time zone,
      archive_reason text,
      inserted_at timestamp(0) without time zone NOT NULL DEFAULT clock_timestamp(),
      updated_at timestamp(0) without time zone NOT NULL DEFAULT clock_timestamp()
    )
    """)

    Repo.query!("""
    CREATE UNIQUE INDEX localized_texts_source_locale_unique
    ON #{prefix}.localized_texts (source_type, source_id, source_field, locale_code)
    """)
  end

  defp insert_text!(prefix, overrides) do
    {:ok, %Postgrex.Result{rows: [[id]]}} = insert_text(prefix, overrides)
    id
  end

  defp insert_text(prefix, overrides) do
    attrs =
      Keyword.merge(
        [
          project_id: 1,
          source_type: "flow_node",
          source_id: 101,
          source_field: "text",
          locale_code: "es",
          source_text: nil,
          translated_text: nil,
          archived_at: nil,
          archive_reason: nil
        ],
        overrides
      )

    Repo.query(
      """
      INSERT INTO #{prefix}.localized_texts (
        project_id, source_type, source_id, source_field, locale_code,
        source_text, translated_text, archived_at, archive_reason
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      RETURNING id
      """,
      [
        attrs[:project_id],
        attrs[:source_type],
        attrs[:source_id],
        attrs[:source_field],
        attrs[:locale_code],
        attrs[:source_text],
        attrs[:translated_text],
        attrs[:archived_at],
        attrs[:archive_reason]
      ],
      mode: :savepoint
    )
  end

  defp text_row(prefix, id) do
    Repo.query!("SELECT * FROM #{prefix}.localized_texts WHERE id = $1", [id]).rows
  end

  defp selected_text_row(prefix, id) do
    Repo.query!(
      """
      SELECT id, project_id, source_text, translated_text, archived_at, archive_reason
      FROM #{prefix}.localized_texts
      WHERE id = $1
      """,
      [id]
    ).rows
  end

  defp run_migration(direction, prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      ScopeLocalizedTextIdentityToActiveProject,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end

  defp now, do: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

  defp assert_unique_violation(fun) do
    assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} = fun.()
  end

  defp index_definition(prefix) do
    %Postgrex.Result{rows: [[definition]]} =
      Repo.query!(
        """
        SELECT pg_get_indexdef(index_row.oid)
        FROM pg_class AS index_row
        JOIN pg_namespace AS namespace_row ON namespace_row.oid = index_row.relnamespace
        WHERE namespace_row.nspname = $1
          AND index_row.relname = 'localized_texts_source_locale_unique'
        """,
        [prefix]
      )

    definition
  end
end
