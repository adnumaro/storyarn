defmodule Storyarn.Scenes.AnnotationCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.PositionUtils
  alias Storyarn.Scenes.SceneAnnotation

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
    attrs = Storyarn.Shared.MapUtils.stringify_keys(attrs)

    PositionUtils.with_scene_lock(scene_id, fn ->
      with :ok <- PositionUtils.lock_requested_layer_for_scene(scene_id, attrs) do
        position = PositionUtils.next_position(SceneAnnotation, scene_id)

        %SceneAnnotation{scene_id: scene_id}
        |> SceneAnnotation.create_changeset(Map.put(attrs, "position", position))
        |> Repo.insert()
      end
    end)
  end

  def update_annotation(%SceneAnnotation{} = annotation, attrs) do
    PositionUtils.with_scene_lock(annotation.scene_id, fn ->
      with :ok <-
             PositionUtils.lock_requested_layer_for_scene(
               annotation.scene_id,
               attrs,
               annotation.layer_id
             ) do
        annotation
        |> SceneAnnotation.update_changeset(attrs)
        |> Repo.update()
      end
    end)
  end

  def move_annotation(%SceneAnnotation{} = annotation, position_x, position_y) do
    annotation
    |> SceneAnnotation.move_changeset(%{position_x: position_x, position_y: position_y})
    |> Repo.update()
  end

  def delete_annotation(%SceneAnnotation{} = annotation) do
    Repo.delete(annotation)
  end
end
