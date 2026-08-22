defmodule Storyarn.Flows.Persistence.StorageCleanupRequestRecord do
  @moduledoc false

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

  @doc false
  def flow_restore_changeset(request, storage_keys) do
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
