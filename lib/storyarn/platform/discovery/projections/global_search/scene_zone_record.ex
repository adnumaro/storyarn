defmodule Storyarn.Platform.GlobalSearch.Persistence.SceneZoneRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Platform capability."

  use Ecto.Schema

  schema "scene_zones" do
    field :name, :string
    field :shortcut, :string
    field :tooltip, :string
    field :scene_id, :id
  end
end
