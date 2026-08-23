defmodule Storyarn.GlobalSearch.Persistence.SceneConnectionRecord do
  @moduledoc false

  use Ecto.Schema

  schema "scene_connections" do
    field :label, :string
    field :scene_id, :id
  end
end
