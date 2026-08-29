defmodule Storyarn.Commercial.Billing.Persistence.AssetRecord do
  @moduledoc """
  Billing-owned read model for storage-bearing project assets.

  It intentionally maps only the columns needed to account retained and
  soft-deleted bytes. Project asset rules remain owned by Projects.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "assets" do
    field :project_id, :id
    field :size, :integer
    field :deleted_at, :utc_datetime
  end
end
