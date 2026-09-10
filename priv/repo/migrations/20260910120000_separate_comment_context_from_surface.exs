defmodule Storyarn.Repo.Migrations.SeparateCommentContextFromSurface do
  @moduledoc false
  use Ecto.Migration

  def up do
    alter table(:comment_threads) do
      add :context_type, :string
      add :context_id, :string
      add :context_label, :string
      add :context_inserted_at, :utc_datetime
      add :context_offset_x, :float
      add :context_offset_y, :float
      add :context_sheet_block_id, references(:blocks, on_delete: :nilify_all)
      add :context_sheet_column_group_id, :uuid
      add :context_scene_pin_id, references(:scene_pins, on_delete: :nilify_all)
      add :context_scene_zone_id, references(:scene_zones, on_delete: :nilify_all)
      add :context_scene_connection_id, references(:scene_connections, on_delete: :nilify_all)
      add :context_scene_annotation_id, references(:scene_annotations, on_delete: :nilify_all)
    end

    for field <- [
          :context_sheet_block_id,
          :context_sheet_column_group_id,
          :context_scene_pin_id,
          :context_scene_zone_id,
          :context_scene_connection_id,
          :context_scene_annotation_id
        ] do
      create index(:comment_threads, [field])
    end

    create index(:comment_threads, [:project_id, :context_type, :context_id, :status])
    drop constraint(:comment_threads, :comment_threads_anchor_shape)
    drop constraint(:comment_threads, :comment_threads_position)
    drop constraint(:comment_threads, :comment_threads_anchor_identity)

    execute(legacy_conversion_sql())
    create_owner_constraints()
    create_context_constraints()
    create_node_position_trigger()
    create_column_group_triggers()
  end

  # Kept as a SQL contract so migration tests can exercise actual legacy records
  # inside the sandbox, without rolling back a shared test database's schema.
  def legacy_conversion_sql do
    """
    UPDATE comment_threads AS thread
    SET source_type = 'flow_canvas',
        source_id = flow.id,
        flow_canvas_id = flow.id,
        source_inserted_at = flow.inserted_at,
        source_label = COALESCE(NULLIF(BTRIM(flow.name), ''), CONCAT('Flow #', flow.id)),
        context_type = 'flow_node',
        context_id = node.id::text,
        context_label = thread.source_label,
        context_inserted_at = thread.source_inserted_at,
        context_offset_x = COALESCE(thread.position_x, 16),
        context_offset_y = COALESCE(thread.position_y, 16),
        position_x = CASE WHEN node.position_x > '-Infinity'::float8 AND node.position_x < 'Infinity'::float8
          THEN node.position_x + COALESCE(thread.position_x, 16) ELSE COALESCE(thread.position_x, 16) END,
        position_y = CASE WHEN node.position_y > '-Infinity'::float8 AND node.position_y < 'Infinity'::float8
          THEN node.position_y + COALESCE(thread.position_y, 16) ELSE COALESCE(thread.position_y, 16) END
    FROM flow_nodes AS node
    JOIN flows AS flow ON flow.id = node.flow_id
    WHERE thread.source_type = 'flow_node'
      AND thread.flow_node_id = node.id
      AND thread.source_id = node.id
      AND thread.source_inserted_at = node.inserted_at
      AND thread.container_id = flow.id
      AND thread.project_id = flow.project_id
    """
  end

  defp create_owner_constraints do
    create constraint(:comment_threads, :comment_threads_anchor_shape,
             check: """
             (source_type = 'flow_node' AND flow_canvas_id IS NULL AND scene_canvas_id IS NULL AND sheet_canvas_id IS NULL) OR
             (source_type = 'flow_canvas' AND scene_canvas_id IS NULL AND sheet_canvas_id IS NULL AND source_id = container_id) OR
             (source_type = 'scene_canvas' AND flow_node_id IS NULL AND flow_canvas_id IS NULL AND sheet_canvas_id IS NULL AND source_id = container_id) OR
             (source_type = 'sheet_canvas' AND flow_node_id IS NULL AND flow_canvas_id IS NULL AND scene_canvas_id IS NULL AND source_id = container_id)
             """
           )

    create constraint(:comment_threads, :comment_threads_anchor_identity,
             check: """
             (source_type = 'flow_node' AND (flow_node_id IS NULL OR flow_node_id = source_id)) OR
             (source_type = 'flow_canvas' AND (flow_canvas_id IS NULL OR flow_canvas_id = source_id)) OR
             (source_type = 'scene_canvas' AND (scene_canvas_id IS NULL OR scene_canvas_id = source_id)) OR
             (source_type = 'sheet_canvas' AND (sheet_canvas_id IS NULL OR sheet_canvas_id = source_id))
             """
           )

    # Node coordinates historically have no bound. Their absolute migrated pins
    # must stay where they were, including finite positions beyond ten million.
    create constraint(:comment_threads, :comment_threads_position,
             check: """
             (source_type = 'flow_node' AND position_x IS NULL AND position_y IS NULL) OR
             (source_type IN ('flow_node', 'flow_canvas') AND position_x IS NOT NULL AND position_y IS NOT NULL
               AND position_x > '-Infinity'::float8 AND position_x < 'Infinity'::float8
               AND position_y > '-Infinity'::float8 AND position_y < 'Infinity'::float8) OR
             (source_type = 'scene_canvas' AND position_x IS NOT NULL AND position_y IS NOT NULL
               AND position_x BETWEEN 0 AND 100 AND position_y BETWEEN 0 AND 100) OR
             (source_type = 'sheet_canvas' AND position_x IS NOT NULL AND position_y IS NOT NULL
               AND position_x BETWEEN 0 AND 100 AND position_y BETWEEN 0 AND 10000000)
             """
           )
  end

  defp create_context_constraints do
    create constraint(:comment_threads, :comment_threads_context_shape,
             check: """
             (
               context_type IS NULL AND context_id IS NULL AND context_label IS NULL
               AND context_inserted_at IS NULL AND context_offset_x IS NULL AND context_offset_y IS NULL
               AND (flow_node_id IS NULL OR source_type = 'flow_node')
               AND context_sheet_block_id IS NULL AND context_sheet_column_group_id IS NULL
               AND context_scene_pin_id IS NULL AND context_scene_zone_id IS NULL
               AND context_scene_connection_id IS NULL AND context_scene_annotation_id IS NULL
             ) OR (
               context_type IS NOT NULL AND context_id IS NOT NULL AND context_id <> '' AND context_label IS NOT NULL
               AND (context_type = 'sheet_column_group' OR context_inserted_at IS NOT NULL)
               AND (context_type <> 'sheet_column_group' OR context_inserted_at IS NULL)
               AND ((context_offset_x IS NULL AND context_offset_y IS NULL) OR
                 (context_offset_x IS NOT NULL AND context_offset_y IS NOT NULL
                   AND context_offset_x BETWEEN -10000000 AND 10000000
                   AND context_offset_y BETWEEN -10000000 AND 10000000))
               AND (
                 (source_type = 'flow_canvas' AND context_type = 'flow_node') OR
                 (source_type = 'sheet_canvas' AND context_type IN
                   ('sheet_block', 'sheet_column_group', 'sheet_cover', 'sheet_header', 'sheet_title')) OR
                 (source_type = 'scene_canvas' AND context_type IN
                   ('scene_pin', 'scene_zone', 'scene_connection', 'scene_annotation'))
               )
               AND (context_type = 'flow_node' OR flow_node_id IS NULL)
               AND (context_type = 'sheet_block' OR context_sheet_block_id IS NULL)
               AND (context_type = 'sheet_column_group' OR context_sheet_column_group_id IS NULL)
               AND (context_type = 'scene_pin' OR context_scene_pin_id IS NULL)
               AND (context_type = 'scene_zone' OR context_scene_zone_id IS NULL)
               AND (context_type = 'scene_connection' OR context_scene_connection_id IS NULL)
               AND (context_type = 'scene_annotation' OR context_scene_annotation_id IS NULL)
             )
             """
           )

    create constraint(:comment_threads, :comment_threads_context_identity,
             check: """
             (context_type IS NULL OR (
               (context_type <> 'flow_node' OR flow_node_id IS NULL OR context_id = flow_node_id::text)
               AND (context_sheet_block_id IS NULL OR context_id = context_sheet_block_id::text)
               AND (context_sheet_column_group_id IS NULL OR context_id = context_sheet_column_group_id::text)
               AND (context_scene_pin_id IS NULL OR context_id = context_scene_pin_id::text)
               AND (context_scene_zone_id IS NULL OR context_id = context_scene_zone_id::text)
               AND (context_scene_connection_id IS NULL OR context_id = context_scene_connection_id::text)
               AND (context_scene_annotation_id IS NULL OR context_id = context_scene_annotation_id::text)
               AND (context_type NOT IN ('sheet_cover', 'sheet_header', 'sheet_title') OR context_id = source_id::text)
             ))
             """
           )
  end

  defp create_node_position_trigger do
    execute("""
    CREATE FUNCTION capture_comment_node_position() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE
      pin_x float8;
      pin_y float8;
    BEGIN
      IF TG_OP = 'UPDATE' THEN
        IF OLD.deleted_at IS NOT NULL OR NEW.deleted_at IS NULL THEN RETURN NEW; END IF;
        pin_x := NEW.position_x;
        pin_y := NEW.position_y;
      ELSIF OLD.deleted_at IS NOT NULL THEN
        RETURN OLD;
      ELSE
        pin_x := OLD.position_x;
        pin_y := OLD.position_y;
      END IF;

      UPDATE comment_threads
      SET position_x = pin_x + COALESCE(context_offset_x, 16),
          position_y = pin_y + COALESCE(context_offset_y, 16)
      WHERE source_type = 'flow_canvas' AND context_type = 'flow_node'
        AND flow_node_id = OLD.id AND context_id = OLD.id::text
        AND context_inserted_at = OLD.inserted_at AND container_id = OLD.flow_id
        AND pin_x > '-Infinity'::float8 AND pin_x < 'Infinity'::float8
        AND pin_y > '-Infinity'::float8 AND pin_y < 'Infinity'::float8;

      IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER capture_comment_node_position
    BEFORE DELETE OR UPDATE OF deleted_at ON flow_nodes
    FOR EACH ROW EXECUTE FUNCTION capture_comment_node_position()
    """)
  end

  defp create_column_group_triggers do
    # The immediate check preserves a tombstone even if the UUID is reused later
    # in the same transaction. The deferred check serializes concurrent deletes
    # without holding an advisory lock while acquiring another block row lock.
    execute("""
    CREATE FUNCTION invalidate_comment_column_group() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF OLD.column_group_id IS NULL OR OLD.deleted_at IS NOT NULL THEN RETURN NULL; END IF;
      IF TG_OP = 'UPDATE' THEN
        IF NEW.sheet_id = OLD.sheet_id AND NEW.column_group_id IS NOT DISTINCT FROM OLD.column_group_id
          AND NEW.deleted_at IS NULL THEN RETURN NULL; END IF;
      END IF;

      IF TG_ARGV[0] = 'immediate' AND EXISTS (
        SELECT 1 FROM blocks
        WHERE sheet_id = OLD.sheet_id AND column_group_id = OLD.column_group_id AND deleted_at IS NULL
      ) THEN
        RETURN NULL;
      END IF;

      PERFORM pg_advisory_xact_lock(hashtextextended(
        'comment_sheet_column_group:' || OLD.sheet_id::text || ':' || OLD.column_group_id::text, 0));

      UPDATE comment_threads AS thread
      SET context_sheet_column_group_id = NULL
      WHERE thread.source_type = 'sheet_canvas' AND thread.source_id = OLD.sheet_id
        AND thread.context_type = 'sheet_column_group'
        AND thread.context_sheet_column_group_id = OLD.column_group_id
        AND NOT EXISTS (
          SELECT 1 FROM blocks AS block
          WHERE block.sheet_id = OLD.sheet_id AND block.column_group_id = OLD.column_group_id
            AND block.deleted_at IS NULL
        );
      RETURN NULL;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER invalidate_comment_column_group_immediate
    AFTER DELETE OR UPDATE OF sheet_id, column_group_id, deleted_at ON blocks
    FOR EACH ROW EXECUTE FUNCTION invalidate_comment_column_group('immediate')
    """)

    execute("""
    CREATE CONSTRAINT TRIGGER invalidate_comment_column_group_deferred
    AFTER DELETE OR UPDATE ON blocks DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION invalidate_comment_column_group('deferred')
    """)
  end

  def down do
    raise Ecto.MigrationError,
          "SeparateCommentContextFromSurface is irreversible: rollback would discard contextual identities and " <>
            "restore node ownership from canvas coordinates. Preserve comment threads and their history " <>
            "by rolling forward with a compatible migration."
  end
end
