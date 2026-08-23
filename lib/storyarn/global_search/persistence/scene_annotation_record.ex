defmodule Storyarn.GlobalSearch.Persistence.SceneAnnotationRecord do
  @moduledoc false

  use Ecto.Schema

  schema "scene_annotations" do
    field :text, :string
    field :scene_id, :id
  end
end
