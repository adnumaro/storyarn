defmodule Storyarn.Platform.GlobalSearch.Persistence.SceneLayerRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Platform capability."

  use Ecto.Schema

  schema "scene_layers" do
    field :name, :string
    field :scene_id, :id
  end
end
