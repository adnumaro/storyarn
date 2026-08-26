defmodule Storyarn.Projects.Versioning.ProjectSnapshotReconciliationRepairAction do
  @moduledoc """
  Durable one-shot outcome for a generation-fenced reconciliation repair.

  The source finding remains immutable evidence, while this row records one
  terminal outcome per finding and repair contract. A recurring observation in
  a later inspection run produces a new finding and therefore a new action.
  `subject_fingerprint` snapshots the finding's complete evidence; it is not a
  stable logical-subject identifier across runs. Terminal rows cannot be
  replayed or rewritten.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Versioning.ProjectSnapshotReconciliationFinding

  @action_kinds ~w(
    mark_missing mark_corrupt cleanup_expired_build
    replay_cleanup report_only
  )
  @terminal_statuses ~w(repaired resolved manual failed)

  @type t :: %__MODULE__{}

  schema "project_snapshot_reconciliation_repair_actions" do
    field :contract_version, :integer, default: 1
    field :provider_namespace_fingerprint_snapshot, :string
    field :subject_fingerprint, :string
    field :action_kind, :string
    field :status, :string, default: "pending"
    field :result_code, :string
    field :attempt_count, :integer, default: 0
    field :finished_at, :utc_datetime

    belongs_to :source_finding, ProjectSnapshotReconciliationFinding

    timestamps(type: :utc_datetime)
  end

  @doc false
  def plan_changeset(action, attrs) do
    action
    |> cast(attrs, [
      :source_finding_id,
      :provider_namespace_fingerprint_snapshot,
      :subject_fingerprint,
      :action_kind
    ])
    |> put_change(:contract_version, 1)
    |> put_change(:status, "pending")
    |> put_change(:attempt_count, 0)
    |> validate_required([
      :source_finding_id,
      :contract_version,
      :provider_namespace_fingerprint_snapshot,
      :subject_fingerprint,
      :action_kind,
      :status,
      :attempt_count
    ])
    |> validate_format(:provider_namespace_fingerprint_snapshot, ~r/\A[0-9a-f]{64}\z/)
    |> validate_format(:subject_fingerprint, ~r/\A[0-9a-f]{64}\z/)
    |> validate_inclusion(:action_kind, @action_kinds)
    |> validate_inclusion(:status, ["pending"])
    |> validate_number(:attempt_count, equal_to: 0)
    |> foreign_key_constraint(:source_finding_id,
      name: :snapshot_reconciliation_repair_actions_finding_fkey
    )
    |> unique_constraint([:source_finding_id, :contract_version],
      name: :snapshot_reconciliation_repair_actions_finding_idx
    )
    |> state_constraint()
  end

  @doc false
  def attempt_changeset(%__MODULE__{} = action) do
    action
    |> change()
    |> validate_open_action(action)
    |> force_change(:attempt_count, action.attempt_count)
    |> optimistic_lock(:attempt_count, &(&1 + 1))
    |> state_constraint()
  end

  @doc false
  def outcome_changeset(%__MODULE__{} = action, attrs) do
    action
    |> cast(attrs, [:status, :result_code])
    |> put_change(:finished_at, TimeHelpers.now())
    |> validate_open_action(action)
    |> validate_recorded_attempt(action)
    |> optimistic_lock(:attempt_count, & &1)
    |> validate_required([:status, :result_code, :attempt_count, :finished_at])
    |> validate_inclusion(:status, @terminal_statuses)
    |> validate_number(:attempt_count, greater_than: 0)
    |> validate_length(:result_code, min: 1, max: 255)
    |> state_constraint()
  end

  defp validate_open_action(changeset, %__MODULE__{
         status: "pending",
         attempt_count: attempt_count,
         result_code: nil,
         finished_at: nil
       })
       when is_integer(attempt_count) and attempt_count >= 0, do: changeset

  defp validate_open_action(changeset, %__MODULE__{}),
    do: add_error(changeset, :status, "has already reached a terminal outcome")

  defp validate_recorded_attempt(changeset, %__MODULE__{attempt_count: attempt_count})
       when is_integer(attempt_count) and attempt_count > 0, do: changeset

  defp validate_recorded_attempt(changeset, %__MODULE__{}),
    do: add_error(changeset, :attempt_count, "must be recorded before an outcome")

  defp state_constraint(changeset) do
    check_constraint(changeset, :status, name: :snapshot_reconciliation_repair_actions_shape)
  end
end
