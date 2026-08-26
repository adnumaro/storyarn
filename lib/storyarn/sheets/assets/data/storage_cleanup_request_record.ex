defmodule Storyarn.Sheets.Assets.Data.StorageCleanupRequestRecord do
  @moduledoc "Assets-owned consumer-local SQL projection used by Sheet asset writes and storage accounting without importing another context's schema."

  use Ecto.Schema

  import Ecto.Changeset

  schema "storage_cleanup_requests" do
    field :storage_keys, {:array, :string}, default: []
    field :owner_kind, :string, default: "storage_compensation"
    field :owner_token, Ecto.UUID
    field :provider_namespace_fingerprint, :string
    field :multipart_quiescence_started_at, :utc_datetime
    field :multipart_quiescence_not_before, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  # Fresh inserts only: forcing owner_kind on a loaded row would downgrade its
  # ownership while leaving the owner_token in place.
  @doc false
  def sheet_restore_changeset(%__MODULE__{id: nil} = request, storage_keys) do
    request
    |> cast(%{storage_keys: storage_keys}, [:storage_keys])
    |> put_change(:owner_kind, "storage_compensation")
    |> validate_required([:storage_keys, :owner_kind])
    |> validate_length(:storage_keys, min: 1)
    |> check_constraint(:storage_keys, name: :storage_cleanup_requests_keys_not_empty)
    |> check_constraint(:owner_kind, name: :storage_cleanup_requests_owner)
    |> check_constraint(:provider_namespace_fingerprint,
      name: :storage_cleanup_requests_provider_namespace
    )
  end
end
