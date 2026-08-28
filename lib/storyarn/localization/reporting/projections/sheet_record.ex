defmodule Storyarn.Localization.Reporting.Projections.SheetRecord do
  @moduledoc """
  Read-only Reporting projection of the Sheet identity used for speaker labels.

  Localization Reporting owns this consumer-specific representation and never
  imports `Storyarn.Sheets` code to calculate voice-over metrics.
  """

  use Ecto.Schema

  schema "sheets" do
    field :name, :string
    field :deleted_at, :utc_datetime
  end
end
