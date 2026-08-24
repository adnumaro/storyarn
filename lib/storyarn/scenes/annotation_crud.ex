defmodule Storyarn.Scenes.AnnotationCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.MapUtils
  alias Storyarn.Repo
  alias Storyarn.Scenes.PositionUtils
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneCrud
  alias Storyarn.Scenes.SceneReferenceIntegrity

  def list_annotations(scene_id) do
    Repo.all(from(a in SceneAnnotation, where: a.scene_id == ^scene_id, order_by: [asc: a.position]))
  end

  def get_annotation(scene_id, annotation_id) do
    Repo.one(from(a in SceneAnnotation, where: a.scene_id == ^scene_id and a.id == ^annotation_id))
  end

  def get_annotation!(scene_id, annotation_id) do
    Repo.one!(from(a in SceneAnnotation, where: a.scene_id == ^scene_id and a.id == ^annotation_id))
  end

  def create_annotation(scene_id, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    scene_id
    |> SceneReferenceIntegrity.with_active_scene_lock(fn scene ->
      with :ok <-
             PositionUtils.lock_requested_layer_for_scene(scene.id, attrs) do
        position = PositionUtils.next_position(SceneAnnotation, scene.id)

        %SceneAnnotation{scene_id: scene.id}
        |> SceneAnnotation.create_changeset(Map.put(attrs, "position", position))
        |> Repo.insert()
      end
    end)
    |> SceneCrud.broadcast_scene_dashboard_result(scene_id)
  end

  def update_annotation(%SceneAnnotation{} = annotation, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    annotation.scene_id
    |> SceneReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, locked_annotation} <-
             lock_annotation_for_scene(annotation.id, scene.id),
           :ok <-
             PositionUtils.lock_requested_layer_for_scene(
               scene.id,
               attrs,
               locked_annotation.layer_id
             ) do
        locked_annotation
        |> SceneAnnotation.update_changeset(attrs)
        |> Repo.update()
      end
    end)
    |> SceneCrud.broadcast_scene_dashboard_result(annotation.scene_id)
  end

  def move_annotation(%SceneAnnotation{} = annotation, position_x, position_y) do
    annotation.scene_id
    |> SceneReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, locked_annotation} <-
             lock_annotation_for_scene(annotation.id, scene.id),
           :ok <-
             PositionUtils.lock_requested_layer_for_scene(
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
    |> SceneCrud.broadcast_scene_dashboard_result(annotation.scene_id)
  end

  def delete_annotation(%SceneAnnotation{} = annotation) do
    annotation.scene_id
    |> SceneReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, locked_annotation} <-
             lock_annotation_for_scene(annotation.id, scene.id) do
        Repo.delete(locked_annotation)
      end
    end)
    |> SceneCrud.broadcast_scene_dashboard_result(annotation.scene_id)
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
