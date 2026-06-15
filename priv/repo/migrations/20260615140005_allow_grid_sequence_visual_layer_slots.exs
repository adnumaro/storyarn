defmodule Storyarn.Repo.Migrations.AllowGridSequenceVisualLayerSlots do
  use Ecto.Migration

  @old_slots ["full", "left", "center", "right", "custom"]

  @new_slots @old_slots ++
               [
                 "top-left",
                 "top-center",
                 "top-right",
                 "middle-left",
                 "middle-center",
                 "middle-right",
                 "bottom-left",
                 "bottom-center",
                 "bottom-right"
               ]

  def up do
    replace_slot_constraint(@new_slots)
  end

  def down do
    execute """
    UPDATE flow_node_sequence_visual_layers
    SET slot = CASE
      WHEN slot = 'bottom-left' THEN 'left'
      WHEN slot = 'bottom-center' THEN 'center'
      WHEN slot = 'bottom-right' THEN 'right'
      WHEN slot IN (
        'top-left',
        'top-center',
        'top-right',
        'middle-left',
        'middle-center',
        'middle-right'
      ) THEN 'custom'
      ELSE slot
    END
    """

    replace_slot_constraint(@old_slots)
  end

  defp replace_slot_constraint(slots) do
    execute "ALTER TABLE flow_node_sequence_visual_layers DROP CONSTRAINT IF EXISTS flow_node_sequence_visual_layers_slot_check"

    execute """
    ALTER TABLE flow_node_sequence_visual_layers
      ADD CONSTRAINT flow_node_sequence_visual_layers_slot_check
      CHECK (slot IN (#{sql_list(slots)}))
    """
  end

  defp sql_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
