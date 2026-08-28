defmodule Storyarn.Projects.References.VariableTracker do
  @moduledoc """
  Write-path adapter for variable references.

  During the PR2 transition this module delegates to the existing tracking logic
  while callers migrate to the `Storyarn.Projects.References` facade.
  """

  alias Storyarn.Projects.References.VariableReferenceTracker

  @spec rebuild_project_variable_references(integer()) :: :ok | {:error, term()}
  def rebuild_project_variable_references(project_id),
    do: VariableReferenceTracker.rebuild_project_variable_references(project_id)

  def update_flow_node_variable_references(node), do: VariableReferenceTracker.update_references(node)

  def flow_node_variable_references_current_ids(nodes, project_id),
    do: VariableReferenceTracker.flow_node_references_current_ids(nodes, project_id)

  def validate_snapshot_variable_references(project_id, sources),
    do: VariableReferenceTracker.validate_snapshot_variable_references(project_id, sources)

  def validate_entity_snapshot_variable_references(project_id, entity_type, snapshot),
    do: VariableReferenceTracker.validate_entity_snapshot_variable_references(project_id, entity_type, snapshot)

  def delete_flow_node_variable_references(node_id), do: VariableReferenceTracker.delete_references(node_id)

  def update_scene_pin_variable_references(pin, opts \\ []),
    do: VariableReferenceTracker.update_scene_pin_references(pin, opts)

  def delete_scene_pin_variable_references(pin_id), do: VariableReferenceTracker.delete_map_pin_references(pin_id)

  def update_scene_zone_variable_references(zone, opts \\ []),
    do: VariableReferenceTracker.update_scene_zone_references(zone, opts)

  def delete_scene_zone_variable_references(zone_id), do: VariableReferenceTracker.delete_map_zone_references(zone_id)

  def update_scene_ambient_flow_variable_references(ambient_flow, opts \\ []),
    do: VariableReferenceTracker.update_scene_ambient_flow_references(ambient_flow, opts)

  def delete_scene_ambient_flow_variable_references(ambient_flow_id),
    do: VariableReferenceTracker.delete_scene_ambient_flow_references(ambient_flow_id)
end
