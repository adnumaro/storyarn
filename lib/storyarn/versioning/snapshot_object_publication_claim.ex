defmodule Storyarn.Versioning.SnapshotObjectPublicationClaim do
  @moduledoc """
  Durable exclusive claim for one canonical snapshot object namespace.

  The claim serializes staging and publication across nodes. A namespace that
  reaches `poisoned` is never reclaimed; retries must allocate a new token.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(staging staged publishing published poisoned)
  @status_transitions %{
    "staging" => ~w(staging staged poisoned),
    "staged" => ~w(staged publishing poisoned),
    "publishing" => ~w(publishing published poisoned),
    "published" => ~w(published),
    "poisoned" => ~w(poisoned)
  }

  @inventory_fields [
    {:format_version, [:format_version]},
    {:mode, [:mode]},
    {:object_prefix, [:object_prefix]},
    {:manifest_storage_key, [:manifest_storage_key]},
    {:manifest_size_bytes, [:manifest_size_bytes]},
    {:manifest_checksum, [:manifest_checksum]},
    {:project_storage_key, [:project_storage_key]},
    {:project_size_bytes, [:project_size_bytes]},
    {:project_checksum, [:project_checksum]},
    {:total_size_bytes, [:total_size_bytes]},
    {:accounted_size_bytes, [:accounted_size_bytes]},
    {:asset_blob_size_bytes, [:asset_blob_size_bytes]},
    {:accounting_version, [:accounting_version]},
    {:object_count, [:object_count]},
    {:asset_count, [:asset_count]},
    {:blob_count, [:blob_count]}
  ]

  @primary_key {:object_prefix, :string, autogenerate: false}
  schema "snapshot_object_publication_claims" do
    field :claim_token, Ecto.UUID
    field :inventory_digest, :string
    field :storage_reservation_id_snapshot, :integer
    field :storage_reservation_lease_token, Ecto.UUID
    field :status, :string
    field :lease_expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(
        object_prefix,
        inventory_digest,
        claim_token,
        lease_expires_at,
        reservation_id,
        reservation_lease_token
      ) do
    %__MODULE__{}
    |> change(%{
      object_prefix: object_prefix,
      inventory_digest: inventory_digest,
      claim_token: claim_token,
      storage_reservation_id_snapshot: reservation_id,
      storage_reservation_lease_token: reservation_lease_token,
      status: "staging",
      lease_expires_at: lease_expires_at
    })
    |> validate_required([
      :object_prefix,
      :inventory_digest,
      :claim_token,
      :storage_reservation_id_snapshot,
      :storage_reservation_lease_token,
      :status,
      :lease_expires_at
    ])
    |> validate_number(:storage_reservation_id_snapshot, greater_than: 0)
    |> validate_inclusion(:status, @statuses)
    |> validate_format(
      :object_prefix,
      ~r<\Aprojects/[1-9]\d*/snapshots/object-sets/v1/ready/[A-Za-z0-9_-]{16}\z>
    )
    |> validate_format(:inventory_digest, ~r/\A[0-9a-f]{64}\z/)
    |> unique_constraint(:object_prefix, name: :snapshot_object_publication_claims_pkey)
    |> unique_constraint(:claim_token)
    |> unique_constraint(:storage_reservation_id_snapshot,
      name: :snapshot_object_publication_claims_reservation_idx
    )
    |> foreign_key_constraint(:storage_reservation_id_snapshot,
      name: :snapshot_object_publication_claims_reservation_fkey
    )
    |> check_constraint(:object_prefix, name: :snapshot_object_publication_claims_identity)
  end

  @doc false
  def status_changeset(%__MODULE__{} = claim, status, lease_expires_at \\ nil) do
    claim
    |> change(status: status, lease_expires_at: lease_expires_at)
    |> validate_inclusion(:status, @statuses)
    |> validate_status_transition(claim.status)
    |> check_constraint(:status, name: :snapshot_object_publication_claims_identity)
  end

  @doc "Returns the canonical digest binding a publication claim to its final snapshot row."
  @spec inventory_digest(map()) :: String.t()
  def inventory_digest(source) when is_map(source) do
    @inventory_fields
    |> Enum.map(fn {field, aliases} -> {field, first_value(source, aliases)} end)
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp validate_status_transition(changeset, current_status) do
    next_status = get_field(changeset, :status)

    if next_status in Map.get(@status_transitions, current_status, []),
      do: changeset,
      else: add_error(changeset, :status, "cannot move backwards or leave a terminal state")
  end

  defp first_value(source, [field | fields]) do
    case fetch_value(source, field) do
      {:ok, value} -> value
      :error -> first_value(source, fields)
    end
  end

  defp first_value(_source, []), do: nil

  defp fetch_value(source, field) do
    case Map.fetch(source, field) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(source, Atom.to_string(field))
    end
  end
end
