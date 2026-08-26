defmodule Storyarn.Flows.Logic.Data.SceneZoneRecord do
  @moduledoc "Logic-owned read projection of Scene zones exposed as Flow variables."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "scene_zones" do
    field :name, :string
    field :shortcut, :string
    field :hidden, :boolean, default: false
    field :scene_id, :id

    timestamps(type: :utc_datetime)
  end
end
