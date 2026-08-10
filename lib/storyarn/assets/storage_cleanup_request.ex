defmodule Storyarn.Assets.StorageCleanupRequest do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @provider_namespace_pattern ~r/\A[0-9a-f]{64}\z/

  @type t :: %__MODULE__{
          id: integer() | nil,
          storage_keys: [String.t()],
          owner_kind: String.t(),
          owner_token: Ecto.UUID.t() | nil,
          provider_namespace_fingerprint: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "storage_cleanup_requests" do
    field :storage_keys, {:array, :string}, default: []
    field :owner_kind, :string, default: "storage_compensation"
    field :owner_token, Ecto.UUID
    field :provider_namespace_fingerprint, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(request, attrs) do
    request
    |> cast(attrs, [:storage_keys, :owner_kind, :owner_token, :provider_namespace_fingerprint])
    |> validate_required([:storage_keys, :owner_kind])
    |> validate_length(:storage_keys, min: 1)
    |> validate_inclusion(:owner_kind, ["storage_compensation", "snapshot_lifecycle"])
    |> validate_format(:provider_namespace_fingerprint, @provider_namespace_pattern)
    |> validate_owner()
    |> unique_constraint(:owner_token)
    |> check_constraint(:owner_kind, name: :storage_cleanup_requests_owner)
    |> check_constraint(:provider_namespace_fingerprint,
      name: :storage_cleanup_requests_provider_namespace
    )
  end

  defp validate_owner(changeset) do
    ownership =
      {
        get_field(changeset, :owner_kind),
        get_field(changeset, :owner_token),
        get_field(changeset, :provider_namespace_fingerprint)
      }

    case ownership do
      {"storage_compensation", nil, nil} -> changeset
      {"snapshot_lifecycle", token, fingerprint} when is_binary(token) and is_binary(fingerprint) -> changeset
      _invalid -> add_error(changeset, :owner_kind, "does not match its ownership token")
    end
  end
end
