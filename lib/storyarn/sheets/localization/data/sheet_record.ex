defmodule Storyarn.Sheets.Localization.Data.SheetRecord do
  @moduledoc """
  Localization-owned read model of active Sheet runtime actors.

  Sheet names are localized because runtime serializers expose them as actor
  names; no editor mutation behavior belongs to this projection.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sheets" do
    field :name, :string
    field :project_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
