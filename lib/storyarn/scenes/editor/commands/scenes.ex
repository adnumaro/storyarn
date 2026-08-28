defmodule Storyarn.Scenes.Editor.Commands.Scenes do
  @moduledoc """
  Scene editor write workflows.

  Read concerns live in `Storyarn.Scenes.Editor.Queries.Scenes`; this module
  owns transactions, locks, mutations and the collaboration side effects that
  follow successful writes.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.Repo
  alias Storyarn.Scenes.Editor.Commands.ItemCapacity
  alias Storyarn.Scenes.Editor.Commands.ReferenceIntegrity
  alias Storyarn.Scenes.Editor.Commands.RestoreAssetReferences
  alias Storyarn.Scenes.Editor.Commands.Shortcuts
  alias Storyarn.Scenes.Editor.Commands.SoftDelete
  alias Storyarn.Scenes.Editor.Queries.Scenes, as: SceneQueries
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneLayer

  @scene_preloads [
    :layers,
    [zones: [:label_icon_asset]],
    [pins: [:icon_asset, sheet: [avatars: :asset]]],
    :annotations,
    :background_asset,
    connections: [:from_pin, :to_pin]
  ]

  @doc "Invalidates the Scenes dashboard after a successful child write."
  @spec broadcast_scene_dashboard_result(term(), term()) :: term()
  def broadcast_scene_dashboard_result(result, scene_id)

  def broadcast_scene_dashboard_result({:ok, _value} = result, scene_id) do
    project_id = Repo.one(from(scene in Scene, where: scene.id == ^scene_id, select: scene.project_id))

    if project_id, do: Collaboration.broadcast_dashboard_change(project_id, :scenes)

    result
  end

  def broadcast_scene_dashboard_result(result, _scene_id), do: result

  @doc false
  @spec broadcast_scene_dashboard_project_result(term()) :: term()
  def broadcast_scene_dashboard_project_result({:ok, {value, project_id}}) do
    Collaboration.broadcast_dashboard_change(project_id, :scenes)
    {:ok, value}
  end

  def broadcast_scene_dashboard_project_result(result), do: result

  @doc "Creates a scene with its generated shortcut and default layer."
  def create_scene(%{user: %{id: actor_id}}, project, attrs) when is_integer(actor_id) and actor_id > 0 do
    project_id = project_id!(project)

    result =
      fn ->
        scene = create_scene_in_transaction(project_id, attrs)
        {scene, deliver_content_activity!(actor_id, project_id, :created, scene)}
      end
      |> Repo.transaction()
      |> normalize_item_limit_result()

    case result do
      {:ok, {scene, notification_outcome}} ->
        Platform.publish_notification_delivery(notification_outcome)
        Collaboration.broadcast_dashboard_change(project_id, :scenes)
        {:ok, scene}

      other ->
        other
    end
  end

  def create_scene(project, attrs) do
    project_id = project_id!(project)
    result = do_create_scene(project, attrs)

    case result do
      {:ok, _scene} -> Collaboration.broadcast_dashboard_change(project_id, :scenes)
      _other -> :ok
    end

    result
  end

  defp do_create_scene(project, attrs) do
    fn -> create_scene_in_transaction(project_id!(project), attrs) end
    |> Repo.transaction()
    |> normalize_item_limit_result()
  end

  @doc false
  def create_scene_in_transaction(project, attrs) do
    project_id = project_id!(project)

    with {:ok, locked_project} <- ReferenceIntegrity.lock_active_project(project_id, :update),
         :ok <- ItemCapacity.can_create_item?(locked_project),
         attrs = maybe_generate_shortcut(attrs, locked_project.id, nil),
         {:ok, attrs} <-
           ReferenceIntegrity.lock_scene_root_references(
             %Scene{project_id: locked_project.id},
             attrs
           ) do
      attrs = maybe_assign_position(attrs, locked_project.id, attrs["parent_id"])
      insert_scene_with_default_layer(locked_project.id, attrs)
    else
      {:error, reason, details} -> Repo.rollback({reason, details})
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc false
  def create_scene_in_transaction(%{user: %{id: actor_id}}, project, attrs) when is_integer(actor_id) and actor_id > 0 do
    project_id = project_id!(project)
    scene = create_scene_in_transaction(project_id, attrs)
    {scene, deliver_content_activity!(actor_id, project_id, :created, scene)}
  end

  @doc "Updates an active scene and revalidates all effective references."
  def update_scene(%Scene{} = scene, attrs) do
    scene.id
    |> ReferenceIntegrity.with_active_scene_lock(
      [project_lock: :update],
      fn locked_scene ->
        attrs = maybe_generate_shortcut_on_update(locked_scene, attrs)

        with {:ok, attrs} <- ReferenceIntegrity.lock_scene_root_references(locked_scene, attrs),
             {:ok, updated_scene} <-
               locked_scene
               |> Scene.update_changeset(attrs)
               |> Repo.update() do
          {:ok, Repo.preload(updated_scene, @scene_preloads, force: true)}
        end
      end
    )
    |> broadcast_scene_dashboard_result(scene.id)
  end

  @doc "Soft-deletes a scene and its active descendants."
  def delete_scene(%Scene{} = scene) do
    with {:ok, %{entity: entity}} <- delete_scene_subtree(scene), do: {:ok, entity}
  end

  def delete_scene(%{user: %{id: actor_id}} = actor_scope, %Scene{} = scene) when is_integer(actor_id) and actor_id > 0 do
    with {:ok, %{entity: entity}} <- delete_scene_subtree(actor_scope, scene),
         do: {:ok, entity}
  end

  @doc "Soft-deletes a scene and returns the committed cascade ids."
  def delete_scene_subtree(%Scene{} = scene) do
    result = Repo.transaction(fn -> delete_scene_subtree_in_transaction(scene) end)

    case result do
      {:ok, %{entity: deleted_scene}} ->
        Collaboration.broadcast_dashboard_change(deleted_scene.project_id, :scenes)

      _other ->
        :ok
    end

    result
  end

  def delete_scene_subtree(%{user: %{id: actor_id}} = actor_scope, %Scene{} = scene)
      when is_integer(actor_id) and actor_id > 0 do
    result = Repo.transaction(fn -> delete_scene_subtree_in_transaction(actor_scope, scene) end)

    case result do
      {:ok, %{entity: deleted_scene, notification_outcome: notification_outcome} = deleted} ->
        Platform.publish_notification_delivery(notification_outcome)
        Collaboration.broadcast_dashboard_change(deleted_scene.project_id, :scenes)
        {:ok, Map.delete(deleted, :notification_outcome)}

      _other ->
        result
    end
  end

  @doc false
  def delete_scene_subtree_in_transaction(%Scene{} = scene) do
    ReferenceIntegrity.with_active_scene_lock_in_transaction(
      scene.id,
      [project_lock: :update],
      fn locked_scene ->
        case locked_scene |> Scene.delete_changeset() |> Repo.update() do
          {:ok, deleted_scene} ->
            child_ids =
              SoftDelete.soft_delete_children(
                Scene,
                locked_scene.project_id,
                locked_scene.id
              )

            {:ok, %{entity: deleted_scene, deleted_ids: [deleted_scene.id | child_ids]}}

          {:error, changeset} ->
            {:error, changeset}
        end
      end
    )
  end

  @doc false
  def delete_scene_subtree_in_transaction(%{user: %{id: actor_id}}, %Scene{} = scene)
      when is_integer(actor_id) and actor_id > 0 do
    deleted = delete_scene_subtree_in_transaction(scene)

    outcome =
      deliver_content_activity!(actor_id, deleted.entity.project_id, :deleted, deleted.entity)

    Map.put(deleted, :notification_outcome, outcome)
  end

  @doc false
  def delete_scene_subtree_by_id_in_transaction(%{user: %{id: actor_id}} = actor_scope, project_id, scene_id)
      when is_integer(actor_id) and actor_id > 0 do
    case SceneQueries.get_scene_brief(project_id, scene_id) do
      %Scene{} = scene -> delete_scene_subtree_in_transaction(actor_scope, scene)
      nil -> Repo.rollback(:not_found)
    end
  end

  @doc "Permanently deletes a scene."
  def hard_delete_scene(%Scene{} = scene), do: Repo.delete(scene)

  @doc "Restores a scene and descendants deleted in the same cascade."
  def restore_scene(%Scene{id: scene_id}) when is_integer(scene_id) do
    fn ->
      project_id =
        Repo.one(from(scene in Scene, where: scene.id == ^scene_id, select: scene.project_id)) ||
          Repo.rollback(:scene_not_found)

      with {:ok, _project} <- ReferenceIntegrity.lock_active_project(project_id, :update),
           %Scene{} = locked_scene <-
             Repo.one(
               from(scene in Scene,
                 where:
                   scene.id == ^scene_id and scene.project_id == ^project_id and
                     not is_nil(scene.deleted_at),
                 lock: "FOR UPDATE"
               )
             ),
           restore_children =
             lock_scene_restore_children(project_id, locked_scene.id, locked_scene.deleted_at),
           :ok <-
             RestoreAssetReferences.lock_active_for_restore(project_id,
               scene_ids: [locked_scene.id | Enum.map(restore_children, & &1.id)]
             ),
           {:ok, restored_scene} <-
             locked_scene
             |> Scene.restore_changeset()
             |> Repo.update() do
        restore_locked_scene_children(restore_children)
        {restored_scene, project_id}
      else
        nil -> Repo.rollback(:scene_not_deleted)
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_scene_dashboard_project_result()
  end

  @doc "Returns a changeset for tracking scene form changes."
  def change_scene(%Scene{} = scene, attrs \\ %{}), do: Scene.update_changeset(scene, attrs)

  defp insert_scene_with_default_layer(project_id, attrs) do
    case %Scene{project_id: project_id}
         |> Scene.create_changeset(attrs)
         |> Repo.insert() do
      {:ok, scene} ->
        %SceneLayer{scene_id: scene.id}
        |> SceneLayer.create_changeset(%{name: "Default", is_default: true, position: 0})
        |> Repo.insert!()

        scene

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp deliver_content_activity!(actor_id, project_id, action, scene) do
    case Platform.deliver_content_activity_by_ids(actor_id, project_id, action, "scene", scene) do
      {:ok, outcome} -> outcome
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_scene_restore_children(project_id, parent_id, since) do
    since_threshold = DateTime.add(since, -1, :second)

    children =
      Repo.all(
        from(scene in Scene,
          where:
            scene.project_id == ^project_id and scene.parent_id == ^parent_id and
              not is_nil(scene.deleted_at) and scene.deleted_at >= ^since_threshold,
          order_by: [asc: scene.id],
          lock: "FOR UPDATE"
        )
      )

    children ++
      Enum.flat_map(children, fn child ->
        lock_scene_restore_children(project_id, child.id, since)
      end)
  end

  defp restore_locked_scene_children([]), do: :ok

  defp restore_locked_scene_children(children) do
    child_ids = Enum.map(children, & &1.id)

    {_count, _rows} =
      Repo.update_all(from(scene in Scene, where: scene.id in ^child_ids),
        set: [deleted_at: nil]
      )

    :ok
  end

  defp normalize_item_limit_result({:error, {:limit_reached, details}}), do: {:error, :limit_reached, details}

  defp normalize_item_limit_result(result), do: result

  defp maybe_generate_shortcut(attrs, project_id, exclude_scene_id) do
    attrs
    |> stringify_keys()
    |> Shortcuts.prepare_create(project_id, exclude_scene_id)
  end

  defp maybe_generate_shortcut_on_update(%Scene{} = scene, attrs) do
    Shortcuts.prepare_update(scene, attrs)
  end

  defp stringify_keys(attrs), do: MapAccess.stringify_keys(attrs)

  defp maybe_assign_position(attrs, project_id, parent_id) do
    Shortcuts.assign_position(attrs, project_id, parent_id)
  end

  defp project_id!(%{id: project_id}), do: project_id!(project_id)
  defp project_id!(project_id) when is_integer(project_id) and project_id > 0, do: project_id

  defp project_id!(project) do
    raise ArgumentError, "expected a Scene project identity, got: #{inspect(project)}"
  end
end
