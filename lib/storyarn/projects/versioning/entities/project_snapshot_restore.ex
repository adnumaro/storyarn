defmodule Storyarn.Projects.Versioning.ProjectSnapshotRestore do
  @moduledoc """
  Durable, generation-fenced state for an exact full-project snapshot restore.

  The archive and manifest fields are an immutable copy of the verified
  snapshot identity accepted at request time. Lifecycle changesets never cast
  those fields, so a queued operation cannot silently retarget another object
  set while it is retried.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Persistence.StorageReservationRecord, as: StorageReservation
  alias Storyarn.Projects.Persistence.UserRecord, as: User
  alias Storyarn.Projects.Persistence.WorkspaceRecord, as: Workspace
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.Versioning.ProjectSnapshot

  @statuses ~w(queued running retrying completed failed)
  @active_statuses ~w(queued running retrying)
  @phases ~w(queued preflight staging materializing verifying retrying completed failed)
  @running_phases ~w(preflight staging materializing verifying)
  @identity_fields [
    :workspace_id,
    :project_id,
    :project_snapshot_id,
    :requested_by_id,
    :snapshot_lifecycle_generation,
    :snapshot_accounting_generation,
    :archive_storage_key,
    :archive_size_bytes,
    :archive_checksum,
    :manifest_storage_key,
    :manifest_size_bytes,
    :manifest_checksum
  ]

  @type t :: %__MODULE__{
          id: integer() | nil,
          workspace_id: integer() | nil,
          workspace: Workspace.t() | NotLoaded.t() | nil,
          project_id: integer() | nil,
          project: Project.t() | NotLoaded.t() | nil,
          project_snapshot_id: integer() | nil,
          project_snapshot: ProjectSnapshot.t() | NotLoaded.t() | nil,
          requested_by_id: integer() | nil,
          requested_by: User.t() | NotLoaded.t() | nil,
          oban_job_id: integer() | nil,
          idempotency_key: Ecto.UUID.t() | nil,
          status: String.t(),
          phase: String.t(),
          generation: pos_integer(),
          attempt: non_neg_integer(),
          storage_reservation_id: integer() | nil,
          storage_reservation: StorageReservation.t() | NotLoaded.t() | nil,
          storage_reservation_generation: pos_integer() | nil,
          storage_reservation_lease_token: Ecto.UUID.t() | nil,
          snapshot_lifecycle_generation: pos_integer() | nil,
          snapshot_accounting_generation: pos_integer() | nil,
          archive_storage_key: String.t() | nil,
          archive_size_bytes: pos_integer() | nil,
          archive_checksum: String.t() | nil,
          manifest_storage_key: String.t() | nil,
          manifest_size_bytes: pos_integer() | nil,
          manifest_checksum: String.t() | nil,
          failure_code: String.t() | nil,
          failure_message: String.t() | nil,
          failure_details: map(),
          result: map(),
          result_digest: String.t() | nil,
          requested_at: DateTime.t() | nil,
          claimed_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          failed_at: DateTime.t() | nil,
          state_updated_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "project_snapshot_restores" do
    field :idempotency_key, Ecto.UUID
    field :status, :string, default: "queued"
    field :phase, :string, default: "queued"
    field :generation, :integer, default: 1
    field :attempt, :integer, default: 0
    field :oban_job_id, :integer

    field :storage_reservation_generation, :integer
    field :storage_reservation_lease_token, Ecto.UUID

    field :snapshot_lifecycle_generation, :integer
    field :snapshot_accounting_generation, :integer
    field :archive_storage_key, :string
    field :archive_size_bytes, :integer
    field :archive_checksum, :string
    field :manifest_storage_key, :string
    field :manifest_size_bytes, :integer
    field :manifest_checksum, :string

    field :failure_code, :string
    field :failure_message, :string
    field :failure_details, :map, default: %{}
    field :result, :map, default: %{}
    field :result_digest, :string

    field :requested_at, :utc_datetime
    field :claimed_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :failed_at, :utc_datetime
    field :state_updated_at, :utc_datetime

    belongs_to :workspace, Workspace
    belongs_to :project, Project
    belongs_to :project_snapshot, ProjectSnapshot
    belongs_to :requested_by, User
    belongs_to :storage_reservation, StorageReservation

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def active_statuses, do: @active_statuses
  def phases, do: @phases
  def running_phases, do: @running_phases

  @doc "Builds the initial queued operation from an already-authorized snapshot identity."
  @spec request_changeset(t(), map()) :: Ecto.Changeset.t()
  def request_changeset(restore, attrs) when is_map(attrs) do
    requested_at = get_attr(attrs, :requested_at, TimeHelpers.now())

    restore
    |> cast(attrs, [:idempotency_key])
    |> put_identity_fields(attrs)
    |> change(
      status: "queued",
      phase: "queued",
      generation: 1,
      attempt: 0,
      failure_code: nil,
      failure_message: nil,
      failure_details: %{},
      result: %{},
      result_digest: nil,
      requested_at: requested_at,
      claimed_at: nil,
      completed_at: nil,
      failed_at: nil,
      state_updated_at: requested_at
    )
    |> validate_required([:requested_by_id])
    |> validate_common()
  end

  @doc "Binds the unique Oban delivery created in the request transaction."
  @spec bind_job_changeset(t(), pos_integer()) :: Ecto.Changeset.t()
  def bind_job_changeset(restore, oban_job_id) do
    restore
    |> change(oban_job_id: oban_job_id)
    |> validate_required([:oban_job_id])
    |> validate_number(:oban_job_id, greater_than: 0)
    |> validate_common()
  end

  @doc "Binds the exact staging reservation identity owned by this operation."
  @spec bind_reservation_changeset(t(), map() | StorageReservation.t()) :: Ecto.Changeset.t()
  def bind_reservation_changeset(restore, %StorageReservation{} = reservation) do
    bind_reservation_changeset(restore, %{
      storage_reservation_id: reservation.id,
      storage_reservation_generation: reservation.generation,
      storage_reservation_lease_token: reservation.lease_token
    })
  end

  def bind_reservation_changeset(restore, attrs) when is_map(attrs) do
    restore
    |> change(
      storage_reservation_id: get_attr(attrs, :storage_reservation_id),
      storage_reservation_generation: get_attr(attrs, :storage_reservation_generation),
      storage_reservation_lease_token: get_attr(attrs, :storage_reservation_lease_token)
    )
    |> validate_required([
      :storage_reservation_id,
      :storage_reservation_generation,
      :storage_reservation_lease_token
    ])
    |> validate_common()
  end

  @doc "Claims a queued operation, or resumes a retry, without double-advancing its generation."
  @spec claim_changeset(t(), pos_integer() | map(), DateTime.t()) :: Ecto.Changeset.t()
  def claim_changeset(restore, attempt, now) when is_integer(attempt) do
    claim_changeset(restore, %{attempt: attempt, generation: claim_generation(restore)}, now)
  end

  def claim_changeset(restore, attrs, now) when is_map(attrs) do
    attempt = get_attr(attrs, :attempt)
    generation = get_attr(attrs, :generation)

    restore
    |> change(
      status: "running",
      phase: "preflight",
      generation: generation,
      attempt: attempt,
      claimed_at: restore.claimed_at || now,
      completed_at: nil,
      failed_at: nil,
      failure_code: nil,
      failure_message: nil,
      failure_details: %{},
      result: %{},
      result_digest: nil,
      state_updated_at: now
    )
    |> require_current_status(["queued", "retrying"])
    |> validate_required([:oban_job_id, :claimed_at])
    |> validate_number(:attempt, greater_than: restore.attempt)
    |> validate_claim_generation(restore)
    |> validate_common()
  end

  @doc "Moves a claimed operation through a non-terminal execution phase."
  @spec phase_changeset(t(), String.t(), DateTime.t()) :: Ecto.Changeset.t()
  def phase_changeset(restore, phase, now) do
    restore
    |> change(phase: phase, state_updated_at: now)
    |> require_current_status(["running"])
    |> validate_inclusion(:phase, @running_phases)
    |> validate_common()
  end

  @doc "Records a later delivery attempt without advancing the claimed generation."
  @spec resume_changeset(t(), pos_integer(), DateTime.t()) :: Ecto.Changeset.t()
  def resume_changeset(restore, attempt, now) do
    restore
    |> change(attempt: attempt, state_updated_at: now)
    |> require_current_status(["running"])
    |> validate_number(:attempt, greater_than: restore.attempt)
    |> validate_unchanged_generation(restore)
    |> validate_common()
  end

  @doc "Records a retryable failure while retaining the claimed generation."
  @spec retrying_changeset(t(), map(), DateTime.t()) :: Ecto.Changeset.t()
  def retrying_changeset(restore, attrs, now) when is_map(attrs) do
    restore
    |> change(
      status: "retrying",
      phase: "retrying",
      generation: get_attr(attrs, :generation, restore.generation),
      failure_code: get_attr(attrs, :failure_code),
      failure_message: get_attr(attrs, :failure_message),
      failure_details: get_attr(attrs, :failure_details, %{}),
      result: %{},
      result_digest: nil,
      completed_at: nil,
      failed_at: nil,
      state_updated_at: now
    )
    |> require_current_status(["running"])
    |> validate_required([:failure_code])
    |> validate_unchanged_generation(restore)
    |> validate_common()
  end

  @doc "Completes the exact claimed generation and records a replay-stable result digest."
  @spec complete_changeset(t(), map(), DateTime.t()) :: Ecto.Changeset.t()
  def complete_changeset(restore, result, now) when is_map(result) do
    result_digest = get_attr(result, :result_digest)
    persisted_result = Map.drop(result, [:result_digest, "result_digest"])

    restore
    |> change(
      status: "completed",
      phase: "completed",
      generation: restore.generation + 1,
      result: persisted_result,
      result_digest: result_digest,
      failure_code: nil,
      failure_message: nil,
      failure_details: %{},
      completed_at: now,
      failed_at: nil,
      state_updated_at: now
    )
    |> require_current_status(["running"])
    |> validate_required([:result_digest, :completed_at])
    |> validate_common()
  end

  @doc "Terminalizes a claimed or exhausted retry generation with a durable failure."
  @spec fail_changeset(t(), map(), DateTime.t()) :: Ecto.Changeset.t()
  def fail_changeset(restore, attrs, now) when is_map(attrs) do
    restore
    |> change(
      status: "failed",
      phase: "failed",
      generation: restore.generation + 1,
      failure_code: get_attr(attrs, :failure_code),
      failure_message: get_attr(attrs, :failure_message),
      failure_details: get_attr(attrs, :failure_details, %{}),
      result: %{},
      result_digest: nil,
      completed_at: nil,
      failed_at: now,
      state_updated_at: now
    )
    |> require_current_status(["running", "retrying"])
    |> validate_required([:failure_code, :failed_at])
    |> validate_common()
  end

  @doc false
  @spec abandoned_changeset(t(), map(), DateTime.t()) :: Ecto.Changeset.t()
  def abandoned_changeset(restore, attrs, now) when is_map(attrs) do
    restore
    |> change(
      status: "failed",
      phase: "failed",
      generation: restore.generation + 1,
      attempt: max(restore.attempt, 1),
      claimed_at: restore.claimed_at || now,
      failure_code: get_attr(attrs, :failure_code),
      failure_message: get_attr(attrs, :failure_message),
      failure_details: get_attr(attrs, :failure_details, %{}),
      result: %{},
      result_digest: nil,
      completed_at: nil,
      failed_at: now,
      state_updated_at: now
    )
    |> require_current_status(@active_statuses)
    |> validate_required([:failure_code, :claimed_at, :failed_at])
    |> validate_common()
  end

  defp put_identity_fields(changeset, attrs) do
    Enum.reduce(@identity_fields, changeset, fn field, acc ->
      put_change(acc, field, get_attr(attrs, field))
    end)
  end

  defp validate_common(changeset) do
    changeset
    |> validate_required([
      :workspace_id,
      :project_id,
      :project_snapshot_id,
      :idempotency_key,
      :status,
      :phase,
      :generation,
      :attempt,
      :snapshot_lifecycle_generation,
      :snapshot_accounting_generation,
      :archive_storage_key,
      :archive_size_bytes,
      :archive_checksum,
      :manifest_storage_key,
      :manifest_size_bytes,
      :manifest_checksum,
      :failure_details,
      :result,
      :requested_at,
      :state_updated_at
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:phase, @phases)
    |> validate_number(:generation, greater_than: 0)
    |> validate_number(:attempt, greater_than_or_equal_to: 0)
    |> validate_number(:snapshot_lifecycle_generation, greater_than: 0)
    |> validate_number(:snapshot_accounting_generation, greater_than: 0)
    |> validate_number(:archive_size_bytes, greater_than: 0)
    |> validate_number(:manifest_size_bytes, greater_than: 0)
    |> validate_length(:archive_storage_key, min: 1, max: 520)
    |> validate_length(:manifest_storage_key, min: 1, max: 520)
    |> validate_format(:archive_checksum, ~r/\A[0-9a-f]{64}\z/)
    |> validate_format(:manifest_checksum, ~r/\A[0-9a-f]{64}\z/)
    |> validate_length(:failure_code, min: 1, max: 100)
    |> validate_length(:failure_message, min: 1, max: 500)
    |> validate_format(:result_digest, ~r/\A[0-9a-f]{64}\z/)
    |> validate_reservation_identity()
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:project_snapshot_id)
    |> foreign_key_constraint(:requested_by_id)
    |> foreign_key_constraint(:oban_job_id)
    |> foreign_key_constraint(:storage_reservation_id)
    |> unique_constraint([:workspace_id, :idempotency_key],
      name: :project_snapshot_restores_workspace_idempotency_idx
    )
    |> unique_constraint(:project_id,
      name: :project_snapshot_restores_active_project_idx,
      message: "already has an active snapshot restore"
    )
    |> unique_constraint(:oban_job_id, name: :project_snapshot_restores_oban_job_idx)
    |> check_constraint(:status, name: :project_snapshot_restores_status_check)
    |> check_constraint(:phase, name: :project_snapshot_restores_phase_check)
    |> check_constraint(:archive_storage_key,
      name: :project_snapshot_restores_target_identity_check
    )
    |> check_constraint(:storage_reservation_id,
      name: :project_snapshot_restores_reservation_identity_check
    )
    |> check_constraint(:status, name: :project_snapshot_restores_payload_shape_check)
    |> check_constraint(:status, name: :project_snapshot_restores_lifecycle_shape_check)
  end

  defp validate_reservation_identity(changeset) do
    values =
      Enum.map(
        [
          :storage_reservation_id,
          :storage_reservation_generation,
          :storage_reservation_lease_token
        ],
        &get_field(changeset, &1)
      )

    if Enum.all?(values, &is_nil/1) or Enum.all?(values, &(not is_nil(&1))) do
      changeset
    else
      add_error(changeset, :storage_reservation_id, "must include the complete reservation identity")
    end
  end

  defp require_current_status(changeset, allowed_statuses) do
    current_status = changeset.data.status

    if current_status in allowed_statuses do
      changeset
    else
      add_error(changeset, :status, "cannot transition from #{current_status}")
    end
  end

  defp validate_claim_generation(changeset, restore) do
    expected = claim_generation(restore)

    if get_field(changeset, :generation) == expected do
      changeset
    else
      add_error(changeset, :generation, "must match the claimed lifecycle generation")
    end
  end

  defp validate_unchanged_generation(changeset, restore) do
    if get_field(changeset, :generation) == restore.generation do
      changeset
    else
      add_error(changeset, :generation, "must retain the claimed lifecycle generation")
    end
  end

  defp claim_generation(%__MODULE__{status: "queued", generation: generation}), do: generation + 1
  defp claim_generation(%__MODULE__{generation: generation}), do: generation

  defp get_attr(attrs, field, default \\ nil) do
    case Map.fetch(attrs, field) do
      {:ok, value} -> value
      :error -> Map.get(attrs, Atom.to_string(field), default)
    end
  end
end
