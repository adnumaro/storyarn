defmodule Storyarn.Scenes.TreeOperations do
  @moduledoc false

  alias Storyarn.Scenes.Scene
  alias Storyarn.Shared.TreeOperations, as: SharedTree

  @doc """
  Reorders scenes within a parent container.

  Takes a project_id, parent_id (nil for root level), and a list of scene IDs
  in the desired order. Updates all positions in a single transaction.

  Returns `{:ok, scenes}` with the reordered scenes or `{:error, reason}`.
  """
  def reorder_scenes(project_id, parent_id, scene_ids) when is_list(scene_ids) do
    SharedTree.reorder(Scene, project_id, parent_id, scene_ids, &list_scenes_by_parent/2)
  end

  @doc """
  Moves a scene to a new parent at a specific position, reordering siblings as needed.

  This function handles both same-parent reordering and cross-parent moves.
  It updates the scene's parent_id, then rebuilds positions for all affected containers.

  Returns `{:ok, scene}` with the moved scene or `{:error, reason}`.
  """
  def move_scene_to_position(%Scene{} = scene, new_parent_id, new_position) do
    if new_parent_id && SharedTree.descendant?(Scene, new_parent_id, scene.id) do
      {:error, :cyclic_parent}
    else
      SharedTree.move_to_position(
        Scene,
        scene,
        new_parent_id,
        new_position,
        &list_scenes_by_parent/2
      )
    end
  end

  @doc """
  Gets the next available position for a new scene in the given container.
  """
  def next_position(project_id, parent_id) do
    SharedTree.next_position(Scene, project_id, parent_id)
  end

  @doc """
  Lists scenes for a given parent (or root level).
  Excludes soft-deleted scenes and orders by position then name.
  """
  def list_scenes_by_parent(project_id, parent_id) do
    SharedTree.list_by_parent(Scene, project_id, parent_id)
  end
end
