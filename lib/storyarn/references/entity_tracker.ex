defmodule Storyarn.References.EntityTracker do
  @moduledoc """
  Write-path adapter for entity references.

  During the PR2 transition this module delegates to the existing tracking logic
  while callers migrate to the `Storyarn.References` facade.
  """

  alias Storyarn.Sheets.ReferenceTracker

  defdelegate update_block_references(block), to: ReferenceTracker
  defdelegate delete_block_references(block_id), to: ReferenceTracker
  defdelegate update_screenplay_element_references(element), to: ReferenceTracker
  defdelegate delete_screenplay_element_references(element_id), to: ReferenceTracker
  defdelegate delete_target_references(target_type, target_id), to: ReferenceTracker

  def update_flow_node_entity_references(node), do: ReferenceTracker.update_flow_node_references(node)
  def delete_flow_node_entity_references(node_id), do: ReferenceTracker.delete_flow_node_references(node_id)

  def update_scene_pin_entity_references(pin), do: ReferenceTracker.update_scene_pin_references(pin)
  def delete_scene_pin_entity_references(pin_id), do: ReferenceTracker.delete_map_pin_references(pin_id)

  def update_scene_zone_entity_references(zone), do: ReferenceTracker.update_scene_zone_references(zone)
  def delete_scene_zone_entity_references(zone_id), do: ReferenceTracker.delete_map_zone_references(zone_id)
end
