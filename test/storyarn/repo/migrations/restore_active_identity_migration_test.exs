defmodule Storyarn.Repo.Migrations.RestoreActiveIdentityMigrationTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.ScopeRestoreIdentitiesToActiveRows

  @migration_version 20_260_813_102_000

  if !Code.ensure_loaded?(ScopeRestoreIdentitiesToActiveRows) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260813102000_scope_flow_uniqueness_to_active_rows.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "restore_active_identity_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    create_pre_migration_schema!(prefix)
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    %{prefix: prefix}
  end

  test "trashed main and dialogue identities no longer block exact active replacements", %{
    prefix: prefix
  } do
    trashed_at = now()
    old_flow_id = insert_flow!(prefix, is_main: true, deleted_at: trashed_at)
    old_node_id = insert_dialogue!(prefix, old_flow_id, "dialogue.shared", deleted_at: trashed_at)
    old_flow_before = flow_row(prefix, old_flow_id)
    old_node_before = node_row(prefix, old_node_id)

    assert :ok = run_migration(:up, prefix)

    new_flow_id = insert_flow!(prefix, is_main: true)
    insert_dialogue!(prefix, new_flow_id, "dialogue.shared")

    assert flow_row(prefix, old_flow_id) == old_flow_before
    assert node_row(prefix, old_node_id) == old_node_before

    assert index_definition(prefix, "flows_project_id_is_main_index") =~
             "deleted_at IS NULL"
  end

  test "two active main flows and dialogue IDs remain rejected", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    flow_id = insert_flow!(prefix, is_main: true)
    insert_dialogue!(prefix, flow_id, "dialogue.unique")

    assert_unique_violation(fn -> insert_flow(prefix, is_main: true) end)

    other_flow_id = insert_flow!(prefix)
    assert_unique_violation(fn -> insert_dialogue(prefix, other_flow_id, "dialogue.unique") end)
  end

  test "reactivating a node or parent flow cannot bypass dialogue uniqueness", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    active_flow_id = insert_flow!(prefix)
    insert_dialogue!(prefix, active_flow_id, "dialogue.collision")

    trashed_node_id =
      insert_dialogue!(prefix, active_flow_id, "dialogue.collision", deleted_at: now())

    assert_unique_violation(fn ->
      Repo.query(
        "UPDATE #{prefix}.flow_nodes SET deleted_at = NULL WHERE id = $1",
        [trashed_node_id],
        mode: :savepoint
      )
    end)

    trashed_flow_id = insert_flow!(prefix, deleted_at: now())
    insert_dialogue!(prefix, trashed_flow_id, "dialogue.collision")

    assert_unique_violation(fn ->
      Repo.query(
        "UPDATE #{prefix}.flows SET deleted_at = NULL WHERE id = $1",
        [trashed_flow_id],
        mode: :savepoint
      )
    end)

    duplicate_flow_id = insert_flow!(prefix, deleted_at: now())
    insert_dialogue!(prefix, duplicate_flow_id, "dialogue.inside-trashed-flow")
    insert_dialogue!(prefix, duplicate_flow_id, "dialogue.inside-trashed-flow")

    assert_unique_violation(fn ->
      Repo.query(
        "UPDATE #{prefix}.flows SET deleted_at = NULL WHERE id = $1",
        [duplicate_flow_id],
        mode: :savepoint
      )
    end)
  end

  test "archived languages keep their identity while active uniqueness remains exact", %{
    prefix: prefix
  } do
    archived_id =
      insert_language!(prefix,
        locale_code: "en",
        name: "Old English",
        is_source: true,
        archived_at: now()
      )

    archived_before = language_row(prefix, archived_id)
    assert :ok = run_migration(:up, prefix)

    insert_language!(prefix, locale_code: "en", name: "English", is_source: true)

    assert_unique_violation(fn ->
      insert_language(prefix, locale_code: "en", name: "Another English")
    end)

    assert_unique_violation(fn ->
      insert_language(prefix, locale_code: "es", name: "Spanish", is_source: true)
    end)

    insert_language!(prefix,
      locale_code: "fr",
      name: "Archived French",
      is_source: true,
      archived_at: now()
    )

    assert language_row(prefix, archived_id) == archived_before

    assert index_definition(prefix, "project_languages_project_id_locale_code_index") =~
             "archived_at IS NULL"

    assert index_definition(prefix, "project_languages_one_source") =~
             "archived_at IS NULL"
  end

  test "down is reversible only before active and trash identities coexist", %{prefix: prefix} do
    assert :ok = run_migration(:up, prefix)
    assert :ok = run_migration(:down, prefix)

    assert index_definition(prefix, "flows_project_id_is_main_index") =~
             "WHERE (is_main = true)"

    refute index_definition(prefix, "flows_project_id_is_main_index") =~ "deleted_at"

    assert trigger_definition(prefix, "flow_nodes_dialogue_localization_id_unique") =~
             "UPDATE OF type, data, flow_id"

    assert :ok = run_migration(:up, prefix)
    insert_flow!(prefix, is_main: true, deleted_at: now())
    insert_flow!(prefix, is_main: true)

    assert_raise Ecto.MigrationError, ~r/cannot be rolled back/, fn ->
      run_migration(:down, prefix)
    end

    assert index_definition(prefix, "flows_project_id_is_main_index") =~ "deleted_at IS NULL"
  end

  defp create_pre_migration_schema!(prefix) do
    Repo.query!("""
    CREATE TABLE #{prefix}.flows (
      id bigserial PRIMARY KEY,
      project_id bigint NOT NULL,
      is_main boolean NOT NULL DEFAULT false,
      deleted_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL DEFAULT clock_timestamp(),
      updated_at timestamp(0) without time zone NOT NULL DEFAULT clock_timestamp()
    )
    """)

    Repo.query!("""
    CREATE UNIQUE INDEX flows_project_id_is_main_index
    ON #{prefix}.flows (project_id, is_main)
    WHERE is_main = true
    """)

    Repo.query!("""
    CREATE TABLE #{prefix}.flow_nodes (
      id bigserial PRIMARY KEY,
      flow_id bigint NOT NULL REFERENCES #{prefix}.flows(id) ON DELETE CASCADE,
      type text NOT NULL,
      data jsonb NOT NULL DEFAULT '{}'::jsonb,
      deleted_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL DEFAULT clock_timestamp(),
      updated_at timestamp(0) without time zone NOT NULL DEFAULT clock_timestamp()
    )
    """)

    install_historical_dialogue_contract!(prefix)

    Repo.query!("""
    CREATE TABLE #{prefix}.project_languages (
      id bigserial PRIMARY KEY,
      project_id bigint NOT NULL,
      locale_code varchar(35) NOT NULL,
      name text NOT NULL,
      is_source boolean NOT NULL DEFAULT false,
      archived_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL DEFAULT clock_timestamp(),
      updated_at timestamp(0) without time zone NOT NULL DEFAULT clock_timestamp()
    )
    """)

    Repo.query!("""
    CREATE UNIQUE INDEX project_languages_project_id_locale_code_index
    ON #{prefix}.project_languages (project_id, locale_code)
    """)

    Repo.query!("""
    CREATE UNIQUE INDEX project_languages_one_source
    ON #{prefix}.project_languages (project_id)
    WHERE is_source = true
    """)
  end

  defp install_historical_dialogue_contract!(prefix) do
    Repo.query!("""
    CREATE FUNCTION #{prefix}.enforce_dialogue_localization_id_unique()
    RETURNS trigger AS $$
    DECLARE
      dialogue_project_id bigint;
      dialogue_localization_id text;
    BEGIN
      IF NEW.type <> 'dialogue' THEN
        RETURN NEW;
      END IF;

      dialogue_localization_id := NULLIF(NEW.data->>'localization_id', '');
      IF dialogue_localization_id IS NULL THEN
        RETURN NEW;
      END IF;

      SELECT project_id INTO dialogue_project_id FROM flows WHERE id = NEW.flow_id;
      IF dialogue_project_id IS NULL THEN
        RETURN NEW;
      END IF;

      PERFORM pg_advisory_xact_lock(4717000000000 + dialogue_project_id);

      IF EXISTS (
        SELECT 1
        FROM flow_nodes AS node
        JOIN flows AS flow ON flow.id = node.flow_id
        WHERE flow.project_id = dialogue_project_id
          AND node.type = 'dialogue'
          AND node.data->>'localization_id' = dialogue_localization_id
          AND node.id IS DISTINCT FROM NEW.id
      ) THEN
        RAISE EXCEPTION 'dialogue localization_id must be unique within the project'
          USING ERRCODE = '23505',
                CONSTRAINT = 'flow_nodes_dialogue_localization_id_unique';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    Repo.query!("""
    CREATE TRIGGER flow_nodes_dialogue_localization_id_unique
    BEFORE INSERT OR UPDATE OF type, data, flow_id ON #{prefix}.flow_nodes
    FOR EACH ROW EXECUTE FUNCTION #{prefix}.enforce_dialogue_localization_id_unique()
    """)
  end

  defp insert_flow!(prefix, overrides \\ []) do
    {:ok, %Postgrex.Result{rows: [[id]]}} = insert_flow(prefix, overrides)
    id
  end

  defp insert_flow(prefix, overrides) do
    attrs = Keyword.merge([project_id: 1, is_main: false, deleted_at: nil], overrides)

    Repo.query(
      """
      INSERT INTO #{prefix}.flows (project_id, is_main, deleted_at)
      VALUES ($1, $2, $3)
      RETURNING id
      """,
      [attrs[:project_id], attrs[:is_main], attrs[:deleted_at]],
      mode: :savepoint
    )
  end

  defp insert_dialogue!(prefix, flow_id, localization_id, overrides \\ []) do
    {:ok, %Postgrex.Result{rows: [[id]]}} =
      insert_dialogue(prefix, flow_id, localization_id, overrides)

    id
  end

  defp insert_dialogue(prefix, flow_id, localization_id, overrides \\ []) do
    attrs = Keyword.merge([deleted_at: nil], overrides)

    Repo.query(
      """
      INSERT INTO #{prefix}.flow_nodes (flow_id, type, data, deleted_at)
      VALUES ($1, 'dialogue', jsonb_build_object('localization_id', $2::text), $3)
      RETURNING id
      """,
      [flow_id, localization_id, attrs[:deleted_at]],
      mode: :savepoint
    )
  end

  defp insert_language!(prefix, overrides) do
    {:ok, %Postgrex.Result{rows: [[id]]}} = insert_language(prefix, overrides)
    id
  end

  defp insert_language(prefix, overrides) do
    attrs =
      Keyword.merge(
        [project_id: 1, locale_code: "en", name: "English", is_source: false, archived_at: nil],
        overrides
      )

    Repo.query(
      """
      INSERT INTO #{prefix}.project_languages (
        project_id, locale_code, name, is_source, archived_at
      )
      VALUES ($1, $2, $3, $4, $5)
      RETURNING id
      """,
      [
        attrs[:project_id],
        attrs[:locale_code],
        attrs[:name],
        attrs[:is_source],
        attrs[:archived_at]
      ],
      mode: :savepoint
    )
  end

  defp flow_row(prefix, id) do
    Repo.query!("SELECT * FROM #{prefix}.flows WHERE id = $1", [id]).rows
  end

  defp node_row(prefix, id) do
    Repo.query!("SELECT * FROM #{prefix}.flow_nodes WHERE id = $1", [id]).rows
  end

  defp language_row(prefix, id) do
    Repo.query!("SELECT * FROM #{prefix}.project_languages WHERE id = $1", [id]).rows
  end

  defp run_migration(direction, prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      ScopeRestoreIdentitiesToActiveRows,
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

  defp trigger_definition(prefix, trigger) do
    %Postgrex.Result{rows: [[definition]]} =
      Repo.query!(
        """
        SELECT pg_get_triggerdef(trigger_row.oid)
        FROM pg_trigger AS trigger_row
        JOIN pg_class AS table_row ON table_row.oid = trigger_row.tgrelid
        JOIN pg_namespace AS namespace_row ON namespace_row.oid = table_row.relnamespace
        WHERE namespace_row.nspname = $1 AND trigger_row.tgname = $2
        """,
        [prefix, trigger]
      )

    definition
  end
end
