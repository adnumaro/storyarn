defmodule Storyarn.Flows.References do
  @moduledoc """
  Capability boundary for references authored by Flows.

  It owns entity and variable projections, project-scoped target validation,
  trash/restore integrity, avatar references, and rich-text mentions.
  """

  alias Storyarn.Flows.AssetReferences
  alias Storyarn.Flows.AvatarIntegrity
  alias Storyarn.Flows.EntityReferenceTracker
  alias Storyarn.Flows.EntityTrashRefs
  alias Storyarn.Flows.ProjectReferenceIntegrity
  alias Storyarn.Flows.ReferenceIntegrity
  alias Storyarn.Flows.References.Commands.StaleVariableReferenceRepair
  alias Storyarn.Flows.RichTextMentions
  alias Storyarn.Flows.VariableReferenceTracker

  defdelegate lock_active_asset_references_for_restore(project_id, owner_ids),
    to: AssetReferences,
    as: :lock_active_for_restore

  defdelegate validate_avatar_speaker(avatar_id, avatar_sheet_id, speaker_sheet_id),
    to: AvatarIntegrity

  defdelegate lock_and_normalize_node_avatar(flow_id, node_type, data), to: AvatarIntegrity

  defdelegate lock_and_normalize_node_avatar_for_project(project_id, node_type, data),
    to: AvatarIntegrity

  defdelegate lock_and_normalize_node_avatar_batch_for_project(project_id, data_items),
    to: AvatarIntegrity

  defdelegate lock_avatar_for_delete(avatar_id, opts \\ []), to: AvatarIntegrity
  defdelegate lock_avatar_reference_target(avatar_id), to: AvatarIntegrity
  defdelegate ensure_avatar_deletable(avatar_id), to: AvatarIntegrity, as: :ensure_deletable

  defdelegate update_entity_references(node, opts \\ []),
    to: EntityReferenceTracker,
    as: :update_references

  defdelegate entity_references_current_ids(nodes),
    to: EntityReferenceTracker,
    as: :references_current_ids

  defdelegate delete_entity_references(node_id),
    to: EntityReferenceTracker,
    as: :delete_references

  defdelegate count_entity_backlinks(target_type, target_id),
    to: EntityReferenceTracker,
    as: :count_backlinks

  defdelegate sweep_trash_column(source_schema, source_type, source_column, target_type, target_id),
    to: EntityTrashRefs,
    as: :sweep_column

  defdelegate sweep_trash_jsonb_field(
                source_schema,
                source_type,
                jsonb_column,
                jsonb_key,
                target_type,
                target_id
              ),
              to: EntityTrashRefs,
              as: :sweep_jsonb_field

  defdelegate sweep_project_flow_references(project_id, target_flow_id), to: EntityTrashRefs
  defdelegate restore_trash_references(target_type, target_id), to: EntityTrashRefs, as: :restore

  defdelegate restore_locked_flow_refs(refs, source_nodes, target_flow_id),
    to: EntityTrashRefs

  defdelegate reconcile_project_restore_flow_refs(
                project_id,
                target_flow_ids,
                target_snapshot_node_ids,
                reactivated_target_flow_ids \\ []
              ),
              to: EntityTrashRefs

  defdelegate lock_active_project(project_id, lock_mode \\ :share),
    to: ProjectReferenceIntegrity

  defdelegate lock_active_references(project_id, specs), to: ProjectReferenceIntegrity

  defdelegate ensure_locked_asset_content_type(project_id, asset_id, context, pattern),
    to: ProjectReferenceIntegrity

  defdelegate normalize_optional_id(value), to: ProjectReferenceIntegrity

  defdelegate lock_active_node_for_write(node, project_lock_mode \\ :update),
    to: ReferenceIntegrity

  defdelegate lock_active_flow_for_write(flow, project_lock_mode \\ :update),
    to: ReferenceIntegrity

  defdelegate lock_node_parent(flow_id, parent_id, source_node_id \\ nil),
    to: ReferenceIntegrity

  defdelegate lock_and_normalize_node_references(project_id, source_flow_id, node_type, data),
    to: ReferenceIntegrity

  defdelegate lock_and_normalize_node_reference_batch(project_id, candidates),
    to: ReferenceIntegrity

  defdelegate lock_flow_parent(project_id, source_flow_id, parent_id), to: ReferenceIntegrity
  defdelegate lock_flow_scene(project_id, scene_id), to: ReferenceIntegrity
  defdelegate lock_effective_output_pins(project_id, node), to: ReferenceIntegrity

  defdelegate rich_text_html_candidates(value), to: RichTextMentions, as: :html_candidates
  defdelegate extract_rich_text_mentions(html), to: RichTextMentions, as: :extract_from_html

  defdelegate update_variable_references(node), to: VariableReferenceTracker, as: :update_references

  defdelegate flow_node_references_current_ids(nodes, project_id),
    to: VariableReferenceTracker

  defdelegate validate_flow_node_variable_targets(nodes, project_id),
    to: VariableReferenceTracker

  defdelegate delete_variable_references(node_id),
    to: VariableReferenceTracker,
    as: :delete_references

  defdelegate list_stale_node_ids(flow_id), to: VariableReferenceTracker
  defdelegate list_stale_node_ids_by_flow(flow_ids), to: VariableReferenceTracker
  defdelegate list_referenced_sheet_ids(project_id), to: VariableReferenceTracker

  defdelegate repair_stale_variable_references(scope, project_id),
    to: StaleVariableReferenceRepair,
    as: :repair_project
end
