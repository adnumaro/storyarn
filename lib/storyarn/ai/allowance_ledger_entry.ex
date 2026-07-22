defmodule Storyarn.AI.AllowanceLedgerEntry do
  @moduledoc "Append-only, content-free audit entry for managed allowance movement."
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.AI.AllowanceGrant
  alias Storyarn.AI.AllowanceReservation
  alias Storyarn.AI.Operation
  alias Storyarn.Workspaces.Workspace

  schema "ai_allowance_ledger_entries" do
    field :workspace_id_snapshot, :integer
    field :kind, :string
    field :units, :integer
    field :available_delta, :integer
    field :idempotency_key, :string
    field :metadata, :map, default: %{}

    belongs_to :workspace, Workspace
    belongs_to :operation, Operation
    belongs_to :grant, AllowanceGrant
    belongs_to :reservation, AllowanceReservation

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:kind, :units, :available_delta, :idempotency_key, :metadata])
    |> put_identity_fields(attrs)
    |> validate_required([
      :workspace_id_snapshot,
      :kind,
      :units,
      :available_delta,
      :idempotency_key
    ])
    |> validate_inclusion(:kind, ~w(grant reserve commit release adjustment expiry))
    |> validate_number(:units, greater_than: 0)
    |> validate_length(:idempotency_key, min: 1, max: 200)
    |> validate_workspace_identity()
    |> unique_constraint([:workspace_id_snapshot, :idempotency_key],
      name: :ai_allowance_ledger_workspace_idempotency_unique
    )
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:operation_id)
    |> foreign_key_constraint(:grant_id)
    |> foreign_key_constraint(:reservation_id)
  end

  defp validate_workspace_identity(changeset) do
    case {get_field(changeset, :workspace_id), get_field(changeset, :workspace_id_snapshot)} do
      {nil, snapshot} when is_integer(snapshot) -> changeset
      {workspace_id, workspace_id} when is_integer(workspace_id) -> changeset
      {_workspace_id, _snapshot} -> add_error(changeset, :workspace_id_snapshot, "must match workspace")
    end
  end

  defp put_identity_fields(changeset, attrs) do
    Enum.reduce(
      [:workspace_id, :workspace_id_snapshot, :operation_id, :grant_id, :reservation_id],
      changeset,
      fn field, acc -> put_change(acc, field, Map.get(attrs, field)) end
    )
  end
end
