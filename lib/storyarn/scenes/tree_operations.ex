defmodule Storyarn.Scenes.TreeOperations do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneReferenceIntegrity
  alias Storyarn.Shared.TreeOperations, as: SharedTree

  @doc """
  Reorders scenes within a parent container.

  Takes a project_id, parent_id (nil for root level), and a list of scene IDs
  in the desired order. Updates all positions in a single transaction.

  Returns `{:ok, scenes}` with the reordered scenes or `{:error, reason}`.
  """
  def reorder_scenes(project_id, parent_id, scene_ids) when is_list(scene_ids) do
    Repo.transaction(fn ->
      with {:ok, project} <-
             SceneReferenceIntegrity.lock_active_project(project_id, :update),
           {:ok, normalized_parent_id} <-
             SceneReferenceIntegrity.lock_scene_parent(
               %Scene{project_id: project.id},
               parent_id
             ),
           {:ok, normalized_scene_ids} <- normalize_reorder_ids(scene_ids),
           :ok <-
             lock_requested_scenes(
               project.id,
               normalized_parent_id,
               normalized_scene_ids
             ) do
        SharedTree.batch_set_positions(
          "scenes",
          Enum.with_index(normalized_scene_ids),
          scope: {"project_id", project.id},
          parent_id: normalized_parent_id,
          soft_delete: true
        )

        list_scenes_by_parent(project.id, normalized_parent_id)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Moves a scene to a new parent at a specific position, reordering siblings as needed.

  This function handles both same-parent reordering and cross-parent moves.
  It updates the scene's parent_id, then rebuilds positions for all affected containers.

  Returns `{:ok, scene}` with the moved scene or `{:error, reason}`.
  """
  def move_scene_to_position(%Scene{} = scene, new_parent_id, new_position) do
    SceneReferenceIntegrity.with_active_scene_lock(
      scene.id,
      [project_lock: :update],
      fn locked_scene ->
        case SceneReferenceIntegrity.lock_scene_parent(
               locked_scene,
               new_parent_id
             ) do
          {:ok, normalized_parent_id} ->
            SharedTree.move_to_position(
              Scene,
              locked_scene,
              normalized_parent_id,
              new_position,
              &list_scenes_by_parent/2
            )

          {:error, {:invalid_scene_parent, _scene_id, _parent_id, _reason}} ->
            {:error, :cyclic_parent}

          error ->
            error
        end
      end
    )
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

  defp lock_requested_scenes(_project_id, _parent_id, []), do: :ok

  defp lock_requested_scenes(project_id, parent_id, scene_ids) do
    locked_ids =
      Scene
      |> where(
        [scene],
        scene.project_id == ^project_id and
          scene.id in ^scene_ids and
          is_nil(scene.deleted_at)
      )
      |> SharedTree.add_parent_filter(parent_id)
      |> order_by([scene], asc: scene.id)
      |> lock("FOR UPDATE")
      |> select([scene], scene.id)
      |> Repo.all()

    if locked_ids == Enum.sort(scene_ids) do
      :ok
    else
      {:error, {:invalid_scene_reorder, scene_ids}}
    end
  end

  defp normalize_reorder_ids(scene_ids) do
    with {:ok, normalized_ids} <- normalize_positive_ids(scene_ids),
         true <- length(normalized_ids) == MapSet.size(MapSet.new(normalized_ids)) do
      {:ok, normalized_ids}
    else
      _error -> {:error, {:invalid_scene_reorder, scene_ids}}
    end
  end

  defp normalize_positive_ids(ids) do
    ids
    |> Enum.reduce_while({:ok, []}, fn id, {:ok, normalized} ->
      case ProjectReferenceIntegrity.normalize_optional_id(id) do
        {:ok, normalized_id} when is_integer(normalized_id) ->
          {:cont, {:ok, [normalized_id | normalized]}}

        _error ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      :error -> :error
    end
  end
end
