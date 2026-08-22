defmodule Storyarn.Flows.Persistence.StorageReservationRecord do
  @moduledoc false

  use Ecto.Schema

  schema "workspace_storage_reservations" do
    field :workspace_id_snapshot, :integer
    field :status, :string
    field :reserved_bytes, :integer

    timestamps(type: :utc_datetime)
  end
end
