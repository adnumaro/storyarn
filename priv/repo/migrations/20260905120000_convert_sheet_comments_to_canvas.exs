defmodule Storyarn.Repo.Migrations.ConvertSheetCommentsToCanvas do
  @moduledoc false
  use Ecto.Migration

  def up do
    alter table(:comment_threads) do
      add :sheet_canvas_id, references(:sheets, on_delete: :nilify_all)
    end

    create index(:comment_threads, [:sheet_canvas_id])

    drop constraint(:comment_threads, :comment_threads_source_type)
    drop constraint(:comment_threads, :comment_threads_anchor_shape)
    drop constraint(:comment_threads, :comment_threads_position)
    drop constraint(:comment_threads, :comment_threads_anchor_identity)

    execute("""
    UPDATE comment_threads AS thread
    SET source_type = 'sheet_canvas',
        source_id = thread.container_id,
        sheet_canvas_id = sheet.id,
        source_inserted_at = sheet.inserted_at,
        source_label = COALESCE(NULLIF(BTRIM(sheet.name), ''), CONCAT('Sheet #', sheet.id))
    FROM sheets AS sheet
    WHERE thread.source_type = 'sheet_block'
      AND sheet.id = thread.container_id
      AND sheet.project_id = thread.project_id
    """)

    execute("""
    UPDATE comment_threads
    SET source_type = 'sheet_canvas',
        source_id = container_id,
        source_label = CONCAT('Sheet #', container_id)
    WHERE source_type = 'sheet_block'
    """)

    drop index(:comment_threads, [:sheet_block_id])

    alter table(:comment_threads) do
      remove :sheet_block_id
    end

    create constraint(:comment_threads, :comment_threads_source_type,
             check: "source_type IN ('flow_node', 'flow_canvas', 'scene_canvas', 'sheet_canvas')"
           )

    create constraint(:comment_threads, :comment_threads_anchor_shape,
             check:
               "(source_type = 'flow_node' AND flow_canvas_id IS NULL AND scene_canvas_id IS NULL AND sheet_canvas_id IS NULL) OR " <>
                 "(source_type = 'flow_canvas' AND flow_node_id IS NULL AND scene_canvas_id IS NULL AND sheet_canvas_id IS NULL AND source_id = container_id) OR " <>
                 "(source_type = 'scene_canvas' AND flow_node_id IS NULL AND flow_canvas_id IS NULL AND sheet_canvas_id IS NULL AND source_id = container_id) OR " <>
                 "(source_type = 'sheet_canvas' AND flow_node_id IS NULL AND flow_canvas_id IS NULL AND scene_canvas_id IS NULL AND source_id = container_id)"
           )

    create constraint(:comment_threads, :comment_threads_position,
             check:
               "(source_type = 'flow_node' AND position_x IS NULL AND position_y IS NULL) OR " <>
                 "(source_type IN ('flow_node', 'flow_canvas') AND " <>
                 "position_x IS NOT NULL AND position_y IS NOT NULL AND " <>
                 "position_x BETWEEN -10000000 AND 10000000 AND position_y BETWEEN -10000000 AND 10000000) OR " <>
                 "(source_type = 'scene_canvas' AND " <>
                 "position_x IS NOT NULL AND position_y IS NOT NULL AND " <>
                 "position_x BETWEEN 0 AND 100 AND position_y BETWEEN 0 AND 100) OR " <>
                 "(source_type = 'sheet_canvas' AND " <>
                 "position_x IS NOT NULL AND position_y IS NOT NULL AND " <>
                 "position_x BETWEEN 0 AND 100 AND position_y BETWEEN 0 AND 10000000)"
           )

    create constraint(:comment_threads, :comment_threads_anchor_identity,
             check:
               "(source_type = 'flow_node' AND (flow_node_id IS NULL OR flow_node_id = source_id)) OR " <>
                 "(source_type = 'flow_canvas' AND (flow_canvas_id IS NULL OR flow_canvas_id = source_id)) OR " <>
                 "(source_type = 'scene_canvas' AND (scene_canvas_id IS NULL OR scene_canvas_id = source_id)) OR " <>
                 "(source_type = 'sheet_canvas' AND (sheet_canvas_id IS NULL OR sheet_canvas_id = source_id))"
           )
  end

  def down do
    raise Ecto.MigrationError,
          "ConvertSheetCommentsToCanvas is irreversible: rollback would restore block-relative Sheet anchors from canvas coordinates. " <>
            "Preserve comment threads and their history by rolling forward with a compatible migration."
  end
end
