defmodule Storyarn.Projects.Trash do
  @moduledoc """
  Public capability boundary for Project-owned trash and retention workflows.

  It coordinates the recoverable lifecycle of Project content while each tool
  keeps its exact restore and purge invariants behind this capability boundary.
  """

  alias Storyarn.Projects.FlowProjectTrash
  alias Storyarn.Projects.ProjectTrash
  alias Storyarn.Projects.SceneProjectTrash
  alias Storyarn.Projects.SheetProjectTrash

  @type deleted_item :: ProjectTrash.deleted_item()
  @type page :: ProjectTrash.page()

  defdelegate paginate_deleted_items(project_id, opts \\ []), to: ProjectTrash
  defdelegate list_deleted_items(project_id, opts \\ []), to: ProjectTrash
  defdelegate list_deleted_items_for_retention(opts \\ []), to: ProjectTrash
  defdelegate deleted_items_retention_cutoff(), to: ProjectTrash
  defdelegate delete_retention_candidate(item, delete_fun), to: ProjectTrash
  defdelegate purge_asset_trash_candidate(item, actor_id), to: ProjectTrash

  defdelegate restore_trashed_flow(project_id, flow_id), to: FlowProjectTrash, as: :restore
  defdelegate permanently_delete_trashed_flow(flow), to: FlowProjectTrash, as: :hard_delete

  defdelegate permanently_delete_trashed_flow(project_id, flow_id),
    to: FlowProjectTrash,
    as: :hard_delete

  defdelegate get_trashed_sheet(project_id, sheet_id), to: SheetProjectTrash, as: :get_trashed
  defdelegate restore_trashed_sheet(sheet), to: SheetProjectTrash, as: :restore
  defdelegate permanently_delete_trashed_sheet(sheet), to: SheetProjectTrash, as: :hard_delete

  defdelegate restore_trashed_scene(scene), to: SceneProjectTrash, as: :restore
  defdelegate permanently_delete_trashed_scene(scene), to: SceneProjectTrash, as: :hard_delete

  defdelegate permanently_delete_trashed_scene(project_id, scene_id),
    to: SceneProjectTrash,
    as: :hard_delete
end
