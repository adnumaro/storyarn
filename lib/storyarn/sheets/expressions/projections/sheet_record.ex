defmodule Storyarn.Sheets.Expressions.Projections.SheetRecord do
  @moduledoc """
  Logic-owned read model for the Sheet namespace of variables.

  It intentionally contains only the identity, display and lifecycle fields
  required to resolve qualified references and build the variable catalog.
  """

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
