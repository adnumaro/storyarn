defmodule Storyarn.Projects.SceneProjectTrash do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Collaboration
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Persistence.SceneRecord
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  def delete_subtree_in_transaction(%SceneRecord{id: scene_id}) do
    with project_id when is_integer(project_id) <- fetch_project_id(scene_id),
         %Project{deleted_at: nil} <- lock_project(project_id),
         %SceneRecord{deleted_at: nil} = scene <- lock_scene(scene_id, project_id),
         {:ok, deleted_scene} <- scene |> SceneRecord.delete_changeset() |> Repo.update() do
      child_ids = soft_delete_children(project_id, scene_id)
      %{entity: deleted_scene, deleted_ids: [deleted_scene.id | child_ids]}
    else
      nil -> Repo.rollback(:scene_not_found)
      %Project{} -> Repo.rollback(:project_not_active)
      %SceneRecord{} -> Repo.rollback(:scene_not_active)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def hard_delete(%SceneRecord{} = scene), do: Repo.delete(scene)

  def hard_delete(project_id, scene_id) do
    case Repo.one(
           from(scene in SceneRecord,
             where: scene.id == ^scene_id and scene.project_id == ^project_id
           )
         ) do
      nil -> {:error, :scene_not_found}
      scene -> hard_delete(scene)
    end
  end

  def restore(%SceneRecord{id: scene_id}) when is_integer(scene_id) do
    fn ->
      project_id = fetch_project_id(scene_id) || Repo.rollback(:scene_not_found)

      with %Project{deleted_at: nil} <- lock_project(project_id),
           %SceneRecord{} = scene <- lock_deleted_scene(scene_id, project_id),
           children = lock_restore_children(project_id, scene.id, scene.deleted_at),
           :ok <-
             Assets.lock_active_asset_references_for_restore(project_id,
               scene_ids: [scene.id | Enum.map(children, & &1.id)]
             ),
           {:ok, restored_scene} <- scene |> SceneRecord.restore_changeset() |> Repo.update() do
        restore_children(children)
        {restored_scene, project_id}
      else
        nil -> Repo.rollback(:scene_not_deleted)
        %Project{} -> Repo.rollback(:project_not_active)
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_restore()
  end

  defp fetch_project_id(scene_id) do
    Repo.one(from(scene in SceneRecord, where: scene.id == ^scene_id, select: scene.project_id))
  end

  defp lock_project(project_id) do
    Repo.one(from(project in Project, where: project.id == ^project_id, lock: "FOR UPDATE"))
  end

  defp lock_scene(scene_id, project_id) do
    Repo.one(
      from(scene in SceneRecord,
        where: scene.id == ^scene_id and scene.project_id == ^project_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_deleted_scene(scene_id, project_id) do
    Repo.one(
      from(scene in SceneRecord,
        where:
          scene.id == ^scene_id and scene.project_id == ^project_id and
            not is_nil(scene.deleted_at),
        lock: "FOR UPDATE"
      )
    )
  end

  defp soft_delete_children(project_id, parent_id) do
    now = TimeHelpers.now()

    children =
      Repo.all(
        from(scene in SceneRecord,
          where:
            scene.project_id == ^project_id and scene.parent_id == ^parent_id and
              is_nil(scene.deleted_at)
        )
      )

    Enum.flat_map(children, fn child ->
      Repo.update_all(
        from(scene in SceneRecord, where: scene.id == ^child.id),
        set: [deleted_at: now]
      )

      [child.id | soft_delete_children(project_id, child.id)]
    end)
  end

  defp lock_restore_children(project_id, parent_id, since) do
    since_threshold = DateTime.add(since, -1, :second)

    children =
      Repo.all(
        from(scene in SceneRecord,
          where:
            scene.project_id == ^project_id and scene.parent_id == ^parent_id and
              not is_nil(scene.deleted_at) and scene.deleted_at >= ^since_threshold,
          order_by: [asc: scene.id],
          lock: "FOR UPDATE"
        )
      )

    children ++
      Enum.flat_map(children, fn child ->
        lock_restore_children(project_id, child.id, since)
      end)
  end

  defp restore_children([]), do: :ok

  defp restore_children(children) do
    ids = Enum.map(children, & &1.id)
    {_count, _rows} = Repo.update_all(from(scene in SceneRecord, where: scene.id in ^ids), set: [deleted_at: nil])
    :ok
  end

  defp broadcast_restore({:ok, {scene, project_id}}) do
    Collaboration.broadcast_dashboard_change(project_id, :scenes)
    {:ok, scene}
  end

  defp broadcast_restore(result), do: result
end
