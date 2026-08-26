defmodule Storyarn.Scenes.Editor.Commands.Tree do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.Editor.Adapters.Postgres.Positions
  alias Storyarn.Scenes.Editor.Commands.ReferenceIntegrity
  alias Storyarn.Scenes.References
  alias Storyarn.Scenes.Scene

  @doc """
  Reorders scenes within a parent container.

  Takes a project_id, parent_id (nil for root level), and a list of scene IDs
  in the desired order. Updates all positions in a single transaction.

  Returns `{:ok, scenes}` with the reordered scenes or `{:error, reason}`.
  """
  def reorder_scenes(project_id, parent_id, scene_ids) when is_list(scene_ids) do
    Repo.transaction(fn ->
      with {:ok, project} <-
             ReferenceIntegrity.lock_active_project(project_id, :update),
           {:ok, normalized_parent_id} <-
             ReferenceIntegrity.lock_scene_parent(
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
        Positions.set_scene_positions(
          Enum.with_index(normalized_scene_ids),
          project.id,
          normalized_parent_id
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
    ReferenceIntegrity.with_active_scene_lock(
      scene.id,
      [project_lock: :update],
      fn locked_scene ->
        case ReferenceIntegrity.lock_scene_parent(
               locked_scene,
               new_parent_id
             ) do
          {:ok, normalized_parent_id} ->
            move_locked_scene(locked_scene, normalized_parent_id, new_position)

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
    from(scene in Scene,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      select: max(scene.position)
    )
    |> add_parent_filter(parent_id)
    |> Repo.one()
    |> case do
      nil -> 0
      position -> position + 1
    end
  end

  @doc """
  Lists scenes for a given parent (or root level).
  Excludes soft-deleted scenes and orders by position then name.
  """
  def list_scenes_by_parent(project_id, parent_id) do
    from(scene in Scene,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      order_by: [asc: scene.position, asc: scene.name]
    )
    |> add_parent_filter(parent_id)
    |> Repo.all()
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
      |> add_parent_filter(parent_id)
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
      case References.normalize_optional_id(id) do
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

  defp move_locked_scene(scene, parent_id, position) do
    position = max(position, 0)

    case scene
         |> Scene.move_changeset(%{parent_id: parent_id, position: position})
         |> Repo.update() do
      {:ok, updated} ->
        apply_move(scene, updated, parent_id, position)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp apply_move(scene, updated, parent_id, position) do
    destination_pairs =
      scene.project_id
      |> list_scenes_by_parent(parent_id)
      |> Enum.reject(&(&1.id == scene.id))
      |> List.insert_at(position, updated)
      |> Enum.with_index()
      |> Enum.map(fn {sibling, index} -> {sibling.id, index} end)

    Positions.set_scene_positions(destination_pairs, scene.project_id, parent_id)

    if scene.parent_id != parent_id do
      reorder_source_container(scene.project_id, scene.parent_id)
    end

    {:ok, Repo.get!(Scene, scene.id)}
  end

  defp reorder_source_container(project_id, parent_id) do
    pairs =
      project_id
      |> list_scenes_by_parent(parent_id)
      |> Enum.with_index()
      |> Enum.map(fn {scene, index} -> {scene.id, index} end)

    Positions.set_scene_positions(pairs, project_id, parent_id)
  end

  defp add_parent_filter(query, nil), do: where(query, [scene], is_nil(scene.parent_id))
  defp add_parent_filter(query, parent_id), do: where(query, [scene], scene.parent_id == ^parent_id)
end
