defmodule Storyarn.Platform.GlobalSearch.Persistence.ScenePinRecord do
  @moduledoc false

  use Ecto.Schema

  schema "scene_pins" do
    field :label, :string
    field :shortcut, :string
    field :tooltip, :string
    field :scene_id, :id
  end
end
