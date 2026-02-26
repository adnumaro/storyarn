defmodule Storyarn.Scenes.AnnotationCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.{PositionUtils, SceneAnnotation}

  def list_annotations(scene_id) do
    from(a in SceneAnnotation,
      where: a.scene_id == ^scene_id,
      order_by: [asc: a.position]
    )
    |> Repo.all()
  end

  def get_annotation(scene_id, annotation_id) do
    from(a in SceneAnnotation, where: a.scene_id == ^scene_id and a.id == ^annotation_id)
    |> Repo.one()
  end

  def get_annotation!(scene_id, annotation_id) do
    from(a in SceneAnnotation, where: a.scene_id == ^scene_id and a.id == ^annotation_id)
    |> Repo.one!()
  end

  def create_annotation(scene_id, attrs) do
    position = PositionUtils.next_position(SceneAnnotation, scene_id)
    attrs = Storyarn.Shared.MapUtils.stringify_keys(attrs)

    %SceneAnnotation{scene_id: scene_id}
    |> SceneAnnotation.create_changeset(Map.put(attrs, "position", position))
    |> Repo.insert()
  end

  def update_annotation(%SceneAnnotation{} = annotation, attrs) do
    annotation
    |> SceneAnnotation.update_changeset(attrs)
    |> Repo.update()
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
