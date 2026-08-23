defmodule Storyarn.GlobalSearch.Persistence.SceneLayerRecord do
  @moduledoc false

  use Ecto.Schema

  schema "scene_layers" do
    field :name, :string
    field :scene_id, :id
  end
end
