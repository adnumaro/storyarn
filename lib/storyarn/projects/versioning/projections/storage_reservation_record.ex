defmodule Storyarn.Projects.Persistence.StorageReservationRecord do
  @moduledoc """
  Project-owned read model for the storage reservation protocol persisted by
  Commercial Billing.

  Billing remains the only ordinary writer of
  `workspace_storage_reservations`. Projects duplicates the persisted shape so
  snapshot and restore invariants can be queried without compiling against
  Billing's Ecto schema.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspace_storage_reservations" do
    field :workspace_id, :id
    field :project_id, :id
    field :project_snapshot_id, :id
    field :workspace_id_snapshot, :integer
    field :project_id_snapshot, :integer
    field :project_snapshot_id_snapshot, :integer
    field :idempotency_key, :string
    field :kind, :string
    field :status, :string
    field :storage_namespace, :string
    field :cleanup_object_prefix, :string
    field :reserved_bytes, :integer
    field :actual_bytes, :integer
    field :lease_token, Ecto.UUID
    field :generation, :integer
    field :expires_at, :utc_datetime
    field :storage_started_at, :utc_datetime
    field :cleanup_inventory_digest, :string
    field :cleanup_inventory_count, :integer
    field :cleanup_storage_keys, {:array, :string}
    field :settled_at, :utc_datetime
    field :release_reason, :string
    field :cleanup_status, :string
    field :cleanup_reference, :string
    field :accounting_version, :integer
    field :accounting_measured_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
