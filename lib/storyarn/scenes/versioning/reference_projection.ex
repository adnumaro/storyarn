defmodule Storyarn.Scenes.Versioning.ReferenceProjection do
  @moduledoc false

  alias Storyarn.Scenes.EntityReferenceTracker
  alias Storyarn.Scenes.VariableReferenceTracker

  def validate_snapshot_variable_references(project_id, sources),
    do: VariableReferenceTracker.validate_snapshot_variable_references(project_id, sources)

  def update_scene_pin_entity_references(pin, opts), do: EntityReferenceTracker.update_pin_references(pin, opts)

  def update_scene_pin_variable_references(pin, opts), do: VariableReferenceTracker.update_pin_references(pin, opts)

  def update_scene_zone_entity_references(zone, opts), do: EntityReferenceTracker.update_zone_references(zone, opts)

  def update_scene_zone_variable_references(zone, opts), do: VariableReferenceTracker.update_zone_references(zone, opts)

  def update_scene_ambient_flow_variable_references(ambient_flow, opts),
    do: VariableReferenceTracker.update_ambient_flow_references(ambient_flow, opts)

  def delete_scene_pin_entity_references(pin_id), do: EntityReferenceTracker.delete_pin_references(pin_id)

  def delete_scene_pin_variable_references(pin_id), do: VariableReferenceTracker.delete_pin_references(pin_id)

  def delete_scene_zone_entity_references(zone_id), do: EntityReferenceTracker.delete_zone_references(zone_id)

  def delete_scene_zone_variable_references(zone_id), do: VariableReferenceTracker.delete_zone_references(zone_id)

  def delete_scene_ambient_flow_variable_references(ambient_flow_id),
    do: VariableReferenceTracker.delete_ambient_flow_references(ambient_flow_id)
end
