defmodule Storyarn.Repo.Migrations.CommentContextMigrationTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Repo.Migrations.SeparateCommentContextFromSurface

  @version 20_260_910_120_000

  if !Code.ensure_loaded?(SeparateCommentContextFromSurface) do
    Code.require_file(
      Path.expand("../../../../priv/repo/migrations/20260910120000_separate_comment_context_from_surface.exs", __DIR__)
    )
  end

  setup do
    prefix = "comment_context_migration_#{System.unique_integer([:positive])}"
    Repo.query!("CREATE SCHEMA #{prefix}")
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
    create_legacy_schema()
    %{prefix: prefix}
  end

  test "upgrade preserves legacy discussions, offsets, owner identity and unverified orphans", %{prefix: prefix} do
    insert_legacy_thread(1, 1, 1, nil, nil)
    insert_legacy_thread(2, 2, 2, 25.0, -10.0)
    insert_legacy_thread(3, 3, nil, 10.0, 20.0)

    Repo.query!("""
    INSERT INTO comment_messages (id, thread_id, body, client_request_id, request_hash)
    VALUES (1, 1, 'Preserve this discussion', 'original-request', 'original-fingerprint')
    """)

    assert :ok = run_migration(prefix)

    assert [
             [1, "flow_canvas", 1, 1, "The Flow", "flow_node", "1", "Original node", 16.0, 16.0, 116.0, 216.0],
             [
               2,
               "flow_canvas",
               1,
               1,
               "The Flow",
               "flow_node",
               "2",
               "Original node",
               25.0,
               -10.0,
               20_000_025.0,
               -30_000_010.0
             ],
             [3, "flow_node", 3, nil, "Original node", nil, nil, nil, nil, nil, 10.0, 20.0]
           ] ==
             rows("""
             SELECT id, source_type, source_id, flow_canvas_id, source_label, context_type, context_id,
               context_label, context_offset_x, context_offset_y, position_x, position_y
             FROM comment_threads ORDER BY id
             """)

    assert [[true, true, 7, 1]] =
             rows("""
             SELECT source_inserted_at = '2026-09-01'::timestamp,
               context_inserted_at = '2026-09-02'::timestamp, revision, message_count
             FROM comment_threads WHERE id = 1
             """)

    assert [[1, 1, "Preserve this discussion", "original-request", "original-fingerprint"]] =
             rows("SELECT * FROM comment_messages")
  end

  test "migration does not attach a legacy row to a reused node identity", %{prefix: prefix} do
    insert_legacy_thread(1, 1, 1, 10.0, 20.0)
    Repo.query!("UPDATE flow_nodes SET inserted_at = '2026-09-03' WHERE id = 1")
    assert :ok = run_migration(prefix)

    assert [["flow_node", nil, nil, 10.0, 20.0]] =
             rows("SELECT source_type, flow_canvas_id, context_type, position_x, position_y FROM comment_threads")
  end

  test "node deletion captures the current pin position and tombstones prevent ID reuse", %{prefix: prefix} do
    insert_legacy_thread(1, 1, 1, 25.0, -10.0)
    assert :ok = run_migration(prefix)
    Repo.query!("UPDATE flow_nodes SET position_x = 500, position_y = 600 WHERE id = 1")
    Repo.query!("DELETE FROM flow_nodes WHERE id = 1")

    assert [[1, nil, "1", "Original node", 525.0, 590.0, 7]] =
             rows("""
             SELECT flow_canvas_id, flow_node_id, context_id, context_label, position_x, position_y, revision
             FROM comment_threads
             """)

    Repo.query!("""
    INSERT INTO flow_nodes (id, flow_id, position_x, position_y, inserted_at)
    VALUES (1, 1, 100, 200, '2026-09-02')
    """)

    assert [[nil, "1"]] = rows("SELECT flow_node_id, context_id FROM comment_threads")
  end

  test "a simultaneous move and soft deletion captures the final position only once", %{prefix: prefix} do
    insert_legacy_thread(1, 1, 1, 25.0, -10.0)
    assert :ok = run_migration(prefix)

    Repo.query!("""
    UPDATE flow_nodes SET position_x = 500, position_y = 600, deleted_at = '2026-09-10' WHERE id = 1
    """)

    Repo.query!("UPDATE flow_nodes SET position_x = 999, position_y = 999 WHERE id = 1")
    Repo.query!("DELETE FROM flow_nodes WHERE id = 1")

    assert [[525.0, 590.0, 7]] = rows("SELECT position_x, position_y, revision FROM comment_threads")
  end

  test "context identity and shape constraints reject inconsistent live pointers", %{prefix: prefix} do
    insert_legacy_thread(1, 1, 1, nil, nil)
    assert :ok = run_migration(prefix)

    assert_constraint(
      "UPDATE comment_threads SET context_id = '2' WHERE id = 1",
      "comment_threads_context_identity"
    )

    assert_constraint(
      "UPDATE comment_threads SET context_type = 'sheet_block' WHERE id = 1",
      "comment_threads_context_shape"
    )

    assert_constraint(
      "UPDATE comment_threads SET position_x = 'NaN'::float8 WHERE id = 1",
      "comment_threads_position"
    )
  end

  test "a disappeared row remains detached even if its UUID is reused in the same transaction", %{prefix: prefix} do
    assert :ok = run_migration(prefix)
    group_id = insert_group_comment()

    Repo.query!("UPDATE blocks SET column_group_id = NULL WHERE id = 1")
    assert [[group_id]] == rows("SELECT context_sheet_column_group_id::text FROM comment_threads")

    Repo.query!("UPDATE blocks SET column_group_id = NULL WHERE id = 2")

    assert [[nil, group_id, "Original row", 7]] ==
             rows("SELECT context_sheet_column_group_id, context_id, context_label, revision FROM comment_threads")

    Repo.query!("UPDATE blocks SET column_group_id = $1::text::uuid WHERE id IN (1, 2)", [group_id])
    Repo.query!("SET CONSTRAINTS invalidate_comment_column_group_deferred IMMEDIATE")
    assert [[nil, group_id]] == rows("SELECT context_sheet_column_group_id, context_id FROM comment_threads")
  end

  test "group deletion still invalidates context after the owning Sheet FK is nilled", %{prefix: prefix} do
    assert :ok = run_migration(prefix)
    group_id = insert_group_comment()
    Repo.query!("UPDATE comment_threads SET sheet_canvas_id = NULL")
    Repo.query!("DELETE FROM blocks")

    assert [[nil, nil, group_id]] ==
             rows("SELECT sheet_canvas_id, context_sheet_column_group_id, context_id FROM comment_threads")
  end

  test "rollback refuses to discard discussions or their new contextual identity", %{prefix: prefix} do
    insert_legacy_thread(1, 1, 1, nil, nil)
    assert :ok = run_migration(prefix)
    before = rows("SELECT * FROM comment_threads")

    assert_raise Ecto.MigrationError, ~r/irreversible.*Preserve comment threads and their history/, fn ->
      SeparateCommentContextFromSurface.down()
    end

    assert rows("SELECT * FROM comment_threads") == before
  end

  defp create_legacy_schema do
    Repo.query!("""
    CREATE TABLE flows (id bigint PRIMARY KEY, project_id bigint, name text, inserted_at timestamp(0))
    """)

    Repo.query!("""
    CREATE TABLE flow_nodes (
      id bigint PRIMARY KEY, flow_id bigint REFERENCES flows(id) ON DELETE CASCADE,
      position_x float8, position_y float8, inserted_at timestamp(0), deleted_at timestamp(0)
    )
    """)

    Repo.query!("CREATE TABLE sheets (id bigint PRIMARY KEY)")

    Repo.query!("""
    CREATE TABLE blocks (
      id bigint PRIMARY KEY, sheet_id bigint REFERENCES sheets(id) ON DELETE CASCADE,
      column_group_id uuid, deleted_at timestamp(0)
    )
    """)

    for table <- ~w(scenes scene_pins scene_zones scene_connections scene_annotations) do
      Repo.query!("CREATE TABLE #{table} (id bigint PRIMARY KEY)")
    end

    Repo.query!("""
    CREATE TABLE comment_threads (
      id bigint PRIMARY KEY, project_id bigint NOT NULL, source_type text NOT NULL, source_id bigint NOT NULL,
      container_id bigint NOT NULL, source_inserted_at timestamp(0) NOT NULL, source_label text NOT NULL,
      flow_node_id bigint REFERENCES flow_nodes(id) ON DELETE SET NULL,
      flow_canvas_id bigint REFERENCES flows(id) ON DELETE SET NULL,
      scene_canvas_id bigint REFERENCES scenes(id) ON DELETE SET NULL,
      sheet_canvas_id bigint REFERENCES sheets(id) ON DELETE SET NULL,
      position_x float8, position_y float8, status text DEFAULT 'open', revision integer DEFAULT 7,
      message_count integer DEFAULT 1,
      CONSTRAINT comment_threads_anchor_shape CHECK (true),
      CONSTRAINT comment_threads_anchor_identity CHECK (true),
      CONSTRAINT comment_threads_position CHECK (true)
    )
    """)

    Repo.query!("""
    CREATE TABLE comment_messages (
      id bigint PRIMARY KEY, thread_id bigint REFERENCES comment_threads(id), body text,
      client_request_id text, request_hash text
    )
    """)

    Repo.query!("INSERT INTO flows VALUES (1, 1, 'The Flow', '2026-09-01')")

    Repo.query!("""
    INSERT INTO flow_nodes (id, flow_id, position_x, position_y, inserted_at)
    VALUES (1, 1, 100, 200, '2026-09-02'), (2, 1, 20000000, -30000000, '2026-09-02')
    """)
  end

  defp insert_legacy_thread(id, source_id, node_id, x, y) do
    Repo.query!(
      """
      INSERT INTO comment_threads (
        id, project_id, source_type, source_id, flow_node_id, container_id,
        source_inserted_at, source_label, position_x, position_y
      ) VALUES ($1, 1, 'flow_node', $2, $3, 1, '2026-09-02', 'Original node', $4, $5)
      """,
      [id, source_id, node_id, x, y]
    )
  end

  defp insert_group_comment do
    group_id = Ecto.UUID.generate()
    Repo.query!("INSERT INTO sheets VALUES (1)")

    Repo.query!(
      "INSERT INTO blocks (id, sheet_id, column_group_id) VALUES (1, 1, $1::text::uuid), (2, 1, $1::text::uuid)",
      [group_id]
    )

    Repo.query!(
      """
      INSERT INTO comment_threads (
        id, project_id, source_type, source_id, sheet_canvas_id, container_id,
        source_inserted_at, source_label, position_x, position_y,
        context_type, context_id, context_label, context_sheet_column_group_id
      ) VALUES (1, 1, 'sheet_canvas', 1, 1, 1, '2026-09-01', 'The Sheet', 10, 800,
        'sheet_column_group', $1::text, 'Original row', $1::text::uuid)
      """,
      [group_id]
    )

    group_id
  end

  defp rows(sql), do: Repo.query!(sql).rows

  defp assert_constraint(sql, constraint) do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation, constraint: ^constraint}}} =
             Repo.query(sql, [], mode: :savepoint)
  end

  defp run_migration(prefix) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @version,
      SeparateCommentContextFromSurface,
      :forward,
      :up,
      :up,
      prefix: prefix,
      log: false
    )
  end
end
