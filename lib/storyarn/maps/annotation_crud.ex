defmodule Storyarn.Maps.AnnotationCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Maps.{MapAnnotation, PositionUtils}
  alias Storyarn.Repo

  def list_annotations(map_id) do
    from(a in MapAnnotation,
      where: a.map_id == ^map_id,
      order_by: [asc: a.position]
    )
    |> Repo.all()
  end

  def get_annotation(annotation_id) do
    Repo.get(MapAnnotation, annotation_id)
  end

  def get_annotation!(annotation_id) do
    Repo.get!(MapAnnotation, annotation_id)
  end

  def get_annotation(map_id, annotation_id) do
    from(a in MapAnnotation, where: a.map_id == ^map_id and a.id == ^annotation_id)
    |> Repo.one()
  end

  def get_annotation!(map_id, annotation_id) do
    from(a in MapAnnotation, where: a.map_id == ^map_id and a.id == ^annotation_id)
    |> Repo.one!()
  end

  def create_annotation(map_id, attrs) do
    position = PositionUtils.next_position(MapAnnotation, map_id)
    attrs = Storyarn.Shared.MapUtils.stringify_keys(attrs)

    %MapAnnotation{map_id: map_id}
    |> MapAnnotation.create_changeset(Map.put(attrs, "position", position))
    |> Repo.insert()
  end

  def update_annotation(%MapAnnotation{} = annotation, attrs) do
    annotation
    |> MapAnnotation.update_changeset(attrs)
    |> Repo.update()
  end

  def move_annotation(%MapAnnotation{} = annotation, position_x, position_y) do
    annotation
    |> MapAnnotation.move_changeset(%{position_x: position_x, position_y: position_y})
    |> Repo.update()
  end

  def delete_annotation(%MapAnnotation{} = annotation) do
    Repo.delete(annotation)
  end

end
