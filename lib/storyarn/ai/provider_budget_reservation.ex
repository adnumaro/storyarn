defmodule Storyarn.AI.ProviderBudgetReservation do
  @moduledoc "Provider-cost reservation used by managed global and workspace circuit breakers."
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.AI.Operation
  alias Storyarn.Workspaces.Workspace

  schema "ai_provider_budget_reservations" do
    field :workspace_id_snapshot, :integer
    field :provider, :string
    field :model, :string
    field :price_snapshot, :map
    field :estimated_cost, :decimal
    field :actual_cost, :decimal
    field :currency, :string
    field :status, :string
    field :settled_at, :utc_datetime

    belongs_to :operation, Operation
    belongs_to :workspace, Workspace

    timestamps(type: :utc_datetime)
  end

  def create_changeset(reservation, attrs) do
    reservation
    |> cast(attrs, [
      :provider,
      :model,
      :price_snapshot,
      :estimated_cost,
      :currency,
      :status
    ])
    |> put_identity_fields(attrs)
    |> validate_required([
      :operation_id,
      :workspace_id,
      :workspace_id_snapshot,
      :provider,
      :model,
      :price_snapshot,
      :estimated_cost,
      :currency,
      :status
    ])
    |> validate_inclusion(:status, ["reserved"])
    |> validate_number(:estimated_cost, greater_than_or_equal_to: 0)
    |> validate_length(:currency, min: 1, max: 12)
    |> unique_constraint(:operation_id)
    |> foreign_key_constraint(:operation_id)
    |> foreign_key_constraint(:workspace_id)
  end

  def settle_changeset(reservation, actual_cost, settled_at) do
    reservation
    |> change(status: "settled", actual_cost: actual_cost, settled_at: settled_at)
    |> validate_required([:status, :actual_cost, :settled_at])
    |> validate_number(:actual_cost, greater_than_or_equal_to: 0)
  end

  defp put_identity_fields(changeset, attrs) do
    Enum.reduce([:operation_id, :workspace_id, :workspace_id_snapshot], changeset, fn field, acc ->
      put_change(acc, field, Map.get(attrs, field))
    end)
  end
end
