defmodule Storyarn.AI.AllowanceAllocation do
  @moduledoc "Grant allocation retained so a release restores only still-valid allowance."
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.AI.AllowanceGrant
  alias Storyarn.AI.AllowanceReservation

  schema "ai_allowance_allocations" do
    field :units, :integer
    field :restored_units, :integer, default: 0

    belongs_to :reservation, AllowanceReservation
    belongs_to :grant, AllowanceGrant

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def create_changeset(allocation, attrs) do
    allocation
    |> cast(attrs, [:units])
    |> put_change(:reservation_id, Map.get(attrs, :reservation_id))
    |> put_change(:grant_id, Map.get(attrs, :grant_id))
    |> validate_required([:reservation_id, :grant_id, :units])
    |> validate_number(:units, greater_than: 0)
    |> unique_constraint([:reservation_id, :grant_id])
    |> foreign_key_constraint(:reservation_id)
    |> foreign_key_constraint(:grant_id)
  end

  def restore_changeset(allocation, restored_units) do
    allocation
    |> change(restored_units: restored_units)
    |> validate_required([:restored_units])
    |> validate_number(:restored_units, greater_than_or_equal_to: 0, less_than_or_equal_to: allocation.units)
  end
end
