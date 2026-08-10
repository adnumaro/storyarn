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
    field :cleanup_intent_id_snapshot, :integer
    field :lifecycle_generation, :integer
    field :accounting_generation, :integer
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
      :cleanup_intent_id_snapshot,
      :lifecycle_generation,
      :accounting_generation,
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
    |> validate_positive_evidence_ids()
    |> validate_repair_evidence()
    |> validate_non_negative_evidence_sizes()
    |> validate_length(:object_prefix, max: 500)
    |> validate_length(:storage_key, count: :bytes, max: 4_096)
    |> validate_safe_storage_key()
    |> validate_length(:error_code, max: 255)
    |> validate_safe_details()
    |> foreign_key_constraint(:run_id)
    |> unique_constraint([:run_id, :fingerprint],
      name: :project_snapshot_reconciliation_findings_run_fingerprint_idx
    )
    |> check_constraint(:category, name: :project_snapshot_reconciliation_findings_evidence)
    |> check_constraint(:accounting_generation,
      name: :project_snapshot_reconciliation_findings_repair_evidence
    )
  end

  defp validate_positive_evidence_ids(changeset) do
    Enum.reduce(
      [
        :workspace_id_snapshot,
        :project_id_snapshot,
        :project_snapshot_id_snapshot,
        :storage_reservation_id_snapshot,
        :cleanup_intent_id_snapshot,
        :lifecycle_generation,
        :accounting_generation,
        :reservation_generation
      ],
      changeset,
      &validate_number(&2, &1, greater_than: 0)
    )
  end

  defp validate_non_negative_evidence_sizes(changeset) do
    Enum.reduce(
      [:expected_size_bytes, :observed_size_bytes],
      changeset,
      &validate_number(&2, &1, greater_than_or_equal_to: 0)
    )
  end

  defp validate_repair_evidence(changeset) do
    case get_field(changeset, :category) do
      category
      when category in [
             "ready_manifest_missing",
             "ready_manifest_corrupt",
             "ready_object_missing",
             "ready_object_corrupt"
           ] ->
        validate_required(changeset, [:accounting_generation])

      "terminal_cleanup_failure" ->
        validate_required(changeset, [:cleanup_intent_id_snapshot])

      _category ->
        changeset
    end
  end

  @doc false
  def safe_storage_key_evidence?("base64url:" <> encoded) when encoded != "" do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, decoded} -> Base.url_encode64(decoded, padding: false) == encoded
      :error -> false
    end
  end

  def safe_storage_key_evidence?(value) when is_binary(value) do
    String.valid?(value) and not String.contains?(value, <<0>>) and not unsafe_evidence_string?(value)
  end

  def safe_storage_key_evidence?(_value), do: false

  defp validate_safe_storage_key(changeset) do
    case get_field(changeset, :storage_key) do
      nil ->
        changeset

      storage_key ->
        if safe_storage_key_evidence?(storage_key),
          do: changeset,
          else: add_error(changeset, :storage_key, "contains unsafe reconciliation evidence")
    end
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
    byte_size(value) <= 1_024 and String.valid?(value) and not unsafe_evidence_string?(value)
  end

  defp safe_detail_value?(_value), do: false

  defp unsafe_detail_key?(key) do
    key in ~w(url presigned_url source_key thumbnail_key credential secret token)
  end

  defp unsafe_evidence_string?(value) do
    downcased = String.downcase(value)

    String.contains?(downcased, ["http://", "https://"]) or
      String.contains?(downcased, ["x-amz-", "x-goog-", "signature=", "credential=", "token="])
  end
end
