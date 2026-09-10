defmodule Storyarn.Projects.Comments.Projections.ScenePinRecord do
  @moduledoc false
  use Ecto.Schema

  schema "scene_pins" do
    field(:scene_id, :integer)
    field(:label, :string)
    field(:inserted_at, :utc_datetime)
  end
end
