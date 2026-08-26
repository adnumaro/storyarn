defmodule Storyarn.Flows.Logic.Data.SheetRecord do
  @moduledoc "Logic-owned namespace projection used by the Flow variable catalog."

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
