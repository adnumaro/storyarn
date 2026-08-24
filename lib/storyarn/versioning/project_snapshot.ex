defmodule Storyarn.Versioning.ProjectSnapshot do
  @moduledoc """
  Schema for project-level snapshots.

  Every project snapshot row owns one canonical v2 ZIP archive plus its
  independently checksummed manifest.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Projects.Persistence.UserRecord, as: User
  alias Storyarn.Projects.Project
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.ProjectSnapshotCapture
  alias Storyarn.Versioning.SnapshotArchiveStorage

  @allocated_object_set_fields [
    :project_id,
    :version_number,
    :format_version,
    :object_prefix,
    :archive_storage_key,
    :archive_size_bytes,
    :project_size_bytes,
    :project_checksum,
    :manifest_storage_key,
    :manifest_size_bytes,
    :manifest_checksum,
    :total_size_bytes,
    :object_count,
    :asset_count,
    :blob_count,
    :restore_contract_version
  ]
  @ready_object_set_fields [
    :project_id,
    :version_number,
    :title,
    :description,
    :archive_storage_key,
    :archive_size_bytes,
    :archive_checksum,
    :project_size_bytes,
    :project_checksum,
    :entity_counts,
    :created_by_id,
    :is_auto,
    :format_version,
    :object_prefix,
    :manifest_storage_key,
    :manifest_size_bytes,
    :manifest_checksum,
    :total_size_bytes,
    :object_count,
    :asset_count,
    :blob_count,
    :mode,
    :lifecycle_state,
    :integrity_state,
    :accounted_size_bytes,
    :asset_blob_size_bytes,
    :accounting_version,
    :restore_contract_version
  ]
  @origins ~w(user daily pre_restore post_restore)
  @same_generation_transitions %{
    "pending" => ~w(pending building failed cancelled),
    "building" => ~w(building verifying failed cancelled),
    "verifying" => ~w(verifying ready failed cancelled),
    "ready" => ~w(ready),
    "failed" => ~w(failed),
    "cancelled" => ~w(cancelled),
    "deleting" => ~w(deleting)
  }
  @reconciliation_integrity_sources ~w(verified missing corrupt)
  @reconciliation_integrity_targets ~w(missing corrupt)

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_id: integer(),
          version_number: integer(),
          title: String.t() | nil,
          description: String.t() | nil,
          archive_storage_key: String.t() | nil,
          archive_size_bytes: integer() | nil,
          archive_checksum: String.t() | nil,
          project_size_bytes: integer(),
          project_checksum: String.t() | nil,
          format_version: integer() | nil,
          object_prefix: String.t() | nil,
          manifest_storage_key: String.t() | nil,
          manifest_size_bytes: integer() | nil,
          manifest_checksum: String.t() | nil,
          total_size_bytes: integer() | nil,
          object_count: integer() | nil,
          asset_count: integer() | nil,
          blob_count: integer() | nil,
          mode: String.t() | nil,
          lifecycle_state: String.t() | nil,
          integrity_state: String.t() | nil,
          accounted_size_bytes: integer() | nil,
          asset_blob_size_bytes: integer() | nil,
          accounting_version: integer() | nil,
          accounting_generation: integer() | nil,
          accounting_measured_at: DateTime.t() | nil,
          origin: String.t(),
          expires_at: DateTime.t() | nil,
          lifecycle_generation: pos_integer(),
          deletion_requested_at: DateTime.t() | nil,
          idempotency_key: String.t(),
          capture_boundary: Ecto.UUID.t(),
          capture_digest: String.t(),
          restore_contract_version: integer() | nil,
          captured_at: DateTime.t(),
          progress_phase: String.t(),
          progress_bytes: integer(),
          progress_total_bytes: integer(),
          failure_code: String.t() | nil,
          failure_message: String.t() | nil,
          storage_reservation_id: integer() | nil,
          build_job_id: integer() | nil,
          build_attempt: non_neg_integer(),
          publication_claim_token: Ecto.UUID.t() | nil,
          building_started_at: DateTime.t() | nil,
          verifying_started_at: DateTime.t() | nil,
          ready_at: DateTime.t() | nil,
          failed_at: DateTime.t() | nil,
          cancel_requested_at: DateTime.t() | nil,
          cancelled_at: DateTime.t() | nil,
          state_updated_at: DateTime.t(),
          entity_counts: map(),
          created_by_id: integer() | nil,
          created_by: User.t() | NotLoaded.t() | nil,
          is_auto: boolean(),
          project: Project.t() | NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "project_snapshots" do
    field :version_number, :integer
    field :title, :string
    field :description, :string
    field :archive_storage_key, :string
    field :archive_size_bytes, :integer
    field :archive_checksum, :string
    field :project_size_bytes, :integer
    field :project_checksum, :string
    field :format_version, :integer, default: 2
    field :object_prefix, :string
    field :manifest_storage_key, :string
    field :manifest_size_bytes, :integer
    field :manifest_checksum, :string
    field :total_size_bytes, :integer
    field :object_count, :integer
    field :asset_count, :integer
    field :blob_count, :integer
    field :mode, :string
    field :lifecycle_state, :string
    field :integrity_state, :string
    field :accounted_size_bytes, :integer
    field :asset_blob_size_bytes, :integer
    field :accounting_version, :integer
    field :accounting_generation, :integer
    field :accounting_measured_at, :utc_datetime
    field :origin, :string, default: "user"
    field :expires_at, :utc_datetime
    field :lifecycle_generation, :integer, default: 1
    field :deletion_requested_at, :utc_datetime
    field :idempotency_key, :string
    field :capture_boundary, Ecto.UUID
    field :capture_digest, :string
    field :restore_contract_version, :integer
    field :captured_at, :utc_datetime
    field :progress_phase, :string
    field :progress_bytes, :integer
    field :progress_total_bytes, :integer
    field :failure_code, :string
    field :failure_message, :string
    field :build_job_id, :integer
    field :build_attempt, :integer, default: 0
    field :publication_claim_token, Ecto.UUID
    field :building_started_at, :utc_datetime
    field :verifying_started_at, :utc_datetime
    field :ready_at, :utc_datetime
    field :failed_at, :utc_datetime
    field :cancel_requested_at, :utc_datetime
    field :cancelled_at, :utc_datetime
    field :state_updated_at, :utc_datetime, read_after_writes: true
    field :entity_counts, :map, default: %{}
    field :is_auto, :boolean, default: false

    belongs_to :project, Project
    belongs_to :created_by, User
    belongs_to :storage_reservation, StorageReservation
    has_one :capture, ProjectSnapshotCapture

    timestamps(updated_at: false, type: :utc_datetime)
  end

  @doc """
  Changeset for persisting canonical snapshot storage.

  The canonical archive and manifest sidecar retain independent digests.
  Readers require both physical objects and never infer readiness from one
  object alone.
  """
  def object_set_changeset(snapshot, attrs) do
    attrs = normalize_object_set_accounting_attrs(attrs)

    derive_accounted_size? = not has_attr?(attrs, :accounted_size_bytes)
    derive_asset_blob_size? = not has_attr?(attrs, :asset_blob_size_bytes)

    snapshot
    |> cast(attrs, [
      :project_id,
      :version_number,
      :title,
      :description,
      :archive_storage_key,
      :archive_size_bytes,
      :archive_checksum,
      :project_size_bytes,
      :project_checksum,
      :entity_counts,
      :created_by_id,
      :is_auto,
      :format_version,
      :object_prefix,
      :manifest_storage_key,
      :manifest_size_bytes,
      :manifest_checksum,
      :total_size_bytes,
      :object_count,
      :asset_count,
      :blob_count,
      :mode,
      :lifecycle_state,
      :integrity_state,
      :accounted_size_bytes,
      :asset_blob_size_bytes,
      :accounting_version,
      :accounting_measured_at,
      :origin,
      :expires_at,
      :lifecycle_generation,
      :idempotency_key,
      :capture_boundary,
      :capture_digest,
      :restore_contract_version,
      :captured_at,
      :progress_phase,
      :progress_bytes,
      :progress_total_bytes,
      :building_started_at,
      :verifying_started_at,
      :ready_at,
      :state_updated_at
    ])
    |> advance_accounting_generation(snapshot)
    |> derive_accounting_sizes(derive_accounted_size?, derive_asset_blob_size?)
    |> validate_required([
      :project_id,
      :version_number,
      :project_size_bytes,
      :project_checksum,
      :format_version,
      :object_prefix,
      :manifest_storage_key,
      :manifest_size_bytes,
      :manifest_checksum,
      :total_size_bytes,
      :object_count,
      :asset_count,
      :blob_count,
      :mode,
      :lifecycle_state,
      :integrity_state,
      :accounted_size_bytes,
      :asset_blob_size_bytes,
      :accounting_version,
      :accounting_generation,
      :accounting_measured_at,
      :origin,
      :lifecycle_generation,
      :idempotency_key,
      :capture_boundary,
      :capture_digest,
      :captured_at,
      :progress_phase,
      :progress_bytes,
      :progress_total_bytes,
      :building_started_at,
      :verifying_started_at,
      :ready_at,
      :state_updated_at
    ])
    |> validate_format_required_fields(:ready)
    |> validate_inclusion(:format_version, [2])
    |> validate_inclusion(:mode, ["full"])
    |> validate_inclusion(:lifecycle_state, ["ready"])
    |> validate_inclusion(:integrity_state, ["verified"])
    |> validate_inclusion(:accounting_version, [1])
    |> validate_inclusion(:origin, @origins)
    |> validate_inclusion(:progress_phase, ["complete"])
    |> validate_number(:accounting_generation, greater_than: 0)
    |> validate_number(:lifecycle_generation, greater_than: 0)
    |> validate_length(:title, max: 255)
    |> validate_length(:description, max: 500)
    |> validate_length(:object_prefix, max: 500)
    |> validate_length(:archive_storage_key, max: 520)
    |> validate_length(:manifest_storage_key, max: 520)
    |> validate_number(:archive_size_bytes, greater_than: 0)
    |> validate_number(:project_size_bytes, greater_than: 0)
    |> validate_number(:manifest_size_bytes, greater_than: 0)
    |> validate_number(:total_size_bytes, greater_than: 0)
    |> validate_number(:object_count, greater_than_or_equal_to: 2)
    |> validate_number(:asset_count, greater_than_or_equal_to: 0)
    |> validate_number(:blob_count, greater_than_or_equal_to: 0)
    |> validate_number(:accounted_size_bytes, greater_than: 0)
    |> validate_number(:asset_blob_size_bytes, greater_than_or_equal_to: 0)
    |> validate_format(:project_checksum, ~r/\A[0-9a-f]{64}\z/)
    |> validate_format(:archive_checksum, ~r/\A[0-9a-f]{64}\z/)
    |> validate_format(:manifest_checksum, ~r/\A[0-9a-f]{64}\z/)
    |> validate_format(:capture_digest, ~r/\A[0-9a-f]{64}\z/)
    |> validate_inclusion(:restore_contract_version, [1])
    |> validate_ready_object_keys()
    |> validate_object_set_transition(snapshot)
    |> validate_object_counts()
    |> validate_total_size()
    |> validate_accounting_breakdown()
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by_id)
    |> check_constraint(:format_version, name: :project_snapshots_object_format_version)
    |> check_constraint(:format_version, name: :project_snapshots_archive_format)
    |> check_constraint(:object_count, name: :project_snapshots_object_counts)
    |> check_constraint(:blob_count, name: :project_snapshots_full_asset_blobs)
    |> check_constraint(:total_size_bytes, name: :project_snapshots_object_sizes)
    |> check_constraint(:project_checksum, name: :project_snapshots_project_checksum_format)
    |> check_constraint(:manifest_checksum, name: :project_snapshots_manifest_checksum_format)
    |> check_constraint(:mode, name: :project_snapshots_mode)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_lifecycle_state)
    |> check_constraint(:integrity_state, name: :project_snapshots_integrity_state)
    |> check_constraint(:integrity_state, name: :project_snapshots_mode_integrity)
    |> check_constraint(:mode, name: :project_snapshots_accounting_identity)
    |> check_constraint(:object_prefix, name: :project_snapshots_object_target)
    |> check_constraint(:accounting_version, name: :project_snapshots_accounting_measurement)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_ready_accounting)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_ready_object_set)
    |> check_constraint(:accounted_size_bytes, name: :project_snapshots_full_ready_accounting)
    |> check_constraint(:capture_digest, name: :project_snapshots_capture_digest_format)
    |> restore_contract_constraints()
    |> check_constraint(:progress_phase, name: :project_snapshots_build_progress)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_build_failure)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_build_timestamps)
    |> lifecycle_constraints()
    |> unique_constraint(:object_prefix)
    |> unique_constraint(:archive_storage_key)
    |> unique_constraint(:manifest_storage_key)
    |> unique_constraint([:project_id, :version_number],
      name: :project_snapshots_project_id_version_number_index
    )
  end

  @doc """
  Creates the lightweight lifecycle row owned by an archive build job.

  Capture bytes and exact accounting are intentionally absent here. The worker
  materializes them from one repeatable-read project snapshot before it may
  claim the row for provider I/O.
  """
  def queued_archive_changeset(snapshot, attrs) do
    attrs =
      attrs
      |> put_default(:format_version, 2)
      |> put_default(:lifecycle_state, "pending")
      |> put_default(:integrity_state, "unknown")
      |> put_default(:progress_phase, "pending")
      |> put_default(:progress_bytes, 0)
      |> put_default(:progress_total_bytes, 0)
      |> put_default(:build_attempt, 0)
      |> put_default(:state_updated_at, TimeHelpers.now())
      |> put_default(:origin, "user")
      |> put_default(:lifecycle_generation, 1)
      |> put_pending_object_keys()

    snapshot
    |> cast(attrs, [
      :project_id,
      :version_number,
      :title,
      :description,
      :created_by_id,
      :is_auto,
      :format_version,
      :mode,
      :object_prefix,
      :archive_storage_key,
      :manifest_storage_key,
      :idempotency_key,
      :capture_boundary,
      :lifecycle_state,
      :integrity_state,
      :progress_phase,
      :progress_bytes,
      :progress_total_bytes,
      :build_attempt,
      :state_updated_at,
      :origin,
      :expires_at,
      :lifecycle_generation
    ])
    |> validate_required([
      :project_id,
      :version_number,
      :created_by_id,
      :format_version,
      :mode,
      :object_prefix,
      :archive_storage_key,
      :manifest_storage_key,
      :idempotency_key,
      :capture_boundary,
      :lifecycle_state,
      :integrity_state,
      :progress_phase,
      :progress_bytes,
      :progress_total_bytes,
      :build_attempt,
      :state_updated_at,
      :origin,
      :lifecycle_generation
    ])
    |> validate_inclusion(:format_version, [2])
    |> validate_inclusion(:mode, ["full"])
    |> validate_inclusion(:lifecycle_state, ["pending"])
    |> validate_inclusion(:integrity_state, ["unknown"])
    |> validate_inclusion(:progress_phase, ["pending"])
    |> validate_inclusion(:origin, @origins)
    |> validate_length(:title, max: 255)
    |> validate_length(:description, max: 500)
    |> validate_length(:object_prefix, max: 500)
    |> validate_length(:archive_storage_key, max: 520)
    |> validate_length(:manifest_storage_key, max: 520)
    |> validate_number(:progress_bytes, equal_to: 0)
    |> validate_number(:progress_total_bytes, equal_to: 0)
    |> validate_number(:build_attempt, equal_to: 0)
    |> validate_number(:lifecycle_generation, equal_to: 1)
    |> validate_ready_object_keys()
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by_id)
    |> check_constraint(:format_version, name: :project_snapshots_object_format_version)
    |> check_constraint(:format_version, name: :project_snapshots_archive_format)
    |> check_constraint(:mode, name: :project_snapshots_mode)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_lifecycle_state)
    |> check_constraint(:integrity_state, name: :project_snapshots_integrity_state)
    |> check_constraint(:integrity_state, name: :project_snapshots_mode_integrity)
    |> check_constraint(:mode, name: :project_snapshots_accounting_identity)
    |> check_constraint(:object_prefix, name: :project_snapshots_object_target)
    |> check_constraint(:capture_digest, name: :project_snapshots_capture_digest_format)
    |> check_constraint(:progress_phase, name: :project_snapshots_build_progress)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_build_failure)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_build_timestamps)
    |> lifecycle_constraints()
    |> unique_constraint(:object_prefix)
    |> unique_constraint(:archive_storage_key)
    |> unique_constraint(:manifest_storage_key)
    |> unique_constraint([:project_id, :idempotency_key],
      name: :project_snapshots_project_id_idempotency_idx
    )
    |> unique_constraint(:capture_boundary)
    |> unique_constraint([:project_id, :version_number],
      name: :project_snapshots_project_id_version_number_index
    )
  end

  @doc """
  Creates the durable lifecycle row that an asynchronous snapshot build owns.

  The final object namespace and object keys are allocated up front, but the
  row remains non-ready and unaccounted until a verified manifest is published
  and `object_set_changeset/2` atomically finalizes it.
  """
  def pending_object_set_changeset(snapshot, attrs) do
    attrs =
      attrs
      |> put_default(:format_version, 2)
      |> put_default(:lifecycle_state, "pending")
      |> put_default(:integrity_state, "unknown")
      |> put_default(:progress_phase, "pending")
      |> put_default(:progress_bytes, 0)
      |> put_default(:build_attempt, 0)
      |> put_default(:captured_at, TimeHelpers.now())
      |> put_default(:state_updated_at, TimeHelpers.now())
      |> put_default(:origin, "user")
      |> put_default(:lifecycle_generation, 1)
      |> put_pending_object_keys()

    snapshot
    |> cast(attrs, [
      :project_id,
      :version_number,
      :title,
      :description,
      :archive_storage_key,
      :archive_size_bytes,
      :archive_checksum,
      :project_size_bytes,
      :project_checksum,
      :entity_counts,
      :created_by_id,
      :is_auto,
      :format_version,
      :object_prefix,
      :manifest_storage_key,
      :manifest_size_bytes,
      :manifest_checksum,
      :total_size_bytes,
      :object_count,
      :asset_count,
      :blob_count,
      :mode,
      :lifecycle_state,
      :integrity_state,
      :idempotency_key,
      :capture_boundary,
      :capture_digest,
      :restore_contract_version,
      :captured_at,
      :progress_phase,
      :progress_bytes,
      :progress_total_bytes,
      :build_attempt,
      :state_updated_at,
      :origin,
      :expires_at,
      :lifecycle_generation
    ])
    |> validate_required([
      :project_id,
      :version_number,
      :project_size_bytes,
      :project_checksum,
      :format_version,
      :object_prefix,
      :manifest_storage_key,
      :manifest_size_bytes,
      :manifest_checksum,
      :total_size_bytes,
      :object_count,
      :asset_count,
      :blob_count,
      :mode,
      :lifecycle_state,
      :integrity_state,
      :idempotency_key,
      :capture_boundary,
      :capture_digest,
      :captured_at,
      :progress_phase,
      :progress_bytes,
      :progress_total_bytes,
      :build_attempt,
      :state_updated_at,
      :origin,
      :lifecycle_generation
    ])
    |> validate_format_required_fields(:pending)
    |> validate_inclusion(:format_version, [2])
    |> validate_inclusion(:mode, ["full"])
    |> validate_inclusion(:lifecycle_state, ["pending"])
    |> validate_inclusion(:integrity_state, ["unknown"])
    |> validate_inclusion(:progress_phase, ["pending"])
    |> validate_inclusion(:origin, @origins)
    |> validate_length(:title, max: 255)
    |> validate_length(:description, max: 500)
    |> validate_length(:object_prefix, max: 500)
    |> validate_length(:archive_storage_key, max: 520)
    |> validate_length(:manifest_storage_key, max: 520)
    |> validate_number(:archive_size_bytes, greater_than: 0)
    |> validate_number(:project_size_bytes, greater_than: 0)
    |> validate_number(:manifest_size_bytes, greater_than: 0)
    |> validate_number(:total_size_bytes, greater_than: 0)
    |> validate_number(:object_count, greater_than_or_equal_to: 2)
    |> validate_number(:asset_count, greater_than_or_equal_to: 0)
    |> validate_number(:blob_count, greater_than_or_equal_to: 0)
    |> validate_number(:progress_bytes, equal_to: 0)
    |> validate_progress_total()
    |> validate_number(:build_attempt, equal_to: 0)
    |> validate_number(:lifecycle_generation, equal_to: 1)
    |> validate_format(:project_checksum, ~r/\A[0-9a-f]{64}\z/)
    |> validate_format(:archive_checksum, ~r/\A[0-9a-f]{64}\z/)
    |> validate_format(:manifest_checksum, ~r/\A[0-9a-f]{64}\z/)
    |> validate_format(:capture_digest, ~r/\A[0-9a-f]{64}\z/)
    |> validate_inclusion(:restore_contract_version, [1])
    |> validate_ready_object_keys()
    |> validate_object_counts()
    |> validate_total_size()
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by_id)
    |> check_constraint(:format_version, name: :project_snapshots_object_format_version)
    |> check_constraint(:format_version, name: :project_snapshots_archive_format)
    |> check_constraint(:mode, name: :project_snapshots_mode)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_lifecycle_state)
    |> check_constraint(:integrity_state, name: :project_snapshots_integrity_state)
    |> check_constraint(:integrity_state, name: :project_snapshots_mode_integrity)
    |> check_constraint(:mode, name: :project_snapshots_accounting_identity)
    |> check_constraint(:object_prefix, name: :project_snapshots_object_target)
    |> check_constraint(:accounting_version, name: :project_snapshots_accounting_measurement)
    |> check_constraint(:capture_digest, name: :project_snapshots_capture_digest_format)
    |> restore_contract_constraints()
    |> check_constraint(:progress_phase, name: :project_snapshots_build_progress)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_build_failure)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_build_timestamps)
    |> lifecycle_constraints()
    |> unique_constraint(:object_prefix)
    |> unique_constraint(:archive_storage_key)
    |> unique_constraint(:manifest_storage_key)
    |> unique_constraint([:project_id, :idempotency_key],
      name: :project_snapshots_project_id_idempotency_idx
    )
    |> unique_constraint(:capture_boundary)
    |> unique_constraint([:project_id, :version_number],
      name: :project_snapshots_project_id_version_number_index
    )
  end

  @doc """
  Changeset for updating title and description on an existing snapshot.
  """
  def update_changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:title, :description])
    |> validate_length(:title, max: 255)
    |> validate_length(:description, max: 500)
  end

  @doc false
  def reconciliation_integrity_changeset(%__MODULE__{} = snapshot, target) do
    snapshot
    |> change()
    |> validate_reconciliation_integrity_source(snapshot)
    |> put_reconciliation_integrity_target(target)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_lifecycle_state)
    |> check_constraint(:integrity_state, name: :project_snapshots_integrity_state)
    |> check_constraint(:integrity_state, name: :project_snapshots_mode_integrity)
    |> lifecycle_constraints()
  end

  @doc false
  def build_state_changeset(snapshot, attrs) do
    snapshot
    |> build_state_changeset_base(attrs)
    |> validate_same_generation_transition(snapshot)
    |> ensure_monotonic_state_time(snapshot)
  end

  defp build_state_changeset_base(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :object_prefix,
      :archive_storage_key,
      :manifest_storage_key,
      :lifecycle_state,
      :integrity_state,
      :progress_phase,
      :progress_bytes,
      :progress_total_bytes,
      :failure_code,
      :failure_message,
      :storage_reservation_id,
      :build_job_id,
      :build_attempt,
      :publication_claim_token,
      :building_started_at,
      :verifying_started_at,
      :ready_at,
      :failed_at,
      :cancel_requested_at,
      :cancelled_at,
      :state_updated_at
    ])
    |> validate_required([
      :object_prefix,
      :manifest_storage_key,
      :lifecycle_state,
      :integrity_state,
      :progress_phase,
      :progress_bytes,
      :progress_total_bytes,
      :build_attempt,
      :state_updated_at
    ])
    |> validate_format_required_fields(:state)
    |> validate_inclusion(:lifecycle_state, [
      "pending",
      "building",
      "verifying",
      "ready",
      "failed",
      "cancelled",
      "deleting"
    ])
    |> validate_inclusion(:integrity_state, [
      "unknown",
      "verified",
      "missing",
      "corrupt",
      "incomplete"
    ])
    |> validate_inclusion(:progress_phase, [
      "pending",
      "copying",
      "verifying",
      "finalizing",
      "retrying",
      "complete",
      "failed",
      "cancelled"
    ])
    |> validate_number(:progress_bytes, greater_than_or_equal_to: 0)
    |> validate_progress_total()
    |> validate_number(:build_attempt, greater_than_or_equal_to: 0)
    |> validate_progress_bounds()
    |> validate_ready_object_keys()
    |> foreign_key_constraint(:storage_reservation_id)
    |> check_constraint(:progress_phase, name: :project_snapshots_build_progress)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_build_failure)
    |> check_constraint(:lifecycle_state, name: :project_snapshots_build_timestamps)
    |> unique_constraint(:object_prefix)
    |> unique_constraint(:archive_storage_key)
    |> unique_constraint(:manifest_storage_key)
    |> lifecycle_constraints()
  end

  @doc false
  def retry_state_changeset(%__MODULE__{} = snapshot, attrs) do
    snapshot
    |> build_state_changeset_base(attrs)
    |> validate_retry_origin(snapshot)
    |> advance_lifecycle_generation(snapshot)
    |> validate_generation_transition(snapshot, "pending")
    |> ensure_monotonic_state_time(snapshot)
  end

  @doc false
  def cancel_request_changeset(%__MODULE__{} = snapshot, requested_at) do
    snapshot
    |> change()
    |> put_change(:cancel_requested_at, requested_at)
    |> put_change(:state_updated_at, requested_at)
    |> advance_lifecycle_generation(snapshot)
    |> validate_generation_transition(snapshot, snapshot.lifecycle_state)
    |> lifecycle_constraints()
  end

  @doc false
  def deletion_changeset(%__MODULE__{} = snapshot, requested_at) do
    snapshot
    |> change()
    |> put_change(:lifecycle_state, "deleting")
    |> put_change(:failure_code, nil)
    |> put_change(:failure_message, nil)
    |> put_change(:failed_at, nil)
    |> put_change(:deletion_requested_at, requested_at)
    |> put_change(:state_updated_at, requested_at)
    |> advance_lifecycle_generation(snapshot)
    |> validate_generation_transition(snapshot, "deleting")
    |> lifecycle_constraints()
  end

  defp normalize_object_set_accounting_attrs(attrs) do
    attrs
    |> put_default(:mode, "full")
    |> put_default(:lifecycle_state, "ready")
    |> put_default(:integrity_state, "verified")
    |> put_default(:accounting_version, 1)
    |> put_accounting_measured_at()
  end

  defp advance_accounting_generation(changeset, %__MODULE__{accounting_generation: generation})
       when is_integer(generation) and generation > 0 do
    changeset
    |> optimistic_lock(:accounting_generation, &(&1 + 1))
    |> force_change(:accounting_generation, generation + 1)
  end

  defp advance_accounting_generation(changeset, %__MODULE__{}), do: put_change(changeset, :accounting_generation, 1)

  defp advance_lifecycle_generation(changeset, %__MODULE__{lifecycle_generation: generation})
       when is_integer(generation) and generation > 0 do
    changeset
    |> optimistic_lock(:lifecycle_generation, &(&1 + 1))
    |> force_change(:lifecycle_generation, generation + 1)
  end

  defp advance_lifecycle_generation(changeset, _snapshot) do
    add_error(changeset, :lifecycle_generation, "is invalid")
  end

  defp validate_same_generation_transition(changeset, %__MODULE__{lifecycle_state: current}) do
    next = get_field(changeset, :lifecycle_state)

    if next in Map.get(@same_generation_transitions, current, []),
      do: changeset,
      else: add_error(changeset, :lifecycle_state, "cannot regress or skip lifecycle states")
  end

  defp validate_retry_origin(changeset, %__MODULE__{lifecycle_state: state})
       when state in ["building", "verifying", "failed"], do: changeset

  defp validate_retry_origin(changeset, %__MODULE__{}) do
    add_error(changeset, :lifecycle_state, "cannot retry from the current lifecycle state")
  end

  defp validate_generation_transition(changeset, %__MODULE__{lifecycle_generation: generation}, next_state) do
    if get_field(changeset, :lifecycle_generation) == generation + 1 and
         get_field(changeset, :lifecycle_state) == next_state,
       do: changeset,
       else: add_error(changeset, :lifecycle_generation, "did not advance exactly once")
  end

  defp ensure_monotonic_state_time(changeset, %__MODULE__{state_updated_at: %DateTime{} = current}) do
    case get_field(changeset, :state_updated_at) do
      %DateTime{} = next ->
        if DateTime.compare(next, current) in [:eq, :gt],
          do: changeset,
          else: put_change(changeset, :state_updated_at, current)

      _invalid ->
        changeset
    end
  end

  defp ensure_monotonic_state_time(changeset, _snapshot), do: changeset

  defp lifecycle_constraints(changeset) do
    changeset
    |> check_constraint(:origin, name: :project_snapshots_origin_retention)
    |> check_constraint(:lifecycle_generation, name: :project_snapshots_lifecycle_generation)
  end

  defp restore_contract_constraints(changeset) do
    changeset
    |> check_constraint(:restore_contract_version,
      name: :project_snapshots_restore_contract_version
    )
    |> check_constraint(:restore_contract_version,
      name: :project_snapshots_restore_contract_capture
    )
  end

  defp validate_reconciliation_integrity_source(changeset, snapshot) do
    changeset
    |> validate_reconciliation_source_field(:mode, snapshot.mode == "full")
    |> validate_reconciliation_source_field(:lifecycle_state, snapshot.lifecycle_state == "ready")
    |> validate_reconciliation_source_field(
      :integrity_state,
      snapshot.integrity_state in @reconciliation_integrity_sources
    )
  end

  defp validate_reconciliation_source_field(changeset, _field, true), do: changeset

  defp validate_reconciliation_source_field(changeset, field, false) do
    add_error(changeset, field, "is not eligible for reconciliation repair")
  end

  defp put_reconciliation_integrity_target(changeset, target) when target in @reconciliation_integrity_targets do
    put_change(changeset, :integrity_state, target)
  end

  defp put_reconciliation_integrity_target(changeset, _target) do
    add_error(changeset, :integrity_state, "is not a reconciliation repair target")
  end

  defp put_default(attrs, field, value) do
    if has_attr?(attrs, field), do: attrs, else: Map.put(attrs, field, value)
  end

  defp put_accounting_measured_at(attrs) do
    if has_attr?(attrs, :accounting_measured_at),
      do: attrs,
      else: Map.put(attrs, :accounting_measured_at, TimeHelpers.now())
  end

  defp put_pending_object_keys(attrs) do
    case {attr_value(attrs, :format_version), attr_value(attrs, :object_prefix)} do
      {2, prefix} when is_binary(prefix) ->
        attrs
        |> put_default(:archive_storage_key, SnapshotArchiveStorage.archive_key(prefix))
        |> put_default(:manifest_storage_key, SnapshotArchiveStorage.manifest_key(prefix))

      _prefix ->
        attrs
    end
  end

  defp has_attr?(attrs, field) do
    Map.has_key?(attrs, field) or Map.has_key?(attrs, to_string(field))
  end

  defp attr_value(attrs, field), do: Map.get(attrs, field, Map.get(attrs, to_string(field)))

  defp validate_format_required_fields(changeset, state) do
    required =
      cond do
        state == :ready -> [:archive_storage_key, :archive_size_bytes, :archive_checksum]
        is_nil(get_field(changeset, :capture_digest)) -> [:archive_storage_key]
        true -> [:archive_storage_key, :archive_size_bytes]
      end

    changeset
    |> validate_required(required)
    |> validate_nil_archive_checksum(state)
  end

  defp validate_nil_archive_checksum(changeset, :pending) do
    if is_nil(get_field(changeset, :archive_checksum)),
      do: changeset,
      else: add_error(changeset, :archive_checksum, "must be assigned only after archive verification")
  end

  defp validate_nil_archive_checksum(changeset, _state), do: changeset

  defp validate_progress_total(changeset) do
    if is_nil(get_field(changeset, :capture_digest)),
      do: validate_number(changeset, :progress_total_bytes, equal_to: 0),
      else: validate_number(changeset, :progress_total_bytes, greater_than: 0)
  end

  defp derive_accounting_sizes(changeset, derive_accounted_size?, derive_asset_blob_size?) do
    changeset
    |> maybe_derive_accounted_size(derive_accounted_size?)
    |> maybe_derive_asset_blob_size(derive_asset_blob_size?)
  end

  defp maybe_derive_accounted_size(changeset, true) do
    case get_field(changeset, :total_size_bytes) do
      total_size when is_integer(total_size) -> put_change(changeset, :accounted_size_bytes, total_size)
      _other -> changeset
    end
  end

  defp maybe_derive_accounted_size(changeset, false), do: changeset

  defp maybe_derive_asset_blob_size(changeset, true), do: changeset

  defp maybe_derive_asset_blob_size(changeset, false), do: changeset

  defp validate_object_counts(changeset) do
    format_version = get_field(changeset, :format_version)
    object_count = get_field(changeset, :object_count)
    asset_count = get_field(changeset, :asset_count)
    blob_count = get_field(changeset, :blob_count)

    if Enum.all?([object_count, asset_count, blob_count], &is_integer/1) do
      validate_complete_object_counts(
        changeset,
        format_version,
        get_field(changeset, :mode),
        object_count,
        asset_count,
        blob_count
      )
    else
      changeset
    end
  end

  defp validate_complete_object_counts(changeset, format_version, mode, object_count, asset_count, blob_count) do
    error =
      physical_object_count_error(format_version, object_count, blob_count) ||
        blob_asset_count_error(asset_count, blob_count) ||
        cataloged_blob_count_error(format_version, mode, asset_count, blob_count)

    case error do
      {field, message} -> add_error(changeset, field, message)
      nil -> changeset
    end
  end

  defp physical_object_count_error(2, object_count, _blob_count) when object_count != 2,
    do: {:object_count, "must equal the archive and manifest objects"}

  defp physical_object_count_error(_format_version, _object_count, _blob_count), do: nil

  defp blob_asset_count_error(asset_count, blob_count) when blob_count > asset_count,
    do: {:blob_count, "cannot exceed asset count"}

  defp blob_asset_count_error(_asset_count, _blob_count), do: nil

  defp cataloged_blob_count_error(format_version, "full", asset_count, 0) when asset_count > 0,
    do: {:blob_count, cataloged_blob_count_message(format_version)}

  defp cataloged_blob_count_error(_format_version, _mode, _asset_count, _blob_count), do: nil

  defp cataloged_blob_count_message(_format_version),
    do: "must include at least one logical blob when assets are cataloged"

  defp validate_total_size(changeset) do
    manifest_size = get_field(changeset, :manifest_size_bytes)
    total_size = get_field(changeset, :total_size_bytes)

    if is_integer(manifest_size) and is_integer(total_size) and total_size < manifest_size,
      do: add_error(changeset, :total_size_bytes, "must be at least the manifest size"),
      else: changeset
  end

  defp validate_progress_bounds(changeset) do
    progress_bytes = get_field(changeset, :progress_bytes)
    progress_total_bytes = get_field(changeset, :progress_total_bytes)

    if is_integer(progress_bytes) and is_integer(progress_total_bytes) and
         progress_bytes > progress_total_bytes,
       do: add_error(changeset, :progress_bytes, "cannot exceed total progress bytes"),
       else: changeset
  end

  defp validate_accounting_breakdown(changeset) do
    format_version = get_field(changeset, :format_version)
    total_size = get_field(changeset, :total_size_bytes)
    project_size = get_field(changeset, :project_size_bytes)
    manifest_size = get_field(changeset, :manifest_size_bytes)
    accounted_size = get_field(changeset, :accounted_size_bytes)
    asset_blob_size = get_field(changeset, :asset_blob_size_bytes)

    changeset
    |> validate_accounted_total_size(total_size, accounted_size)
    |> validate_format_accounting_breakdown(
      format_version,
      total_size,
      project_size,
      manifest_size,
      asset_blob_size,
      get_field(changeset, :archive_size_bytes)
    )
  end

  defp validate_accounted_total_size(changeset, total_size, accounted_size)
       when is_integer(total_size) and is_integer(accounted_size) and accounted_size != total_size,
       do: add_error(changeset, :accounted_size_bytes, "must equal the total snapshot size")

  defp validate_accounted_total_size(changeset, _total_size, _accounted_size), do: changeset

  defp validate_format_accounting_breakdown(
         changeset,
         2,
         total_size,
         _project_size,
         manifest_size,
         _asset_blob_size,
         archive_size
       ) do
    if Enum.all?([total_size, archive_size, manifest_size], &is_integer/1) and
         total_size != archive_size + manifest_size do
      add_error(changeset, :total_size_bytes, "must equal archive and manifest physical bytes")
    else
      changeset
    end
  end

  defp validate_format_accounting_breakdown(
         changeset,
         _format_version,
         _total_size,
         _project_size,
         _manifest_size,
         _asset_blob_size,
         _archive_size
       ), do: changeset

  defp validate_ready_object_keys(changeset) do
    project_id = get_field(changeset, :project_id)
    prefix = get_field(changeset, :object_prefix)
    archive_storage_key = get_field(changeset, :archive_storage_key)
    manifest_storage_key = get_field(changeset, :manifest_storage_key)

    changeset
    |> validate_canonical_prefix(SnapshotArchiveStorage.ready_prefix_for_project?(project_id, prefix))
    |> validate_storage_key(
      :archive_storage_key,
      archive_storage_key,
      prefix,
      "snapshot.zip",
      "must identify snapshot.zip in the archive namespace"
    )
    |> validate_storage_key(
      :manifest_storage_key,
      manifest_storage_key,
      prefix,
      "manifest.json",
      "must identify manifest.json in the archive namespace"
    )
  end

  defp validate_canonical_prefix(changeset, true), do: changeset

  defp validate_canonical_prefix(changeset, false) do
    add_error(changeset, :object_prefix, "must be a canonical ready namespace for the project")
  end

  defp validate_storage_key(changeset, field, key, prefix, filename, message) do
    if is_binary(prefix) and key == prefix <> "/" <> filename,
      do: changeset,
      else: add_error(changeset, field, message)
  end

  defp validate_object_set_transition(changeset, snapshot) do
    fields =
      if is_integer(snapshot.accounting_generation),
        do: @ready_object_set_fields,
        else: @allocated_object_set_fields

    validate_immutable_fields(changeset, snapshot, fields)
  end

  defp validate_immutable_fields(changeset, %__MODULE__{id: id} = snapshot, fields) when is_integer(id) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      if get_field(changeset, field) == Map.fetch!(snapshot, field),
        do: changeset,
        else: add_error(changeset, field, "cannot change after the snapshot target is allocated")
    end)
  end

  defp validate_immutable_fields(changeset, %__MODULE__{}, _fields), do: changeset
end
