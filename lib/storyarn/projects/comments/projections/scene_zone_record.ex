defmodule Storyarn.Projects.Comments.Projections.SceneZoneRecord do
  @moduledoc false
  use Ecto.Schema

  schema "scene_zones" do
    field(:scene_id, :integer)
    field(:name, :string)
    field(:inserted_at, :utc_datetime)
  end
end
