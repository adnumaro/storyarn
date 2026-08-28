defmodule Storyarn.Projects.References do
  @moduledoc """
  Public facade for entity and variable reference tracking.
  """

  alias Storyarn.Projects.References.EntityTracker
  alias Storyarn.Projects.References.VariableTracker
  alias Storyarn.Projects.References.VariableUsage

  defdelegate update_block_references(block, opts \\ []), to: EntityTracker

  @spec lock_and_normalize_block_value(integer(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  defdelegate lock_and_normalize_block_value(project_id, block_type, value),
    to: Storyarn.Projects.References.EntityReferenceProjection

  @spec update_flow_node_entity_references(map(), keyword()) :: :ok | {:error, term()}
  defdelegate update_flow_node_entity_references(node, opts \\ []), to: EntityTracker
  defdelegate update_scene_pin_entity_references(pin, opts \\ []), to: EntityTracker
  defdelegate delete_scene_pin_entity_references(pin_id), to: EntityTracker
  defdelegate update_scene_zone_entity_references(zone, opts \\ []), to: EntityTracker
  defdelegate delete_scene_zone_entity_references(zone_id), to: EntityTracker
  defdelegate delete_target_references(target_type, target_id), to: EntityTracker

  @spec rebuild_project_entity_references(integer()) :: :ok | {:error, term()}
  defdelegate rebuild_project_entity_references(project_id), to: EntityTracker

  @spec rebuild_project_variable_references(integer()) :: :ok | {:error, term()}
  defdelegate rebuild_project_variable_references(project_id), to: VariableTracker

  defdelegate update_flow_node_variable_references(node), to: VariableTracker

  @spec flow_node_variable_references_current_ids([map()], integer()) ::
          MapSet.t(integer())
  defdelegate flow_node_variable_references_current_ids(nodes, project_id),
    to: VariableTracker

  @spec validate_snapshot_variable_references(integer(), [map()]) ::
          :ok | {:error, term()}
  defdelegate validate_snapshot_variable_references(project_id, sources),
    to: VariableTracker

  @spec validate_entity_snapshot_variable_references(integer(), String.t(), map()) ::
          :ok | {:error, term()}
  defdelegate validate_entity_snapshot_variable_references(project_id, entity_type, snapshot),
    to: VariableTracker

  defdelegate delete_flow_node_variable_references(node_id), to: VariableTracker
  defdelegate update_scene_pin_variable_references(pin, opts \\ []), to: VariableTracker
  defdelegate delete_scene_pin_variable_references(pin_id), to: VariableTracker
  defdelegate update_scene_zone_variable_references(zone, opts \\ []), to: VariableTracker
  defdelegate delete_scene_zone_variable_references(zone_id), to: VariableTracker

  defdelegate update_scene_ambient_flow_variable_references(ambient_flow, opts \\ []),
    to: VariableTracker

  defdelegate delete_scene_ambient_flow_variable_references(ambient_flow_id),
    to: VariableTracker

  defdelegate count_variable_usage(block_id), to: VariableUsage
  defdelegate referenced_block_ids(block_ids), to: VariableUsage
  defdelegate list_variable_usages(project_id, definition, opts \\ []), to: VariableUsage

  defdelegate count_stale_variable_references(block_ids, project_id),
    to: VariableUsage,
    as: :count_stale_references

  defdelegate check_stale_variable_references(block_id, project_id), to: VariableUsage
  defdelegate repair_stale_variable_references(project_id), to: VariableUsage
  # The batched export sweep reads Project-owned records; the per-tool editors
  # keep their own copies of this rule.
  defdelegate list_stale_node_variable_refs_by_flow(flow_ids),
    to: Storyarn.Projects.FlowVariableReferenceReadModel

  defdelegate list_stale_node_ids(flow_id), to: VariableUsage
end
