defmodule Storyarn.References.VariableTracker do
  @moduledoc """
  Write-path adapter for variable references.

  During the PR2 transition this module delegates to the existing tracking logic
  while callers migrate to the `Storyarn.References` facade.
  """

  alias Storyarn.Flows.VariableReferenceTracker

  def update_flow_node_variable_references(node),
    do: VariableReferenceTracker.update_references(node)

  def delete_flow_node_variable_references(node_id),
    do: VariableReferenceTracker.delete_references(node_id)

  def update_scene_pin_variable_references(pin, opts \\ []),
    do: VariableReferenceTracker.update_scene_pin_references(pin, opts)

  def delete_scene_pin_variable_references(pin_id),
    do: VariableReferenceTracker.delete_map_pin_references(pin_id)

  def update_scene_zone_variable_references(zone, opts \\ []),
    do: VariableReferenceTracker.update_scene_zone_references(zone, opts)

  def delete_scene_zone_variable_references(zone_id),
    do: VariableReferenceTracker.delete_map_zone_references(zone_id)
end
