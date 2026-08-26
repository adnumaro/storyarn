defmodule Storyarn.Sheets.Localization.Data.ProjectRecord do
  @moduledoc """
  Minimal read model used to serialize Sheet localization reconciliation.

  Localization only needs to lock the project identity and reject deleted
  projects; Project lifecycle and writes remain outside this capability.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "projects" do
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
