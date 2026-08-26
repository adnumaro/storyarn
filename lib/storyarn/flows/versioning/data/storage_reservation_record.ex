defmodule Storyarn.Flows.Versioning.Data.StorageReservationRecord do
  @moduledoc """
  Versioning-owned reservation projection used only for workspace storage accounting.
  """

  use Ecto.Schema

  schema "workspace_storage_reservations" do
    field :workspace_id_snapshot, :integer
    field :status, :string
    field :reserved_bytes, :integer

    timestamps(type: :utc_datetime)
  end
end
