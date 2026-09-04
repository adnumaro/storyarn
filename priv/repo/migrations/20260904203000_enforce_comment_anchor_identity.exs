defmodule Storyarn.Repo.Migrations.EnforceCommentAnchorIdentity do
  use Ecto.Migration

  def change do
    create constraint(:comment_threads, :comment_threads_anchor_identity,
             check:
               "(source_type = 'flow_node' AND (flow_node_id IS NULL OR flow_node_id = source_id)) OR " <>
                 "(source_type = 'flow_canvas' AND (flow_canvas_id IS NULL OR flow_canvas_id = source_id))"
           )
  end
end
