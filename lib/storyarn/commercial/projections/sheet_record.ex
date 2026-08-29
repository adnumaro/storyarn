defmodule Storyarn.Commercial.Billing.Persistence.SheetRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Commercial capability."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sheets" do
    field :project_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
