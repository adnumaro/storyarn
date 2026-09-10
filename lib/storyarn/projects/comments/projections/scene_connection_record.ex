defmodule Storyarn.Projects.Comments.Projections.SceneConnectionRecord do
  @moduledoc false
  use Ecto.Schema

  schema "scene_connections" do
    field(:scene_id, :integer)
    field(:label, :string)
    field(:inserted_at, :utc_datetime)
  end
end
