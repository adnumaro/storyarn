defmodule Storyarn.Repo.Migrations.AddSpatialCommentAnchors do
  use Ecto.Migration

  def up do
    alter table(:comment_threads) do
      add :flow_canvas_id, references(:flows, on_delete: :nilify_all)
      add :position_x, :float
      add :position_y, :float
    end

    create index(:comment_threads, [:flow_canvas_id])
    drop constraint(:comment_threads, :comment_threads_source_type)

    create constraint(:comment_threads, :comment_threads_source_type,
             check: "source_type IN ('flow_node', 'flow_canvas')"
           )

    create constraint(:comment_threads, :comment_threads_anchor_shape,
             check:
               "(source_type = 'flow_node' AND flow_canvas_id IS NULL) OR " <>
                 "(source_type = 'flow_canvas' AND flow_node_id IS NULL AND source_id = container_id)"
           )

    create constraint(:comment_threads, :comment_threads_position,
             check:
               "(source_type = 'flow_node' AND position_x IS NULL AND position_y IS NULL) OR " <>
                 "(position_x IS NOT NULL AND position_y IS NOT NULL AND " <>
                 "position_x BETWEEN -10000000 AND 10000000 AND position_y BETWEEN -10000000 AND 10000000)"
           )
  end

  def down do
    drop constraint(:comment_threads, :comment_threads_position)
    drop constraint(:comment_threads, :comment_threads_anchor_shape)
    drop constraint(:comment_threads, :comment_threads_source_type)

    create constraint(:comment_threads, :comment_threads_source_type,
             check: "source_type = 'flow_node'"
           )

    drop index(:comment_threads, [:flow_canvas_id])

    alter table(:comment_threads) do
      remove :flow_canvas_id
      remove :position_x
      remove :position_y
    end
  end
end
