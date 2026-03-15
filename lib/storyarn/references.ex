defmodule Storyarn.References do
  @moduledoc """
  Public facade for entity and variable reference tracking.
  """

  alias Storyarn.References.{Backlinks, EntityTracker, VariableTracker, VariableUsage}

  defdelegate update_block_references(block), to: EntityTracker
  defdelegate delete_block_references(block_id), to: EntityTracker
  defdelegate update_flow_node_entity_references(node), to: EntityTracker
  defdelegate delete_flow_node_entity_references(node_id), to: EntityTracker
  defdelegate update_screenplay_element_references(element), to: EntityTracker
  defdelegate delete_screenplay_element_references(element_id), to: EntityTracker
  defdelegate update_scene_pin_entity_references(pin), to: EntityTracker
  defdelegate delete_scene_pin_entity_references(pin_id), to: EntityTracker
  defdelegate update_scene_zone_entity_references(zone), to: EntityTracker
  defdelegate delete_scene_zone_entity_references(zone_id), to: EntityTracker
  defdelegate delete_target_references(target_type, target_id), to: EntityTracker

  defdelegate get_backlinks(target_type, target_id), to: Backlinks
  defdelegate get_backlinks_with_sources(target_type, target_id, project_id), to: Backlinks
  defdelegate count_backlinks(target_type, target_id), to: Backlinks

  defdelegate update_flow_node_variable_references(node), to: VariableTracker
  defdelegate delete_flow_node_variable_references(node_id), to: VariableTracker
  defdelegate update_scene_pin_variable_references(pin, opts \\ []), to: VariableTracker
  defdelegate delete_scene_pin_variable_references(pin_id), to: VariableTracker
  defdelegate update_scene_zone_variable_references(zone, opts \\ []), to: VariableTracker
  defdelegate delete_scene_zone_variable_references(zone_id), to: VariableTracker

  defdelegate get_variable_usage(block_id, project_id), to: VariableUsage
  defdelegate count_variable_usage(block_id), to: VariableUsage
  defdelegate referenced_block_ids(block_ids), to: VariableUsage
  defdelegate check_stale_variable_references(block_id, project_id), to: VariableUsage
  defdelegate repair_stale_variable_references(project_id), to: VariableUsage
  defdelegate list_stale_node_ids(flow_id), to: VariableUsage
end
