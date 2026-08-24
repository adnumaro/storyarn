defmodule Storyarn.Platform.GlobalSearch.Persistence.SheetRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sheets" do
    field :name, :string
    field :shortcut, :string
    field :description, :string
    field :color, :string
    field :position, :integer, default: 0
    field :project_id, :id
    field :parent_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
