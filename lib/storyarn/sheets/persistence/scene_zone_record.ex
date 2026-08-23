defmodule Storyarn.Sheets.Persistence.SceneZoneRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "scene_zones" do
    field :name, :string
    field :action_data, :map, default: %{}
    field :target_type, :string
    field :target_id, :integer
    field :scene_id, :id

    timestamps(type: :utc_datetime)
  end
end
