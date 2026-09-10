defmodule Storyarn.Projects.Comments.Projections.SceneAnnotationRecord do
  @moduledoc false
  use Ecto.Schema

  schema "scene_annotations" do
    field(:scene_id, :integer)
    field(:text, :string)
    field(:inserted_at, :utc_datetime)
  end
end
