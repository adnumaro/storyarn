defmodule Storyarn.Commercial.Billing.Persistence.ProjectSnapshotRestoreRecord do
  @moduledoc """
  Billing-owned read model for the durable owner of a restore reservation.

  Restore lifecycle and mutation rules remain in Projects; Commercial only locks
  and verifies the identity needed to settle capacity.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "project_snapshot_restores" do
    field :workspace_id, :id
    field :project_id, :id
    field :project_snapshot_id, :id
    field :storage_reservation_id, :id
    field :status, :string
    field :generation, :integer

    timestamps(type: :utc_datetime)
  end
end
