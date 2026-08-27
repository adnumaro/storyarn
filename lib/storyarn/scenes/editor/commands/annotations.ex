defmodule Storyarn.Scenes.Editor.Commands.Annotations do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.Repo
  alias Storyarn.Scenes.Editor.Commands.Positions
  alias Storyarn.Scenes.Editor.Commands.ReferenceIntegrity
  alias Storyarn.Scenes.Editor.Commands.Scenes
  alias Storyarn.Scenes.SceneAnnotation

  def create_annotation(scene_id, attrs) do
    attrs = MapAccess.stringify_keys(attrs)

    scene_id
    |> ReferenceIntegrity.with_active_scene_lock(fn scene ->
      with :ok <-
             Positions.lock_requested_layer_for_scene(scene.id, attrs) do
        position = Positions.next_position(SceneAnnotation, scene.id)

        %SceneAnnotation{scene_id: scene.id}
        |> SceneAnnotation.create_changeset(Map.put(attrs, "position", position))
        |> Repo.insert()
      end
    end)
    |> Scenes.broadcast_scene_dashboard_result(scene_id)
  end

  def update_annotation(%SceneAnnotation{} = annotation, attrs) do
    attrs = MapAccess.stringify_keys(attrs)

    annotation.scene_id
    |> ReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, locked_annotation} <-
             lock_annotation_for_scene(annotation.id, scene.id),
           :ok <-
             Positions.lock_requested_layer_for_scene(
               scene.id,
               attrs,
               locked_annotation.layer_id
             ) do
        locked_annotation
        |> SceneAnnotation.update_changeset(attrs)
        |> Repo.update()
      end
    end)
    |> Scenes.broadcast_scene_dashboard_result(annotation.scene_id)
  end

  def move_annotation(%SceneAnnotation{} = annotation, position_x, position_y) do
    annotation.scene_id
    |> ReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, locked_annotation} <-
             lock_annotation_for_scene(annotation.id, scene.id),
           :ok <-
             Positions.lock_requested_layer_for_scene(
               scene.id,
               %{},
               locked_annotation.layer_id
             ) do
        locked_annotation
        |> SceneAnnotation.move_changeset(%{
          position_x: position_x,
          position_y: position_y
        })
        |> Repo.update()
      end
    end)
    |> Scenes.broadcast_scene_dashboard_result(annotation.scene_id)
  end

  def delete_annotation(%SceneAnnotation{} = annotation) do
    annotation.scene_id
    |> ReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, locked_annotation} <-
             lock_annotation_for_scene(annotation.id, scene.id) do
        Repo.delete(locked_annotation)
      end
    end)
    |> Scenes.broadcast_scene_dashboard_result(annotation.scene_id)
  end

  defp lock_annotation_for_scene(annotation_id, scene_id) do
    case Repo.one(
           from(annotation in SceneAnnotation,
             where:
               annotation.id == ^annotation_id and
                 annotation.scene_id == ^scene_id,
             lock: "FOR UPDATE"
           )
         ) do
      %SceneAnnotation{} = annotation -> {:ok, annotation}
      nil -> {:error, :annotation_not_found}
    end
  end
end
