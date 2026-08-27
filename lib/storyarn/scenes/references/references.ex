defmodule Storyarn.Scenes.References do
  @moduledoc """
  Scene reference-integrity boundary.

  It validates project-scoped targets and maintains the entity and variable
  reference projections produced by pins, zones and ambient flows.
  """

  alias Storyarn.Scenes.References.Commands.EntityProjection
  alias Storyarn.Scenes.References.Commands.ProjectIntegrity
  alias Storyarn.Scenes.References.Commands.VariableProjection

  defdelegate lock_active_project(project_id, lock_mode \\ :share), to: ProjectIntegrity
  defdelegate lock_active_references(project_id, specs), to: ProjectIntegrity
  defdelegate lock_active_reference_ids(project_id, specs), to: ProjectIntegrity

  defdelegate ensure_locked_asset_content_type(project_id, asset_id, context, pattern),
    to: ProjectIntegrity

  defdelegate normalize_optional_id(value), to: ProjectIntegrity

  defdelegate update_pin_entity_references(pin, opts \\ []),
    to: EntityProjection,
    as: :update_pin_references

  defdelegate delete_pin_entity_references(pin_id),
    to: EntityProjection,
    as: :delete_pin_references

  defdelegate update_zone_entity_references(zone, opts \\ []),
    to: EntityProjection,
    as: :update_zone_references

  defdelegate delete_zone_entity_references(zone_id),
    to: EntityProjection,
    as: :delete_zone_references

  defdelegate update_pin_variable_references(pin, opts \\ []),
    to: VariableProjection,
    as: :update_pin_references

  defdelegate delete_pin_variable_references(pin_id),
    to: VariableProjection,
    as: :delete_pin_references

  defdelegate update_zone_variable_references(zone, opts \\ []),
    to: VariableProjection,
    as: :update_zone_references

  defdelegate delete_zone_variable_references(zone_id),
    to: VariableProjection,
    as: :delete_zone_references

  defdelegate update_ambient_flow_variable_references(ambient_flow, opts \\ []),
    to: VariableProjection,
    as: :update_ambient_flow_references

  defdelegate delete_ambient_flow_variable_references(ambient_flow_id),
    to: VariableProjection,
    as: :delete_ambient_flow_references

  defdelegate validate_snapshot_variable_references(project_id, sources),
    to: VariableProjection
end
