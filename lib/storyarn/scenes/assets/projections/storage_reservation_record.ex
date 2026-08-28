defmodule Storyarn.Scenes.Assets.Projections.StorageReservationRecord do
  @moduledoc "Assets-owned consumer-local SQL projection used by Scene asset writes and storage accounting without importing another context's schema."

  use Ecto.Schema

  schema "workspace_storage_reservations" do
    field :workspace_id_snapshot, :integer
    field :kind, :string
    field :status, :string
    field :reserved_bytes, :integer
    field :storage_started_at, :utc_datetime
    field :cleanup_storage_keys, {:array, :string}

    timestamps(type: :utc_datetime)
  end
end
