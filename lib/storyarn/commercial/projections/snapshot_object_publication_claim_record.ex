defmodule Storyarn.Commercial.Billing.Persistence.SnapshotObjectPublicationClaimRecord do
  @moduledoc """
  Billing-owned projection of the publication fence for snapshot objects.

  Commercial reads this proof before committing or releasing capacity. Projects
  remains the sole writer of publication claims.
  """

  use Ecto.Schema

  @inventory_fields [
    {:format_version, [:format_version]},
    {:mode, [:mode]},
    {:object_prefix, [:object_prefix]},
    {:archive_storage_key, [:archive_storage_key]},
    {:archive_size_bytes, [:archive_size_bytes]},
    {:manifest_storage_key, [:manifest_storage_key]},
    {:manifest_size_bytes, [:manifest_size_bytes]},
    {:manifest_checksum, [:manifest_checksum]},
    {:project_size_bytes, [:project_size_bytes]},
    {:project_checksum, [:project_checksum]},
    {:total_size_bytes, [:total_size_bytes]},
    {:accounted_size_bytes, [:accounted_size_bytes]},
    {:asset_blob_size_bytes, [:asset_blob_size_bytes]},
    {:accounting_version, [:accounting_version]},
    {:object_count, [:object_count]},
    {:asset_count, [:asset_count]},
    {:blob_count, [:blob_count]},
    {:capture_digest, [:capture_digest]}
  ]

  @primary_key {:object_prefix, :string, autogenerate: false}
  schema "snapshot_object_publication_claims" do
    field :inventory_digest, :string
    field :storage_reservation_id_snapshot, :integer
    field :storage_reservation_lease_token, Ecto.UUID
    field :status, :string
  end

  @doc "Returns the canonical digest binding a claim to its final snapshot projection."
  @spec inventory_digest(map()) :: String.t()
  def inventory_digest(source) when is_map(source) do
    case first_value(source, [:format_version]) do
      2 ->
        @inventory_fields
        |> Enum.map(fn {field, aliases} -> {field, first_value(source, aliases)} end)
        |> :erlang.term_to_binary([:deterministic])
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      format_version ->
        raise ArgumentError, "unsupported snapshot claim format: #{inspect(format_version)}"
    end
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
