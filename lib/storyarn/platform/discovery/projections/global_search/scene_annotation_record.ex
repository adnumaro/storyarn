defmodule Storyarn.Platform.GlobalSearch.Persistence.SceneAnnotationRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Platform capability."

  use Ecto.Schema

  schema "scene_annotations" do
    field :text, :string
    field :scene_id, :id
  end
end
