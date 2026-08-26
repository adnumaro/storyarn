defmodule Storyarn.Sheets.References.Data.ScenePinRecord do
  @moduledoc """
  References-local projection of Scene pins that mention Sheet variables or
  display a Sheet. It is read-only outside the projection maintenance command.
  """

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
