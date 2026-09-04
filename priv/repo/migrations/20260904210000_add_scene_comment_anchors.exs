defmodule Storyarn.Repo.Migrations.AddSceneCommentAnchors do
  use Ecto.Migration

  def up do
    alter table(:comment_threads) do
      add :scene_canvas_id, references(:scenes, on_delete: :nilify_all)
    end

    create index(:comment_threads, [:scene_canvas_id])

    drop constraint(:comment_threads, :comment_threads_source_type)
    drop constraint(:comment_threads, :comment_threads_anchor_shape)
    drop constraint(:comment_threads, :comment_threads_position)
    drop constraint(:comment_threads, :comment_threads_anchor_identity)

    create constraint(:comment_threads, :comment_threads_source_type,
             check: "source_type IN ('flow_node', 'flow_canvas', 'scene_canvas')"
           )

    create constraint(:comment_threads, :comment_threads_anchor_shape,
             check:
               "(source_type = 'flow_node' AND flow_canvas_id IS NULL AND scene_canvas_id IS NULL) OR " <>
                 "(source_type = 'flow_canvas' AND flow_node_id IS NULL AND scene_canvas_id IS NULL AND source_id = container_id) OR " <>
                 "(source_type = 'scene_canvas' AND flow_node_id IS NULL AND flow_canvas_id IS NULL AND source_id = container_id)"
           )

    create constraint(:comment_threads, :comment_threads_position,
             check:
               "(source_type = 'flow_node' AND position_x IS NULL AND position_y IS NULL) OR " <>
                 "(source_type IN ('flow_node', 'flow_canvas') AND " <>
                 "position_x IS NOT NULL AND position_y IS NOT NULL AND " <>
                 "position_x BETWEEN -10000000 AND 10000000 AND position_y BETWEEN -10000000 AND 10000000) OR " <>
                 "(source_type = 'scene_canvas' AND " <>
                 "position_x IS NOT NULL AND position_y IS NOT NULL AND " <>
                 "position_x BETWEEN 0 AND 100 AND position_y BETWEEN 0 AND 100)"
           )

    create constraint(:comment_threads, :comment_threads_anchor_identity,
             check:
               "(source_type = 'flow_node' AND (flow_node_id IS NULL OR flow_node_id = source_id)) OR " <>
                 "(source_type = 'flow_canvas' AND (flow_canvas_id IS NULL OR flow_canvas_id = source_id)) OR " <>
                 "(source_type = 'scene_canvas' AND (scene_canvas_id IS NULL OR scene_canvas_id = source_id))"
           )
  end

  def down do
    raise Ecto.MigrationError,
          "AddSceneCommentAnchors is irreversible: rollback would remove Scene canvas anchors and spatial metadata. " <>
            "Preserve comment threads and their history by rolling forward with a compatible migration."
  end
end
