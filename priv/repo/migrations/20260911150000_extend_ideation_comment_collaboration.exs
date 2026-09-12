defmodule Storyarn.Repo.Migrations.ExtendIdeationCommentCollaboration do
  use Ecto.Migration

  def up do
    alter table(:comment_threads) do
      add :ideation_group_id, references(:ideation_groups, on_delete: :nilify_all)
    end

    create index(:comment_threads, [:ideation_group_id])

    create index(:comment_threads, [:project_id, :last_activity_at, :id],
             name: :ideation_comment_activity,
             where: "source_type IN ('ideation_session', 'ideation_idea', 'ideation_group')"
           )

    create index(:comment_mentions, [:user_id, :message_id])

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
        EXECUTE format('ALTER TABLE comment_threads ADD CONSTRAINT %I CHECK (((%s) AND ideation_group_id IS NULL) OR (
          source_type = ''ideation_group'' AND flow_node_id IS NULL AND flow_canvas_id IS NULL AND
          scene_canvas_id IS NULL AND sheet_canvas_id IS NULL AND ideation_idea_id IS NULL AND
          position_x IS NULL AND position_y IS NULL AND source_recovery_identity IS NOT NULL AND
          (ideation_session_id IS NULL OR ideation_session_id = container_id) AND
          (ideation_group_id IS NULL OR ideation_group_id = source_id)))', constraint_name, old_expression);
      END LOOP;
    END $$;
    """)

    create table(:comment_participations, primary_key: false) do
      add :thread_id, references(:comment_threads, on_delete: :delete_all), primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), primary_key: true
      add :following, :boolean, null: false, default: false
      add :last_read_message_id, :bigint, null: false, default: 0
    end

    create index(:comment_participations, [:user_id, :thread_id])

    create constraint(:comment_participations, :comment_read_watermark_nonnegative,
             check: "last_read_message_id >= 0"
           )
  end

  def down do
    raise Ecto.MigrationError, "Preserve discussions and per-user state by rolling forward."
  end
end
