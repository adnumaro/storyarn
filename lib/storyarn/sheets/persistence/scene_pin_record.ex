defmodule Storyarn.Sheets.Persistence.ScenePinRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "scene_pins" do
    field :label, :string
    field :condition, :map
    field :scene_id, :id
    field :sheet_id, :id

    timestamps(type: :utc_datetime)
  end
end
