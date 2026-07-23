defmodule Storyarn.AI.AllowanceGrant do
  @moduledoc "Operator-issued promotional managed-AI allowance grant."
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.AI.AllowanceAccount
  alias Storyarn.Workspaces.Workspace

  schema "ai_allowance_grants" do
    field :workspace_id_snapshot, :integer
    field :grant_key, :string
    field :kind, :string
    field :units, :integer
    field :remaining_units, :integer
    field :expires_at, :utc_datetime
    field :actor_id, :integer
    field :metadata, :map, default: %{}

    belongs_to :account, AllowanceAccount
    belongs_to :workspace, Workspace
    belongs_to :granted_by, User

    timestamps(type: :utc_datetime)
  end

  def create_changeset(grant, attrs) do
    grant
    |> cast(attrs, [:grant_key, :kind, :units, :remaining_units, :expires_at])
    |> put_change(:metadata, %{})
    |> put_identity_fields(attrs)
    |> validate_required([
      :account_id,
      :workspace_id,
      :workspace_id_snapshot,
      :grant_key,
      :kind,
      :units,
      :remaining_units,
      :granted_by_id,
      :actor_id
    ])
    |> validate_inclusion(:kind, ~w(one_time periodic adjustment))
    |> validate_length(:grant_key, min: 1, max: 160)
    |> validate_number(:units, greater_than: 0)
    |> validate_number(:remaining_units, greater_than_or_equal_to: 0)
    |> validate_remaining()
    |> unique_constraint([:workspace_id_snapshot, :grant_key])
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:granted_by_id)
  end

  defp validate_remaining(changeset) do
    units = get_field(changeset, :units)
    remaining = get_field(changeset, :remaining_units)

    if is_integer(units) and is_integer(remaining) and remaining > units,
      do: add_error(changeset, :remaining_units, "cannot exceed granted units"),
      else: changeset
  end

  defp put_identity_fields(changeset, attrs) do
    Enum.reduce(
      [:account_id, :workspace_id, :workspace_id_snapshot, :granted_by_id, :actor_id],
      changeset,
      fn field, acc -> put_change(acc, field, Map.get(attrs, field)) end
    )
  end
end
