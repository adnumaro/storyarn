defmodule Storyarn.Repo.Migrations.AddIdeationCommentAnchors do
  use Ecto.Migration

  def up do
    alter table(:comment_threads) do
      add :ideation_session_id, references(:ideation_sessions, on_delete: :nilify_all)
      add :ideation_idea_id, references(:ideation_ideas, on_delete: :nilify_all)
      add :source_recovery_identity, :uuid
    end

    create index(:comment_threads, [:ideation_session_id])
    create index(:comment_threads, [:ideation_idea_id])

    # Retain the existing, validated spatial/identity constraints verbatim and
    # extend each with the two non-spatial source shapes. No history rewrite.
    execute("""
    DO $$
    DECLARE
      constraint_name text;
      old_expression text;
      ideation_expression text :=
        'source_type IN (''ideation_session'', ''ideation_idea'') AND
         flow_node_id IS NULL AND flow_canvas_id IS NULL AND
         scene_canvas_id IS NULL AND sheet_canvas_id IS NULL AND
         position_x IS NULL AND position_y IS NULL AND
         source_recovery_identity IS NOT NULL AND
         (ideation_session_id IS NULL OR ideation_session_id = container_id) AND
         ((source_type = ''ideation_session'' AND source_id = container_id AND ideation_idea_id IS NULL) OR
          (source_type = ''ideation_idea'' AND (ideation_idea_id IS NULL OR ideation_idea_id = source_id)))';
    BEGIN
      FOREACH constraint_name IN ARRAY ARRAY[
        'comment_threads_source_type', 'comment_threads_anchor_shape',
        'comment_threads_position', 'comment_threads_anchor_identity'
      ] LOOP
        SELECT pg_get_expr(conbin, conrelid) INTO STRICT old_expression
          FROM pg_constraint WHERE conrelid = 'comment_threads'::regclass AND conname = constraint_name;
        EXECUTE format('ALTER TABLE comment_threads DROP CONSTRAINT %I', constraint_name);
        EXECUTE format('ALTER TABLE comment_threads ADD CONSTRAINT %I CHECK (((%s) AND ideation_session_id IS NULL AND ideation_idea_id IS NULL AND source_recovery_identity IS NULL) OR (%s))',
          constraint_name, old_expression, ideation_expression);
      END LOOP;
    END $$;
    """)
  end

  def down do
    raise Ecto.MigrationError,
          "Preserve brainstorming conversations by rolling forward; this migration is irreversible."
  end
end
