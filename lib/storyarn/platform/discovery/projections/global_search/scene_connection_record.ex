defmodule Storyarn.Platform.GlobalSearch.Persistence.SceneConnectionRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Platform capability."

  use Ecto.Schema

  schema "scene_connections" do
    field :label, :string
    field :scene_id, :id
  end
end
