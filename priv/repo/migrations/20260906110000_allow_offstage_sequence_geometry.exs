defmodule Storyarn.Repo.Migrations.AllowOffstageSequenceGeometry do
  use Ecto.Migration

  def up do
    drop constraint(
           :flow_node_sequence_visual_layers,
           :flow_node_sequence_visual_layers_geometry_check
         )

    create constraint(
             :flow_node_sequence_visual_layers,
             :flow_node_sequence_visual_layers_geometry_check,
             check: """
             x >= -10 AND x <= 10 AND y >= -10 AND y <= 10
             AND width > 0 AND width <= 20 AND height > 0 AND height <= 20
             AND anchor_x >= 0 AND anchor_x <= 1 AND anchor_y >= 0 AND anchor_y <= 1
             AND opacity >= 0 AND opacity <= 1
             """
           )
  end

  def down do
    drop constraint(
           :flow_node_sequence_visual_layers,
           :flow_node_sequence_visual_layers_geometry_check
         )

    # Refuse rollback if offstage compositions exist instead of silently cropping them.
    create constraint(
             :flow_node_sequence_visual_layers,
             :flow_node_sequence_visual_layers_geometry_check,
             check: """
             x >= 0 AND x <= 1 AND y >= 0 AND y <= 1
             AND width > 0 AND width <= 1 AND height > 0 AND height <= 1
             AND anchor_x >= 0 AND anchor_x <= 1 AND anchor_y >= 0 AND anchor_y <= 1
             AND opacity >= 0 AND opacity <= 1
             """
           )
  end
end
