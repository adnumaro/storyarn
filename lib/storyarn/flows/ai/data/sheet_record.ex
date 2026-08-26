defmodule Storyarn.Flows.AI.Data.SheetRecord do
  @moduledoc "AI-owned speaker Sheet projection used in dialogue context packages."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sheets" do
    field :name, :string
    field :shortcut, :string
    field :description, :string
    field :project_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
