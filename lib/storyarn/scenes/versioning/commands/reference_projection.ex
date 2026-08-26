defmodule Storyarn.Scenes.Versioning.Commands.ReferenceProjection do
  @moduledoc false

  alias Storyarn.Scenes.References

  def validate_snapshot_variable_references(project_id, sources),
    do: References.validate_snapshot_variable_references(project_id, sources)

  def update_scene_pin_entity_references(pin, opts), do: References.update_pin_entity_references(pin, opts)

  def update_scene_pin_variable_references(pin, opts), do: References.update_pin_variable_references(pin, opts)

  def update_scene_zone_entity_references(zone, opts), do: References.update_zone_entity_references(zone, opts)

  def update_scene_zone_variable_references(zone, opts), do: References.update_zone_variable_references(zone, opts)

  def update_scene_ambient_flow_variable_references(ambient_flow, opts),
    do: References.update_ambient_flow_variable_references(ambient_flow, opts)

  def delete_scene_pin_entity_references(pin_id), do: References.delete_pin_entity_references(pin_id)

  def delete_scene_pin_variable_references(pin_id), do: References.delete_pin_variable_references(pin_id)

  def delete_scene_zone_entity_references(zone_id), do: References.delete_zone_entity_references(zone_id)

  def delete_scene_zone_variable_references(zone_id), do: References.delete_zone_variable_references(zone_id)

  def delete_scene_ambient_flow_variable_references(ambient_flow_id),
    do: References.delete_ambient_flow_variable_references(ambient_flow_id)
end
