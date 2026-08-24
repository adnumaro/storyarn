defmodule Storyarn.Imports.ProjectImportAttempt do
  @moduledoc """
  Durable, privacy-safe state for a project import.

  Uploaded names and imported content are intentionally absent. The encrypted
  plan lives in private object storage and the Oban job contains only this
  record's numeric identifier.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Imports.PlanCleanupRequest
  alias Storyarn.Projects.Persistence.UserRecord, as: User
  alias Storyarn.Projects.Project
  alias Storyarn.Versioning.ProjectSnapshot

  @statuses ~w(ready queued running retrying completed failed expired)
  @active_statuses ~w(ready queued running retrying)
  @stages ~w(parsed awaiting_snapshot queued materializing retrying completed failed expired)
  @formats ~w(yarn storyarn)
  @source_kinds ~w(file archive)
  @strategies ~w(skip overwrite rename)
  @import_modes ~w(additive replace_project)

  schema "project_import_attempts" do
    field :status, :string
    field :stage, :string
    field :format, :string
    field :source_kind, :string
    field :parser_version, :string
    field :conflict_strategy, :string, default: "rename"
    field :import_mode, :string, default: "additive"
    field :replace_eligible, :boolean, default: false
    field :replacement_prepared_at, :utc_datetime
    field :snapshot_request_key, Ecto.UUID
    field :snapshot_reference_bound_at, :utc_datetime
    field :snapshot_lifecycle_generation, :integer
    field :snapshot_accounting_generation, :integer
    field :snapshot_capture_digest, :string
    field :snapshot_project_checksum, :string
    field :snapshot_archive_storage_key, :string
    field :snapshot_archive_size_bytes, :integer
    field :snapshot_archive_checksum, :string
    field :snapshot_manifest_storage_key, :string
    field :snapshot_manifest_size_bytes, :integer
    field :snapshot_manifest_checksum, :string
    field :idempotency_key, :string
    field :plan_storage_key, :string
    field :counts, :map, default: %{}
    field :warning_codes, {:array, :string}, default: []
    field :error_code, :string
    field :error_message, :string
    field :error_report, :map, default: %{}
    field :expires_at, :utc_datetime
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :oban_job_id, :integer

    belongs_to :project, Project
    belongs_to :user, User
    belongs_to :plan_cleanup_request, PlanCleanupRequest
    belongs_to :pre_import_snapshot, ProjectSnapshot

    timestamps(type: :utc_datetime)
  end

  def active_statuses, do: @active_statuses
  def strategies, do: @strategies
  def import_modes, do: @import_modes

  @doc """
  Whether the attempt may be operated on by the given member.

  Active attempts are private to the member who started them: project
  permission alone must not let one owner adopt, reconcile, enqueue or cancel
  another member's in-flight import by guessing its id. Terminal attempts have
  had `user_id` stripped by the terminal-privacy constraint and read as
  project-level records for anyone the project-level authorization admits.

  Terminality is decided by `status`, never by a nil `user_id`: the users FK
  nilifies on delete, so an active attempt with no owner is a legal row, and a
  security predicate must fail closed on it rather than open it to everyone.
  """
  @spec owned_or_ownerless?(%__MODULE__{}, pos_integer()) :: boolean()
  def owned_or_ownerless?(%__MODULE__{} = attempt, user_id) do
    attempt.user_id == user_id or attempt.status not in @active_statuses
  end

  def ready_changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :status,
      :stage,
      :format,
      :source_kind,
      :parser_version,
      :replace_eligible,
      :idempotency_key,
      :plan_storage_key,
      :counts,
      :warning_codes,
      :expires_at
    ])
    |> validate_required([
      :status,
      :stage,
      :format,
      :source_kind,
      :parser_version,
      :idempotency_key,
      :plan_storage_key,
      :plan_cleanup_request_id,
      :expires_at
    ])
    |> validate_common()
  end

  def import_mode_changeset(attempt, "additive") do
    attempt
    |> change(
      import_mode: "additive",
      replacement_prepared_at: nil,
      snapshot_request_key: nil,
      pre_import_snapshot_id: nil,
      snapshot_reference_bound_at: nil,
      snapshot_lifecycle_generation: nil,
      snapshot_accounting_generation: nil,
      snapshot_capture_digest: nil,
      snapshot_project_checksum: nil,
      snapshot_archive_storage_key: nil,
      snapshot_archive_size_bytes: nil,
      snapshot_archive_checksum: nil,
      snapshot_manifest_storage_key: nil,
      snapshot_manifest_size_bytes: nil,
      snapshot_manifest_checksum: nil
    )
    |> validate_common()
  end

  def import_mode_changeset(attempt, "replace_project") do
    attempt
    |> change(
      import_mode: "replace_project",
      replacement_prepared_at: nil,
      snapshot_request_key: attempt.snapshot_request_key || Ecto.UUID.generate()
    )
    |> validate_common()
  end

  def import_mode_changeset(attempt, _mode) do
    attempt
    |> change()
    |> add_error(:import_mode, "is invalid")
    |> validate_common()
  end

  def queued_changeset(attempt, strategy, job_id, expires_at) do
    attempt
    |> change(
      status: "queued",
      stage: "queued",
      conflict_strategy: strategy,
      oban_job_id: job_id,
      expires_at: expires_at,
      error_code: nil,
      error_message: nil,
      error_report: %{}
    )
    |> validate_common()
  end

  def awaiting_snapshot_changeset(attempt, strategy, job_id, expires_at) do
    attempt
    |> change(
      status: "queued",
      stage: "awaiting_snapshot",
      conflict_strategy: strategy,
      oban_job_id: job_id,
      pre_import_snapshot_id: nil,
      snapshot_reference_bound_at: nil,
      expires_at: expires_at,
      error_code: nil,
      error_message: nil,
      error_report: %{}
    )
    |> validate_common()
  end

  def snapshot_ready_changeset(attempt, snapshot) do
    attempt
    |> change(
      status: "queued",
      stage: "queued",
      snapshot_lifecycle_generation: snapshot.lifecycle_generation,
      snapshot_accounting_generation: snapshot.accounting_generation,
      snapshot_capture_digest: snapshot.capture_digest,
      snapshot_project_checksum: snapshot.project_checksum,
      snapshot_archive_storage_key: snapshot.archive_storage_key,
      snapshot_archive_size_bytes: snapshot.archive_size_bytes,
      snapshot_archive_checksum: snapshot.archive_checksum,
      snapshot_manifest_storage_key: snapshot.manifest_storage_key,
      snapshot_manifest_size_bytes: snapshot.manifest_size_bytes,
      snapshot_manifest_checksum: snapshot.manifest_checksum,
      error_code: nil,
      error_message: nil,
      error_report: %{}
    )
    |> validate_common()
  end

  def snapshot_waiting_changeset(attempt) do
    attempt
    |> change(
      status: "queued",
      stage: "awaiting_snapshot",
      error_code: nil,
      error_message: nil,
      error_report: %{}
    )
    |> validate_common()
  end

  def reviewed_changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:plan_storage_key, :plan_cleanup_request_id, :counts])
    |> validate_required([:plan_storage_key, :plan_cleanup_request_id])
    |> validate_common()
  end

  def conflict_strategy_changeset(attempt, strategy) do
    attempt
    |> change(conflict_strategy: strategy)
    |> validate_common()
  end

  def running_changeset(attempt, now) do
    attempt
    |> change(
      status: "running",
      stage: "materializing",
      started_at: attempt.started_at || now,
      completed_at: nil,
      error_code: nil,
      error_message: nil,
      error_report: %{}
    )
    |> validate_common()
  end

  def retrying_changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:status, :stage, :error_code, :error_message, :error_report, :started_at, :expires_at])
    |> validate_common()
  end

  def queued_retry_changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:error_code, :error_message, :error_report, :expires_at])
    |> put_change(:status, "queued")
    |> validate_common()
  end

  def completed_changeset(attempt, now, counts, opts \\ []) do
    attempt
    |> change(
      status: "completed",
      stage: "completed",
      completed_at: now,
      counts: counts,
      user_id: nil,
      idempotency_key: nil,
      error_code: nil,
      error_message: nil,
      error_report: %{}
    )
    |> force_change(:replacement_prepared_at, Keyword.get(opts, :replacement_prepared_at))
    |> validate_common()
  end

  def failed_changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:status, :stage, :error_code, :error_message, :error_report, :completed_at])
    |> put_change(:user_id, nil)
    |> put_change(:idempotency_key, nil)
    |> validate_required([:error_code, :completed_at])
    |> validate_common()
  end

  @doc """
  Terminalizes an attempt as `expired`.

  `error_code` separates the two things that reach this state. A preview that
  simply aged out carries no code and must not be reported as a failure; an
  attempt rejected for an unusable review carries the reason so the UI can say
  which one happened. `user_id` and `idempotency_key` are dropped like every
  other terminal transition, which is why resuming a terminal attempt can only
  ever be authorized by project, never by owner.
  """
  def expired_changeset(attempt, now, error_code \\ nil) do
    attempt
    |> change(
      status: "expired",
      stage: "expired",
      completed_at: now,
      user_id: nil,
      idempotency_key: nil,
      error_code: error_code,
      error_message: nil,
      error_report: %{}
    )
    |> validate_common()
  end

  defp validate_common(changeset) do
    changeset
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:stage, @stages)
    |> validate_inclusion(:format, @formats)
    |> validate_inclusion(:source_kind, @source_kinds)
    |> validate_inclusion(:conflict_strategy, @strategies)
    |> validate_inclusion(:import_mode, @import_modes)
    |> validate_length(:parser_version, max: 30)
    |> validate_length(:idempotency_key, is: 64)
    |> validate_length(:plan_storage_key, max: 255)
    |> validate_length(:snapshot_capture_digest, is: 64)
    |> validate_length(:snapshot_project_checksum, is: 64)
    |> validate_length(:snapshot_archive_storage_key, max: 520)
    |> validate_length(:snapshot_archive_checksum, is: 64)
    |> validate_length(:snapshot_manifest_storage_key, max: 520)
    |> validate_length(:snapshot_manifest_checksum, is: 64)
    |> validate_number(:snapshot_archive_size_bytes, greater_than: 0)
    |> validate_number(:snapshot_manifest_size_bytes, greater_than: 0)
    |> validate_length(:error_code, max: 100)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:oban_job_id)
    |> foreign_key_constraint(:plan_cleanup_request_id)
    |> foreign_key_constraint(:pre_import_snapshot_id)
    |> unique_constraint(:idempotency_key,
      name: :project_import_attempts_active_idempotency_unique,
      message: "already has an active import"
    )
    |> check_constraint(:status, name: :project_import_attempts_status_check)
    |> check_constraint(:stage, name: :project_import_attempts_stage_check)
    |> check_constraint(:format, name: :project_import_attempts_format_check)
    |> check_constraint(:source_kind, name: :project_import_attempts_source_kind_check)
    |> check_constraint(:conflict_strategy, name: :project_import_attempts_conflict_strategy_check)
    |> check_constraint(:import_mode, name: :project_import_attempts_import_mode_check)
    |> check_constraint(:replace_eligible, name: :project_import_attempts_replace_eligibility_check)
    |> check_constraint(:replacement_prepared_at,
      name: :project_import_attempts_replacement_fence_check
    )
    |> check_constraint(:pre_import_snapshot_id, name: :project_import_attempts_snapshot_identity_check)
    |> check_constraint(:pre_import_snapshot_id, name: :project_import_attempts_replace_snapshot_check)
    |> check_constraint(:pre_import_snapshot_id,
      name: :project_import_attempts_snapshot_reference_state_check
    )
    |> check_constraint(:status, name: :project_import_attempts_state_check)
    |> check_constraint(:status, name: :project_import_attempts_terminal_privacy_check)
  end
end
