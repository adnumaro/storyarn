defmodule Storyarn.Platform.GlobalSearch.Persistence.SceneZoneRecord do
  @moduledoc false

  use Ecto.Schema

  schema "scene_zones" do
    field :name, :string
    field :shortcut, :string
    field :tooltip, :string
    field :scene_id, :id
  end
end
