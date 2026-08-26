defmodule Storyarn.Flows.Logic.Data.ScenePinRecord do
  @moduledoc "Logic-owned read projection of Scene pins exposed as Flow variables."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "scene_pins" do
    field :label, :string
    field :shortcut, :string
    field :hidden, :boolean, default: false
    field :is_playable, :boolean, default: false
    field :is_leader, :boolean, default: false
    field :scene_id, :id

    timestamps(type: :utc_datetime)
  end
end
