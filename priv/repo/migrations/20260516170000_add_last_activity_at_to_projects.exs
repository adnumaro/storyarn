defmodule Storyarn.Repo.Migrations.AddLastActivityAtToProjects do
  use Ecto.Migration

  @direct_project_tables ~w(
    assets
    sheets
    flows
    scenes
    screenplays
    localized_texts
    project_languages
    localization_glossary_entries
    translation_provider_configs
  )

  @sheet_tables ~w(blocks sheet_avatars)
  @block_tables ~w(table_columns table_rows block_gallery_images variable_references)
  @flow_tables ~w(flow_nodes flow_connections)
  @flow_node_tables ~w(
    flow_node_sequence_configs
    flow_node_sequence_tracks
    flow_node_sequence_visual_layers
  )
  @scene_tables ~w(
    scene_layers
    scene_zones
    scene_pins
    scene_connections
    scene_annotations
    scene_ambient_flows
  )
  @screenplay_tables ~w(screenplay_elements)

  def up do
    alter table(:projects) do
      add :last_activity_at, :utc_datetime
    end

    execute(backfill_activity_sql())

    execute(
      "UPDATE projects SET last_activity_at = #{utc_now_sql()} WHERE last_activity_at IS NULL"
    )

    execute("ALTER TABLE projects ALTER COLUMN last_activity_at SET DEFAULT #{utc_now_sql()}")
    execute("ALTER TABLE projects ALTER COLUMN last_activity_at SET NOT NULL")

    create index(:projects, [:workspace_id, :last_activity_at],
             where: "deleted_at IS NULL",
             name: :projects_workspace_last_activity_index
           )

    create_touch_functions()
    create_touch_triggers()
  end

  def down do
    drop_touch_triggers()
    drop_touch_functions()

    drop_if_exists index(:projects, [:workspace_id, :last_activity_at],
                     name: :projects_workspace_last_activity_index
                   )

    alter table(:projects) do
      remove :last_activity_at
    end
  end

  defp create_touch_triggers do
    for table <- @direct_project_tables do
      create_touch_trigger(table, "storyarn_touch_project_activity_from_project_id")
    end

    for table <- @sheet_tables do
      create_touch_trigger(table, "storyarn_touch_project_activity_from_sheet_id")
    end

    for table <- @block_tables do
      create_touch_trigger(table, "storyarn_touch_project_activity_from_block_id")
    end

    for table <- @flow_tables do
      create_touch_trigger(table, "storyarn_touch_project_activity_from_flow_id")
    end

    for table <- @flow_node_tables do
      create_touch_trigger(table, "storyarn_touch_project_activity_from_flow_node_id")
    end

    for table <- @scene_tables do
      create_touch_trigger(table, "storyarn_touch_project_activity_from_scene_id")
    end

    for table <- @screenplay_tables do
      create_touch_trigger(table, "storyarn_touch_project_activity_from_screenplay_id")
    end
  end

  defp drop_touch_triggers do
    for table <- all_touch_tables() do
      execute("DROP TRIGGER IF EXISTS trg_#{table}_touch_project_activity ON #{table}")
    end
  end

  defp create_touch_trigger(table, function_name) do
    execute("""
    CREATE TRIGGER trg_#{table}_touch_project_activity
    AFTER INSERT OR UPDATE ON #{table}
    FOR EACH ROW
    EXECUTE FUNCTION #{function_name}();
    """)
  end

  defp create_touch_functions do
    execute("""
    CREATE OR REPLACE FUNCTION storyarn_touch_project_activity(target_project_id bigint)
    RETURNS void AS $$
    BEGIN
      IF target_project_id IS NULL THEN
        RETURN;
      END IF;

      UPDATE projects
      SET last_activity_at = GREATEST(
        COALESCE(last_activity_at, updated_at, inserted_at, '1970-01-01 00:00:00'::timestamp),
        #{utc_now_sql()}
      )
      WHERE id = target_project_id;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION storyarn_touch_project_activity_from_project_id()
    RETURNS TRIGGER AS $$
    BEGIN
      PERFORM storyarn_touch_project_activity(NEW.project_id);
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION storyarn_touch_project_activity_from_sheet_id()
    RETURNS TRIGGER AS $$
    DECLARE
      target_project_id bigint;
    BEGIN
      SELECT project_id INTO target_project_id
      FROM sheets
      WHERE id = NEW.sheet_id;

      PERFORM storyarn_touch_project_activity(target_project_id);
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION storyarn_touch_project_activity_from_block_id()
    RETURNS TRIGGER AS $$
    DECLARE
      target_project_id bigint;
    BEGIN
      SELECT s.project_id INTO target_project_id
      FROM blocks AS b
      JOIN sheets AS s ON s.id = b.sheet_id
      WHERE b.id = NEW.block_id;

      PERFORM storyarn_touch_project_activity(target_project_id);
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION storyarn_touch_project_activity_from_flow_id()
    RETURNS TRIGGER AS $$
    DECLARE
      target_project_id bigint;
    BEGIN
      SELECT project_id INTO target_project_id
      FROM flows
      WHERE id = NEW.flow_id;

      PERFORM storyarn_touch_project_activity(target_project_id);
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION storyarn_touch_project_activity_from_flow_node_id()
    RETURNS TRIGGER AS $$
    DECLARE
      target_project_id bigint;
    BEGIN
      SELECT f.project_id INTO target_project_id
      FROM flow_nodes AS n
      JOIN flows AS f ON f.id = n.flow_id
      WHERE n.id = NEW.flow_node_id;

      PERFORM storyarn_touch_project_activity(target_project_id);
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION storyarn_touch_project_activity_from_scene_id()
    RETURNS TRIGGER AS $$
    DECLARE
      target_project_id bigint;
    BEGIN
      SELECT project_id INTO target_project_id
      FROM scenes
      WHERE id = NEW.scene_id;

      PERFORM storyarn_touch_project_activity(target_project_id);
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION storyarn_touch_project_activity_from_screenplay_id()
    RETURNS TRIGGER AS $$
    DECLARE
      target_project_id bigint;
    BEGIN
      SELECT project_id INTO target_project_id
      FROM screenplays
      WHERE id = NEW.screenplay_id;

      PERFORM storyarn_touch_project_activity(target_project_id);
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)
  end

  defp drop_touch_functions do
    for function <- touch_functions() do
      execute("DROP FUNCTION IF EXISTS #{function}()")
    end

    execute("DROP FUNCTION IF EXISTS storyarn_touch_project_activity(bigint)")
  end

  defp touch_functions do
    ~w(
      storyarn_touch_project_activity_from_project_id
      storyarn_touch_project_activity_from_sheet_id
      storyarn_touch_project_activity_from_block_id
      storyarn_touch_project_activity_from_flow_id
      storyarn_touch_project_activity_from_flow_node_id
      storyarn_touch_project_activity_from_scene_id
      storyarn_touch_project_activity_from_screenplay_id
    )
  end

  defp all_touch_tables do
    @direct_project_tables ++
      @sheet_tables ++
      @block_tables ++
      @flow_tables ++
      @flow_node_tables ++
      @scene_tables ++
      @screenplay_tables
  end

  defp backfill_activity_sql do
    """
    UPDATE projects AS p
    SET last_activity_at = GREATEST(
      #{Enum.join(backfill_activity_candidates(), ",\n  ")}
    )
    WHERE p.last_activity_at IS NULL
    """
  end

  defp backfill_activity_candidates do
    [
      "COALESCE(p.updated_at, p.inserted_at, #{utc_now_sql()})",
      "COALESCE((SELECT max(updated_at) FROM assets WHERE project_id = p.id), p.updated_at)",
      "COALESCE((SELECT max(updated_at) FROM sheets WHERE project_id = p.id), p.updated_at)",
      """
      COALESCE((
        SELECT max(b.updated_at)
        FROM blocks AS b
        JOIN sheets AS s ON s.id = b.sheet_id
        WHERE s.project_id = p.id
      ), p.updated_at)
      """,
      """
      COALESCE((
        SELECT max(c.updated_at)
        FROM table_columns AS c
        JOIN blocks AS b ON b.id = c.block_id
        JOIN sheets AS s ON s.id = b.sheet_id
        WHERE s.project_id = p.id
      ), p.updated_at)
      """,
      """
      COALESCE((
        SELECT max(r.updated_at)
        FROM table_rows AS r
        JOIN blocks AS b ON b.id = r.block_id
        JOIN sheets AS s ON s.id = b.sheet_id
        WHERE s.project_id = p.id
      ), p.updated_at)
      """,
      """
      COALESCE((
        SELECT max(g.updated_at)
        FROM block_gallery_images AS g
        JOIN blocks AS b ON b.id = g.block_id
        JOIN sheets AS s ON s.id = b.sheet_id
        WHERE s.project_id = p.id
      ), p.updated_at)
      """,
      """
      COALESCE((
        SELECT max(sa.updated_at)
        FROM sheet_avatars AS sa
        JOIN sheets AS s ON s.id = sa.sheet_id
        WHERE s.project_id = p.id
      ), p.updated_at)
      """,
      """
      COALESCE((
        SELECT max(v.updated_at)
        FROM variable_references AS v
        JOIN blocks AS b ON b.id = v.block_id
        JOIN sheets AS s ON s.id = b.sheet_id
        WHERE s.project_id = p.id
      ), p.updated_at)
      """,
      "COALESCE((SELECT max(updated_at) FROM flows WHERE project_id = p.id), p.updated_at)",
      """
      COALESCE((
        SELECT max(n.updated_at)
        FROM flow_nodes AS n
        JOIN flows AS f ON f.id = n.flow_id
        WHERE f.project_id = p.id
      ), p.updated_at)
      """,
      """
      COALESCE((
        SELECT max(c.updated_at)
        FROM flow_connections AS c
        JOIN flows AS f ON f.id = c.flow_id
        WHERE f.project_id = p.id
      ), p.updated_at)
      """,
      """
      COALESCE((
        SELECT max(sc.updated_at)
        FROM flow_node_sequence_configs AS sc
        JOIN flow_nodes AS n ON n.id = sc.flow_node_id
        JOIN flows AS f ON f.id = n.flow_id
        WHERE f.project_id = p.id
      ), p.updated_at)
      """,
      """
      COALESCE((
        SELECT max(st.updated_at)
        FROM flow_node_sequence_tracks AS st
        JOIN flow_nodes AS n ON n.id = st.flow_node_id
        JOIN flows AS f ON f.id = n.flow_id
        WHERE f.project_id = p.id
      ), p.updated_at)
      """,
      """
      COALESCE((
        SELECT max(vl.updated_at)
        FROM flow_node_sequence_visual_layers AS vl
        JOIN flow_nodes AS n ON n.id = vl.flow_node_id
        JOIN flows AS f ON f.id = n.flow_id
        WHERE f.project_id = p.id
      ), p.updated_at)
      """,
      "COALESCE((SELECT max(updated_at) FROM scenes WHERE project_id = p.id), p.updated_at)",
      """
      COALESCE((
        SELECT max(l.updated_at)
        FROM scene_layers AS l
        JOIN scenes AS s ON s.id = l.scene_id
        WHERE s.project_id = p.id
      ), p.updated_at)
      """,
      """
      COALESCE((
        SELECT max(z.updated_at)
        FROM scene_zones AS z
        JOIN scenes AS s ON s.id = z.scene_id
        WHERE s.project_id = p.id
      ), p.updated_at)
      """,
      """
      COALESCE((
        SELECT max(sp.updated_at)
        FROM scene_pins AS sp
        JOIN scenes AS s ON s.id = sp.scene_id
        WHERE s.project_id = p.id
      ), p.updated_at)
      """,
      """
      COALESCE((
        SELECT max(sc.updated_at)
        FROM scene_connections AS sc
        JOIN scenes AS s ON s.id = sc.scene_id
        WHERE s.project_id = p.id
      ), p.updated_at)
      """,
      """
      COALESCE((
        SELECT max(a.updated_at)
        FROM scene_annotations AS a
        JOIN scenes AS s ON s.id = a.scene_id
        WHERE s.project_id = p.id
      ), p.updated_at)
      """,
      """
      COALESCE((
        SELECT max(af.updated_at)
        FROM scene_ambient_flows AS af
        JOIN scenes AS s ON s.id = af.scene_id
        WHERE s.project_id = p.id
      ), p.updated_at)
      """,
      "COALESCE((SELECT max(updated_at) FROM screenplays WHERE project_id = p.id), p.updated_at)",
      """
      COALESCE((
        SELECT max(e.updated_at)
        FROM screenplay_elements AS e
        JOIN screenplays AS sp ON sp.id = e.screenplay_id
        WHERE sp.project_id = p.id
      ), p.updated_at)
      """,
      "COALESCE((SELECT max(updated_at) FROM localized_texts WHERE project_id = p.id), p.updated_at)",
      "COALESCE((SELECT max(updated_at) FROM project_languages WHERE project_id = p.id), p.updated_at)",
      """
      COALESCE((
        SELECT max(updated_at)
        FROM localization_glossary_entries
        WHERE project_id = p.id
      ), p.updated_at)
      """,
      """
      COALESCE((
        SELECT max(updated_at)
        FROM translation_provider_configs
        WHERE project_id = p.id
      ), p.updated_at)
      """
    ]
  end

  defp utc_now_sql do
    "date_trunc('second', timezone('UTC', now()))::timestamp"
  end
end
