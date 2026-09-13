defmodule Storyarn.Repo.Migrations.AllowSpatialIdeationComments do
  use Ecto.Migration

  def up do
    # Keep the established source and recovery identity checks. Only the position
    # part of the Ideation branches changes; other editor constraints are retained.
    execute("""
    DO $$
    DECLARE constraint_name text; old_expression text;
    BEGIN
      FOREACH constraint_name IN ARRAY ARRAY[
        'comment_threads_source_type', 'comment_threads_anchor_shape',
        'comment_threads_position', 'comment_threads_anchor_identity'
      ] LOOP
        SELECT pg_get_expr(conbin, conrelid) INTO STRICT old_expression
          FROM pg_constraint WHERE conrelid = 'comment_threads'::regclass AND conname = constraint_name;
        EXECUTE format('ALTER TABLE comment_threads DROP CONSTRAINT %I', constraint_name);
        EXECUTE format('ALTER TABLE comment_threads ADD CONSTRAINT %I CHECK (
          CASE WHEN source_type IN (''ideation_session'', ''ideation_idea'', ''ideation_group'') THEN
            flow_node_id IS NULL AND flow_canvas_id IS NULL AND scene_canvas_id IS NULL AND
            sheet_canvas_id IS NULL AND source_recovery_identity IS NOT NULL AND
            (ideation_session_id IS NULL OR ideation_session_id = container_id) AND
            ((position_x IS NULL AND position_y IS NULL) OR
             (position_x IS NOT NULL AND position_y IS NOT NULL AND
              position_x BETWEEN -10000000 AND 10000000 AND position_y BETWEEN -10000000 AND 10000000)) AND
            ((source_type = ''ideation_session'' AND source_id = container_id AND
              ideation_idea_id IS NULL AND ideation_group_id IS NULL) OR
             (source_type = ''ideation_idea'' AND ideation_group_id IS NULL AND
              (ideation_idea_id IS NULL OR ideation_idea_id = source_id)) OR
             (source_type = ''ideation_group'' AND ideation_idea_id IS NULL AND
              (ideation_group_id IS NULL OR ideation_group_id = source_id)))
          ELSE (%s) END)', constraint_name, old_expression);
      END LOOP;
    END $$;
    """)
  end

  def down do
    raise Ecto.MigrationError, "Preserve comment positions by rolling forward."
  end
end
