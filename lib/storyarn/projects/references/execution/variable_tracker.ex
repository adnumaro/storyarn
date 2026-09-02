defmodule Storyarn.Projects.References.VariableTracker do
  @moduledoc """
  Application coordinator for Project-owned variable references.

  It routes projection mutations to the transactional writer and consistency
  checks to the independent validation read side. The public
  `Storyarn.Projects.References` capability remains the only caller-facing
  boundary.
  """

  alias Storyarn.Projects.References.VariableReferenceTracker
  alias Storyarn.Projects.References.VariableReferenceValidation

  @spec rebuild_project_variable_references(integer()) :: :ok | {:error, term()}
  def rebuild_project_variable_references(project_id),
    do: VariableReferenceTracker.rebuild_project_variable_references(project_id)

  def update_flow_node_variable_references(node), do: VariableReferenceTracker.update_references(node)

  def flow_node_variable_references_current_ids(nodes, project_id),
    do: VariableReferenceValidation.flow_node_references_current_ids(nodes, project_id)

  def validate_snapshot_variable_references(project_id, sources),
    do: VariableReferenceValidation.validate_snapshot_variable_references(project_id, sources)

  def validate_entity_snapshot_variable_references(project_id, entity_type, snapshot),
    do: VariableReferenceValidation.validate_entity_snapshot_variable_references(project_id, entity_type, snapshot)

  def update_scene_pin_variable_references(pin, opts \\ []),
    do: VariableReferenceTracker.update_scene_pin_references(pin, opts)

  def update_scene_zone_variable_references(zone, opts \\ []),
    do: VariableReferenceTracker.update_scene_zone_references(zone, opts)

  def update_scene_ambient_flow_variable_references(ambient_flow, opts \\ []),
    do: VariableReferenceTracker.update_scene_ambient_flow_references(ambient_flow, opts)
end
