defmodule Storyarn.Sheets.References do
  @moduledoc """
  Public capability boundary for references owned or consumed by Sheets.

  Commands protect project-scoped writes and maintain Sheet projections;
  queries resolve backlinks, foreign appearances, and variable usage without
  exposing their consumer-local SQL records to sibling capabilities.
  """

  alias Storyarn.Sheets.References.Commands.AvatarIntegrity
  alias Storyarn.Sheets.References.Commands.EntityProjection
  alias Storyarn.Sheets.References.Commands.ProjectIntegrity
  alias Storyarn.Sheets.References.Commands.VariableProjection
  alias Storyarn.Sheets.References.Queries.AssetUsage
  alias Storyarn.Sheets.References.Queries.Backlinks
  alias Storyarn.Sheets.References.Queries.Repair
  alias Storyarn.Sheets.References.Queries.Scenes
  alias Storyarn.Sheets.References.Queries.Targets
  alias Storyarn.Sheets.References.Queries.VariableUsage

  @typedoc """
  Active Sheet or Flow target returned by reference validation.

  Flow targets are described structurally so callers can use the reference
  vocabulary without depending on the capability's private SQL projection.
  """
  @type reference_target ::
          Storyarn.Sheets.Sheet.t()
          | %{
              required(:__struct__) => module(),
              required(:id) => integer(),
              required(:project_id) => integer(),
              required(:name) => String.t() | nil,
              required(:shortcut) => String.t() | nil,
              optional(atom()) => term()
            }

  defdelegate lock_active_project(project_id, lock_mode \\ :share), to: ProjectIntegrity
  defdelegate lock_active_references(project_id, specs), to: ProjectIntegrity

  defdelegate ensure_locked_asset_content_type(project_id, asset_id, context, pattern),
    to: ProjectIntegrity

  defdelegate normalize_optional_id(value), to: ProjectIntegrity

  defdelegate validate_avatar_speaker(avatar_id, avatar_sheet_id, speaker_sheet_id),
    to: AvatarIntegrity

  defdelegate ensure_avatar_deletable(avatar_id), to: AvatarIntegrity, as: :ensure_deletable

  defdelegate update_block_references(block, opts \\ []), to: EntityProjection
  defdelegate lock_and_normalize_block_value(project_id, type, value), to: EntityProjection
  defdelegate extract_block_value_references(type, value), to: EntityProjection
  defdelegate delete_block_references(block_id), to: EntityProjection
  defdelegate delete_block_references_for_sources(block_ids), to: EntityProjection
  defdelegate delete_target_references(target_type, target_id), to: EntityProjection

  defdelegate flow_node_references_current?(node), to: Backlinks
  defdelegate flow_node_references_current_ids(nodes), to: Backlinks
  defdelegate get_backlinks(target_type, target_id), to: Backlinks
  defdelegate list_stale_block_reference_source_ids(project_id, block_ids), to: Backlinks
  defdelegate get_reference_targets(references, project_id), to: Backlinks
  defdelegate get_backlinks_with_sources(target_type, target_id, project_id), to: Backlinks
  defdelegate count_backlinks(target_type, target_id), to: Backlinks

  defdelegate validate_reference_target(target_type, target_id, project_id), to: Targets, as: :validate

  defdelegate search_referenceable(project_id, query, allowed_types \\ ["sheet", "flow"]),
    to: Targets,
    as: :search

  defdelegate get_reference_target(target_type, target_id, project_id), to: Targets, as: :get

  defdelegate list_variable_refs_with_block_info_for_repair(project_id),
    to: Repair,
    as: :list_with_block_info

  defdelegate list_stale_regular_node_ids(flow_id), to: Repair
  defdelegate list_stale_table_node_ids(flow_id), to: Repair

  defdelegate resolve_block_id_by_variable(project_id, sheet_shortcut, variable_name),
    to: Repair,
    as: :resolve_block_id

  defdelegate resolve_table_block_id_by_variable(
                project_id,
                sheet_shortcut,
                table_name,
                row_slug,
                column_slug
              ),
              to: Repair,
              as: :resolve_table_block_id

  defdelegate list_variable_referenced_sheet_ids(project_id),
    to: Repair,
    as: :list_referenced_sheet_ids

  defdelegate list_sheets_using_asset_as_avatar(project_id, asset_id),
    to: AssetUsage,
    as: :list_avatar_sheets

  defdelegate list_sheets_using_asset_as_banner(project_id, asset_id),
    to: AssetUsage,
    as: :list_banner_sheets

  defdelegate rebuild_project_variable_references(project_id),
    to: VariableProjection,
    as: :rebuild_project

  defdelegate count_variable_usage(block_id), to: VariableUsage

  defdelegate count_stale_variable_references(block_ids, project_id),
    to: VariableUsage,
    as: :count_stale_references

  defdelegate check_stale_variable_references(block_id, project_id),
    to: VariableUsage,
    as: :check_stale_references

  defdelegate check_stale_flow_node_variable_references(block_id, project_id),
    to: VariableUsage,
    as: :check_stale_flow_node_references

  defdelegate scene_project_id(scene_id), to: Scenes, as: :project_id
  defdelegate scene_pin_backlinks(target_type, target_id, project_id), to: Scenes, as: :pin_backlinks
  defdelegate scene_zone_backlinks(target_type, target_id, project_id), to: Scenes, as: :zone_backlinks
  defdelegate list_scene_appearances(sheet_id), to: Scenes, as: :list_sheet_appearances
end
