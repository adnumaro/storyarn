defmodule Storyarn.Projects.Overview do
  @moduledoc """
  Public capability boundary for Project-wide read models and health analysis.

  Overview owns the consumer-local projections that aggregate authored Sheets,
  Flows, and Scenes for dashboards, export preparation, and project lifecycle
  workflows. It does not write the tool aggregates it reads.
  """

  alias Storyarn.Projects.Dashboard
  alias Storyarn.Projects.FlowReadModel
  alias Storyarn.Projects.SceneHealthReadModel
  alias Storyarn.Projects.SceneReadModel
  alias Storyarn.Projects.SheetHealthReadModel
  alias Storyarn.Projects.SheetReadModel

  defdelegate project_stats(project_id), to: Dashboard
  defdelegate tools(), to: Dashboard
  defdelegate tool_health_summary(findings_by_tool), to: Dashboard
  defdelegate recent_activity(project_id, limit \\ 10), to: Dashboard

  defdelegate list_flows(project_id), to: FlowReadModel
  defdelegate get_flow_brief(project_id, flow_id), to: FlowReadModel
  defdelegate get_flow_including_deleted(project_id, flow_id), to: FlowReadModel
  defdelegate list_flows_for_export(project_id, opts \\ []), to: FlowReadModel
  defdelegate count_flows(project_id), to: FlowReadModel
  defdelegate count_flow_nodes(project_id), to: FlowReadModel, as: :count_nodes_for_project
  defdelegate flow_word_counts(project_id), to: FlowReadModel
  defdelegate list_flow_speaker_sheet_ids(project_id), to: FlowReadModel, as: :list_speaker_sheet_ids
  defdelegate list_flow_shortcuts(project_id), to: FlowReadModel, as: :list_shortcuts

  defdelegate list_flow_export_health_findings(project_id, flows, context \\ %{}),
    to: FlowReadModel,
    as: :list_export_health_findings

  defdelegate list_flow_dashboard_health_findings(project_id),
    to: FlowReadModel,
    as: :list_dashboard_health_findings

  defdelegate list_sheets_for_export(project_id, opts \\ []), to: SheetReadModel, as: :list_for_export
  defdelegate list_sheets_by_ids(project_id, ids), to: SheetReadModel, as: :list_by_ids
  defdelegate count_sheets(project_id), to: SheetReadModel, as: :count_active
  defdelegate count_sheet_variables(project_id), to: SheetReadModel, as: :count_variables
  defdelegate sheet_word_counts(project_id), to: SheetReadModel

  defdelegate list_sheet_dashboard_health_findings(project_id, referenced_ids \\ nil),
    to: SheetHealthReadModel,
    as: :list_dashboard_health_findings

  defdelegate sheet_referenced_block_ids(project_id),
    to: SheetHealthReadModel,
    as: :referenced_block_ids_for_project

  defdelegate list_scenes(project_id), to: SceneReadModel, as: :list_active
  defdelegate list_scene_pin_referenced_sheet_ids(project_id), to: SceneReadModel, as: :list_pin_referenced_sheet_ids
  defdelegate list_scenes_for_export(project_id, opts \\ []), to: SceneReadModel, as: :list_for_export
  defdelegate count_scenes(project_id), to: SceneReadModel, as: :count
  defdelegate get_scene_brief(project_id, scene_id), to: SceneReadModel, as: :get_brief
  defdelegate get_scene_including_deleted(project_id, scene_id), to: SceneReadModel, as: :get_including_deleted
  defdelegate detect_scene_shortcut_conflicts(project_id, shortcuts), to: SceneReadModel, as: :detect_shortcut_conflicts
  defdelegate list_scene_shortcuts(project_id), to: SceneReadModel, as: :list_shortcuts

  defdelegate list_scene_dashboard_health_findings(project_id),
    to: SceneHealthReadModel,
    as: :list_dashboard_findings
end
