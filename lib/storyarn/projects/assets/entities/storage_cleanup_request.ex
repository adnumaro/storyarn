defmodule Storyarn.Projects.Assets.StorageCleanupRequest do
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
          multipart_quiescence_started_at: DateTime.t() | nil,
          multipart_quiescence_not_before: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "storage_cleanup_requests" do
    field :storage_keys, {:array, :string}, default: []
    field :owner_kind, :string, default: "storage_compensation"
    field :owner_token, Ecto.UUID
    field :provider_namespace_fingerprint, :string
    field :multipart_quiescence_started_at, :utc_datetime
    field :multipart_quiescence_not_before, :utc_datetime

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
    |> check_constraint(:multipart_quiescence_not_before,
      name: :storage_cleanup_requests_multipart_quiescence
    )
  end

  @doc false
  def multipart_quiescence_changeset(request, started_at, not_before) do
    request
    |> change(
      multipart_quiescence_started_at: started_at,
      multipart_quiescence_not_before: not_before
    )
    |> validate_multipart_quiescence()
    |> check_constraint(:multipart_quiescence_not_before,
      name: :storage_cleanup_requests_multipart_quiescence
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

  defp validate_multipart_quiescence(changeset) do
    started_at = get_field(changeset, :multipart_quiescence_started_at)
    not_before = get_field(changeset, :multipart_quiescence_not_before)

    case {started_at, not_before} do
      {nil, nil} ->
        changeset

      {%DateTime{} = started_at, %DateTime{} = not_before} ->
        if DateTime.compare(not_before, started_at) in [:eq, :gt],
          do: changeset,
          else: add_error(changeset, :multipart_quiescence_not_before, "must not precede its start")

      _partial ->
        add_error(changeset, :multipart_quiescence_not_before, "must be paired with its start")
    end
  end
end
