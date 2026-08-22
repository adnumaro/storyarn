defmodule Storyarn.Flows.Persistence.SceneZoneRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "scene_zones" do
    field :name, :string
    field :shortcut, :string
    field :hidden, :boolean, default: false
    field :condition, :map
    field :action_data, :map, default: %{}
    field :action_type, :string
    field :target_type, :string
    field :target_id, :integer
    field :scene_id, :id

    timestamps(type: :utc_datetime)
  end
end
