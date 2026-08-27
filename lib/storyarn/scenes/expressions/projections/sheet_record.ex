defmodule Storyarn.Scenes.Expressions.Projections.SheetRecord do
  @moduledoc "Logic-owned projection of the Sheet namespace used by Scene variables."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sheets" do
    field :name, :string
    field :shortcut, :string
    field :project_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
