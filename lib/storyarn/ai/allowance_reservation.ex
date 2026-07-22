defmodule Storyarn.AI.AllowanceReservation do
  @moduledoc "Exactly-once reservation of a fixed managed task price."
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.AI.Operation
  alias Storyarn.Workspaces.Workspace

  schema "ai_allowance_reservations" do
    field :workspace_id_snapshot, :integer
    field :price_id, :string
    field :price_version, :integer
    field :units, :integer
    field :status, :string
    field :settled_at, :utc_datetime

    belongs_to :operation, Operation
    belongs_to :workspace, Workspace

    timestamps(type: :utc_datetime)
  end

  def create_changeset(reservation, attrs) do
    reservation
    |> cast(attrs, [:price_id, :price_version, :units, :status])
    |> put_identity_fields(attrs)
    |> validate_required([
      :operation_id,
      :workspace_id,
      :workspace_id_snapshot,
      :price_id,
      :price_version,
      :units,
      :status
    ])
    |> validate_inclusion(:status, ~w(reserved committed released))
    |> validate_number(:price_version, greater_than: 0)
    |> validate_number(:units, greater_than: 0)
    |> unique_constraint(:operation_id)
    |> foreign_key_constraint(:operation_id)
    |> foreign_key_constraint(:workspace_id)
  end

  def settle_changeset(reservation, status, settled_at) when status in ~w(committed released) do
    reservation
    |> change(status: status, settled_at: settled_at)
    |> validate_required([:status, :settled_at])
  end

  defp put_identity_fields(changeset, attrs) do
    Enum.reduce([:operation_id, :workspace_id, :workspace_id_snapshot], changeset, fn field, acc ->
      put_change(acc, field, Map.get(attrs, field))
    end)
  end
end
