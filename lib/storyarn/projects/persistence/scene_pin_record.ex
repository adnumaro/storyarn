defmodule Storyarn.Projects.Persistence.ScenePinRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "scene_pins" do
    field :label, :string
    field :shortcut, :string
    field :hidden, :boolean, default: false
    field :is_playable, :boolean, default: false
    field :is_leader, :boolean, default: false
    field :condition, :map
    field :sheet_id, :id
    field :flow_id, :id
    field :scene_id, :id

    timestamps(type: :utc_datetime)
  end
end
