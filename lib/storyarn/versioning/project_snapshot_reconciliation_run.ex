defmodule Storyarn.Versioning.ProjectSnapshotReconciliationRun do
  @moduledoc """
  Durable cursor for one observation-only snapshot reconciliation pass.

  A run may write only its own progress and findings. It never authorizes a
  lifecycle, quota, or storage mutation.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending running completed failed)
  @phases ~w(ready_snapshots stale_reservations publication_claims cleanup_intents provider_objects completed)

  @type t :: %__MODULE__{}

  schema "project_snapshot_reconciliation_runs" do
    field :contract_version, :integer, default: 1
    field :provider_namespace_fingerprint, :string
    field :mode, :string, default: "dry_run"
    field :status, :string, default: "pending"
    field :phase, :string, default: "ready_snapshots"
    field :snapshot_high_watermark, :integer, default: 0
    field :snapshot_after_id, :integer, default: 0
    field :reservation_high_watermark, :integer, default: 0
    field :reservation_after_id, :integer, default: 0
    field :claim_sequence_high_watermark, :integer, default: 0
    field :claim_after_sequence, :integer, default: 0
    field :cleanup_intent_high_watermark, :integer, default: 0
    field :cleanup_intent_after_id, :integer, default: 0
    field :active_snapshot_id, :integer
    field :active_snapshot_generation, :integer
    field :active_snapshot_accounting_generation, :integer
    field :active_object_index, :integer, default: 0
    field :active_inventory_cursor, :string
    field :active_inventory_digest, :string
    field :active_inventory_last_key, :string
    field :active_inventory_object_count, :integer, default: 0
    field :active_inventory_bytes, :integer, default: 0
    field :provider_cursor, :string
    field :provider_last_key, :string
    field :provider_scan_completed, :boolean, default: false
    field :cursor_generation, :integer, default: 1
    field :max_objects_per_step, :integer
    field :max_bytes_per_step, :integer
    field :max_findings, :integer
    field :provider_page_size, :integer
    field :max_provider_objects, :integer
    field :max_provider_bytes, :integer
    field :inspected_snapshot_count, :integer, default: 0
    field :inspected_object_count, :integer, default: 0
    field :inspected_bytes, :integer, default: 0
    field :provider_object_count, :integer, default: 0
    field :provider_bytes, :integer, default: 0
    field :finding_count, :integer, default: 0
    field :multipart_inventory_state, :string, default: "unsupported"
    field :physical_inventory_complete, :boolean, default: false
    field :last_error_code, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(run, attrs) do
    run
    |> cast(attrs, [
      :provider_namespace_fingerprint,
      :snapshot_high_watermark,
      :reservation_high_watermark,
      :claim_sequence_high_watermark,
      :cleanup_intent_high_watermark,
      :max_objects_per_step,
      :max_bytes_per_step,
      :max_findings,
      :provider_page_size,
      :max_provider_objects,
      :max_provider_bytes
    ])
    |> put_change(:contract_version, 1)
    |> put_change(:mode, "dry_run")
    |> put_change(:status, "pending")
    |> put_change(:phase, "ready_snapshots")
    |> put_change(:provider_scan_completed, false)
    |> put_change(:multipart_inventory_state, "unsupported")
    |> put_change(:physical_inventory_complete, false)
    |> validate_required([
      :provider_namespace_fingerprint,
      :mode,
      :status,
      :phase,
      :snapshot_high_watermark,
      :reservation_high_watermark,
      :claim_sequence_high_watermark,
      :cleanup_intent_high_watermark,
      :max_objects_per_step,
      :max_bytes_per_step,
      :max_findings,
      :provider_page_size,
      :max_provider_objects,
      :max_provider_bytes,
      :provider_scan_completed
    ])
    |> validate_format(:provider_namespace_fingerprint, ~r/\A[0-9a-f]{64}\z/)
    |> validate_number(:snapshot_high_watermark, greater_than_or_equal_to: 0)
    |> validate_number(:reservation_high_watermark, greater_than_or_equal_to: 0)
    |> validate_number(:claim_sequence_high_watermark, greater_than_or_equal_to: 0)
    |> validate_number(:cleanup_intent_high_watermark, greater_than_or_equal_to: 0)
    |> validate_number(:max_objects_per_step, greater_than: 0, less_than_or_equal_to: 1_000)
    |> validate_number(:max_bytes_per_step,
      greater_than_or_equal_to: 128 * 1024 * 1024,
      less_than_or_equal_to: 1024 * 1024 * 1024
    )
    |> validate_number(:max_findings, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_number(:provider_page_size, greater_than: 0, less_than_or_equal_to: 1_000)
    |> validate_number(:max_provider_objects, greater_than: 0, less_than_or_equal_to: 10_000_000)
    |> validate_number(:max_provider_bytes,
      greater_than: 0,
      less_than_or_equal_to: 1024 * 1024 * 1024 * 1024 * 1024
    )
    |> unique_constraint(:provider_namespace_fingerprint,
      name: :project_snapshot_reconciliation_runs_one_active_namespace
    )
    |> state_constraints()
  end

  @doc false
  def progress_changeset(run, attrs) do
    run
    |> cast(attrs, [
      :status,
      :phase,
      :snapshot_after_id,
      :reservation_after_id,
      :claim_after_sequence,
      :cleanup_intent_after_id,
      :active_snapshot_id,
      :active_snapshot_generation,
      :active_snapshot_accounting_generation,
      :active_object_index,
      :active_inventory_cursor,
      :active_inventory_digest,
      :active_inventory_last_key,
      :active_inventory_object_count,
      :active_inventory_bytes,
      :provider_cursor,
      :provider_last_key,
      :provider_scan_completed,
      :cursor_generation,
      :inspected_snapshot_count,
      :inspected_object_count,
      :inspected_bytes,
      :provider_object_count,
      :provider_bytes,
      :finding_count,
      :last_error_code,
      :started_at,
      :finished_at
    ])
    |> validate_required([
      :status,
      :phase,
      :snapshot_after_id,
      :reservation_after_id,
      :claim_after_sequence,
      :cleanup_intent_after_id,
      :active_object_index,
      :active_inventory_object_count,
      :active_inventory_bytes,
      :cursor_generation,
      :inspected_snapshot_count,
      :inspected_object_count,
      :inspected_bytes,
      :provider_object_count,
      :provider_bytes,
      :provider_scan_completed,
      :finding_count
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:phase, @phases)
    |> state_constraints()
  end

  defp state_constraints(changeset) do
    check_constraint(changeset, :status, name: :project_snapshot_reconciliation_runs_state)
  end
end
