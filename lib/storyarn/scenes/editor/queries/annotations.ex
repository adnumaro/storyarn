defmodule Storyarn.Scenes.Editor.Queries.Annotations do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.SceneAnnotation

  def list_annotations(scene_id) do
    Repo.all(
      from(annotation in SceneAnnotation,
        where: annotation.scene_id == ^scene_id,
        order_by: [asc: annotation.position]
      )
    )
  end

  def get_annotation(scene_id, annotation_id) do
    Repo.one(
      from(annotation in SceneAnnotation,
        where: annotation.scene_id == ^scene_id and annotation.id == ^annotation_id
      )
    )
  end

  def get_annotation!(scene_id, annotation_id) do
    Repo.one!(
      from(annotation in SceneAnnotation,
        where: annotation.scene_id == ^scene_id and annotation.id == ^annotation_id
      )
    )
  end
end
