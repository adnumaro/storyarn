defmodule Storyarn.Assets.StorageCleanupRequest do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          storage_keys: [String.t()],
          owner_kind: String.t(),
          owner_token: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "storage_cleanup_requests" do
    field :storage_keys, {:array, :string}, default: []
    field :owner_kind, :string, default: "storage_compensation"
    field :owner_token, Ecto.UUID

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(request, attrs) do
    request
    |> cast(attrs, [:storage_keys, :owner_kind, :owner_token])
    |> validate_required([:storage_keys, :owner_kind])
    |> validate_length(:storage_keys, min: 1)
    |> validate_inclusion(:owner_kind, ["storage_compensation", "snapshot_lifecycle"])
    |> validate_owner()
    |> unique_constraint(:owner_token)
    |> check_constraint(:owner_kind, name: :storage_cleanup_requests_owner)
  end

  defp validate_owner(changeset) do
    case {get_field(changeset, :owner_kind), get_field(changeset, :owner_token)} do
      {"storage_compensation", nil} -> changeset
      {"snapshot_lifecycle", token} when is_binary(token) -> changeset
      _invalid -> add_error(changeset, :owner_kind, "does not match its ownership token")
    end
  end
end
