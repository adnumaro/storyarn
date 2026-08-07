defmodule Storyarn.Versioning.ProjectSnapshotReconciliationFinding do
  @moduledoc """
  Immutable evidence produced by an observation-only reconciliation run.

  Findings are candidates for operator investigation. They are never deletion
  authority and intentionally contain no URLs, credentials, or mutable object
  ownership tokens.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Versioning.ProjectSnapshotReconciliationRun

  @categories ~w(
    ready_manifest_missing ready_manifest_corrupt
    ready_object_missing ready_object_corrupt
    ready_database_manifest_mismatch ready_inventory_mismatch
    ready_accounting_mismatch ready_verification_limit_exceeded
    failed_snapshot_finalization
    ambiguous_storage_object unsafe_snapshot_storage_key
    abandoned_temporary_object stale_reservation terminal_cleanup_failure
  )

  @type t :: %__MODULE__{}

  schema "project_snapshot_reconciliation_findings" do
    field :fingerprint, :string
    field :category, :string
    field :severity, :string
    field :workspace_id_snapshot, :integer
    field :project_id_snapshot, :integer
    field :project_snapshot_id_snapshot, :integer
    field :storage_reservation_id_snapshot, :integer
    field :lifecycle_generation, :integer
    field :reservation_generation, :integer
    field :object_prefix, :string
    field :storage_key, :string
    field :expected_size_bytes, :integer
    field :observed_size_bytes, :integer
    field :error_code, :string
    field :details, :map, default: %{}

    belongs_to :run, ProjectSnapshotReconciliationRun

    timestamps(updated_at: false, type: :utc_datetime)
  end

  @doc false
  def create_changeset(finding, attrs) do
    finding
    |> cast(attrs, [
      :run_id,
      :fingerprint,
      :category,
      :severity,
      :workspace_id_snapshot,
      :project_id_snapshot,
      :project_snapshot_id_snapshot,
      :storage_reservation_id_snapshot,
      :lifecycle_generation,
      :reservation_generation,
      :object_prefix,
      :storage_key,
      :expected_size_bytes,
      :observed_size_bytes,
      :error_code,
      :details
    ])
    |> validate_required([:run_id, :fingerprint, :category, :severity, :details])
    |> validate_format(:fingerprint, ~r/\A[0-9a-f]{64}\z/)
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:severity, ~w(warning critical))
    |> validate_length(:object_prefix, max: 500)
    |> validate_length(:storage_key, max: 2_048)
    |> validate_length(:error_code, max: 255)
    |> validate_safe_details()
    |> foreign_key_constraint(:run_id)
    |> unique_constraint([:run_id, :fingerprint],
      name: :project_snapshot_reconciliation_findings_run_fingerprint_idx
    )
    |> check_constraint(:category, name: :project_snapshot_reconciliation_findings_evidence)
  end

  defp validate_safe_details(changeset) do
    details = get_field(changeset, :details)

    if is_map(details) and map_size(details) <= 16 and
         Enum.all?(details, fn {key, value} -> safe_detail?(key, value) end) do
      changeset
    else
      add_error(changeset, :details, "contains unsafe reconciliation evidence")
    end
  end

  defp safe_detail?(key, value) when is_binary(key) and byte_size(key) <= 64 do
    String.valid?(key) and not unsafe_detail_key?(String.downcase(key)) and safe_detail_value?(value)
  end

  defp safe_detail?(_key, _value), do: false

  defp safe_detail_value?(value) when is_boolean(value) or is_integer(value) or is_nil(value), do: true

  defp safe_detail_value?(value) when is_binary(value) do
    byte_size(value) <= 1_024 and String.valid?(value) and not unsafe_detail_string?(value)
  end

  defp safe_detail_value?(_value), do: false

  defp unsafe_detail_key?(key) do
    key in ~w(url presigned_url source_key thumbnail_key credential secret token)
  end

  defp unsafe_detail_string?(value) do
    downcased = String.downcase(value)

    String.contains?(downcased, ["http://", "https://"]) or
      String.contains?(downcased, ["x-amz-", "x-goog-", "signature=", "credential=", "token="])
  end
end
