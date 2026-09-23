defmodule Storyarn.Repo.Migrations.AddIdeationDecisionCommentAnchor do
  use Ecto.Migration

  def up do
    alter table(:comment_threads) do
      add :ideation_decision_id, references(:ideation_decisions, on_delete: :nilify_all)
    end

    create index(:comment_threads, [:ideation_decision_id])

    drop index(:comment_threads, [:project_id, :last_activity_at, :id],
           name: :ideation_comment_activity
         )

    create index(:comment_threads, [:project_id, :last_activity_at, :id],
             name: :ideation_comment_activity,
             where:
               "source_type IN ('ideation_session', 'ideation_idea', 'ideation_group', 'ideation_decision')"
           )

    # A decision's discussion is an Ideation anchor without a canvas position.
    # The established Ideation branches and other editor constraints are retained.
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
          CASE WHEN source_type = ''ideation_decision'' THEN
            flow_node_id IS NULL AND flow_canvas_id IS NULL AND scene_canvas_id IS NULL AND
            sheet_canvas_id IS NULL AND source_recovery_identity IS NOT NULL AND
            ideation_idea_id IS NULL AND ideation_group_id IS NULL AND
            (ideation_session_id IS NULL OR ideation_session_id = container_id) AND
            position_x IS NULL AND position_y IS NULL AND
            (ideation_decision_id IS NULL OR ideation_decision_id = source_id)
          ELSE ideation_decision_id IS NULL AND (%s) END)', constraint_name, old_expression);
      END LOOP;
    END $$;
    """)
  end

  def down do
    raise Ecto.MigrationError, "Preserve decision discussions by rolling forward."
  end
end
