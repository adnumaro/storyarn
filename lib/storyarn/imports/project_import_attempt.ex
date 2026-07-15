defmodule Storyarn.Imports.ProjectImportAttempt do
  @moduledoc """
  Durable, privacy-safe state for a project import.

  Uploaded names and imported content are intentionally absent. The encrypted
  plan lives in private object storage and the Oban job contains only this
  record's numeric identifier.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Imports.PlanCleanupRequest
  alias Storyarn.Projects.Project

  @statuses ~w(ready queued running retrying completed failed expired)
  @active_statuses ~w(ready queued running retrying)
  @stages ~w(parsed queued materializing retrying completed failed expired)
  @formats ~w(yarn storyarn)
  @source_kinds ~w(file archive)
  @strategies ~w(skip overwrite rename)

  schema "project_import_attempts" do
    field :status, :string
    field :stage, :string
    field :format, :string
    field :source_kind, :string
    field :parser_version, :string
    field :conflict_strategy, :string, default: "rename"
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

    timestamps(type: :utc_datetime)
  end

  def active_statuses, do: @active_statuses
  def strategies, do: @strategies

  def ready_changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :status,
      :stage,
      :format,
      :source_kind,
      :parser_version,
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

  def completed_changeset(attempt, now, counts) do
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

  def expired_changeset(attempt, now) do
    attempt
    |> change(
      status: "expired",
      stage: "expired",
      completed_at: now,
      user_id: nil,
      idempotency_key: nil
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
    |> validate_length(:parser_version, max: 30)
    |> validate_length(:idempotency_key, is: 64)
    |> validate_length(:plan_storage_key, max: 255)
    |> validate_length(:error_code, max: 100)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:oban_job_id)
    |> foreign_key_constraint(:plan_cleanup_request_id)
    |> unique_constraint(:idempotency_key,
      name: :project_import_attempts_active_idempotency_unique,
      message: "already has an active import"
    )
    |> check_constraint(:status, name: :project_import_attempts_status_check)
    |> check_constraint(:stage, name: :project_import_attempts_stage_check)
    |> check_constraint(:format, name: :project_import_attempts_format_check)
    |> check_constraint(:source_kind, name: :project_import_attempts_source_kind_check)
    |> check_constraint(:conflict_strategy, name: :project_import_attempts_conflict_strategy_check)
    |> check_constraint(:status, name: :project_import_attempts_state_check)
    |> check_constraint(:status, name: :project_import_attempts_terminal_privacy_check)
  end
end
