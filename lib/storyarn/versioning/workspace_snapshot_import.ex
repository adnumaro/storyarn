defmodule Storyarn.Versioning.WorkspaceSnapshotImport do
  @moduledoc """
  Durable state for importing a standalone project snapshot into a workspace.

  Archive identity and reserved storage are fixed when the request is accepted.
  Lifecycle changesets never cast those fields, so retries cannot retarget a
  different archive or silently change the capacity admitted synchronously.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Persistence.UserRecord, as: User
  alias Storyarn.Projects.Persistence.WorkspaceRecord, as: Workspace
  alias Storyarn.Projects.Project

  @statuses ~w(uploading queued running retrying completed failed)
  @active_statuses ~w(uploading queued running retrying)
  @stages ~w(uploading queued verifying materializing retrying completed failed)
  @running_stages ~w(verifying materializing)
  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  @type t :: %__MODULE__{
          id: integer() | nil,
          workspace_id: integer() | nil,
          workspace: Workspace.t() | NotLoaded.t() | nil,
          user_id: integer() | nil,
          user: User.t() | NotLoaded.t() | nil,
          project_id: integer() | nil,
          project: Project.t() | NotLoaded.t() | nil,
          oban_job_id: integer() | nil,
          original_filename: String.t() | nil,
          project_name: String.t() | nil,
          archive_storage_key: String.t() | nil,
          archive_size_bytes: pos_integer() | nil,
          archive_checksum: String.t() | nil,
          manifest_checksum: String.t() | nil,
          project_checksum: String.t() | nil,
          reserved_bytes: non_neg_integer(),
          staging_storage_keys: [String.t()],
          reserved_project_id: integer() | nil,
          materialization_storage_keys: [String.t()],
          status: String.t(),
          stage: String.t(),
          progress_bytes: non_neg_integer(),
          progress_total_bytes: non_neg_integer(),
          attempt: non_neg_integer(),
          max_attempts: pos_integer(),
          failure_code: String.t() | nil,
          failure_details: map(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "workspace_snapshot_imports" do
    field :original_filename, :string
    field :project_name, :string
    field :archive_storage_key, :string
    field :archive_size_bytes, :integer
    field :archive_checksum, :string
    field :manifest_checksum, :string
    field :project_checksum, :string
    field :reserved_bytes, :integer, default: 0
    field :staging_storage_keys, {:array, :string}, default: []
    field :reserved_project_id, :integer
    field :materialization_storage_keys, {:array, :string}, default: []

    field :status, :string, default: "queued"
    field :stage, :string, default: "queued"
    field :progress_bytes, :integer, default: 0
    field :progress_total_bytes, :integer, default: 0
    field :attempt, :integer, default: 0
    field :max_attempts, :integer, default: 3
    field :failure_code, :string
    field :failure_details, :map, default: %{}
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :oban_job_id, :integer

    belongs_to :workspace, Workspace
    belongs_to :user, User
    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def active_statuses, do: @active_statuses
  def stages, do: @stages

  @doc "Owns a direct-upload key before any snapshot payload is trusted."
  def upload_changeset(import, attrs) when is_map(attrs) do
    import
    |> cast(attrs, [
      :workspace_id,
      :user_id,
      :original_filename,
      :project_name,
      :archive_storage_key,
      :archive_size_bytes,
      :staging_storage_keys,
      :progress_total_bytes,
      :max_attempts
    ])
    |> change(status: "uploading", stage: "uploading", reserved_bytes: 0)
    |> validate_required([
      :workspace_id,
      :user_id,
      :original_filename,
      :project_name,
      :archive_storage_key,
      :archive_size_bytes,
      :staging_storage_keys,
      :progress_total_bytes,
      :max_attempts
    ])
    |> validate_common()
  end

  @doc "Accepts a preflighted upload and reserves capacity before its worker is enqueued."
  def admit_changeset(import, attrs) when is_map(attrs) do
    import
    |> cast(attrs, [
      :project_name,
      :manifest_checksum,
      :project_checksum,
      :reserved_bytes,
      :staging_storage_keys,
      :progress_total_bytes
    ])
    |> change(status: "queued", stage: "queued", progress_bytes: 0)
    |> validate_required([
      :project_name,
      :manifest_checksum,
      :project_checksum,
      :reserved_bytes,
      :staging_storage_keys,
      :progress_total_bytes
    ])
    |> validate_common()
  end

  @doc "Persists the deterministic destination inventory before provider staging starts."
  @spec materialization_plan_changeset(t(), pos_integer(), [String.t()]) :: Ecto.Changeset.t()
  def materialization_plan_changeset(import, reserved_project_id, storage_keys)
      when is_integer(reserved_project_id) and reserved_project_id > 0 and is_list(storage_keys) do
    import
    |> change(
      reserved_project_id: reserved_project_id,
      materialization_storage_keys: storage_keys,
      stage: "materializing"
    )
    |> validate_required([:reserved_project_id])
    |> validate_number(:reserved_project_id, greater_than: 0)
    |> validate_length(:materialization_storage_keys, max: 20_000)
    |> validate_common()
  end

  def materialization_plan_changeset(import, _reserved_project_id, _storage_keys) do
    import
    |> change()
    |> add_error(:reserved_project_id, "is invalid")
  end

  @doc "Binds the Oban delivery inserted in the same admission transaction."
  @spec bind_job_changeset(t(), pos_integer()) :: Ecto.Changeset.t()
  def bind_job_changeset(import, oban_job_id) do
    import
    |> change(oban_job_id: oban_job_id)
    |> validate_required([:oban_job_id])
    |> validate_number(:oban_job_id, greater_than: 0)
    |> validate_common()
  end

  @doc "Claims a queued operation or a scheduled retry."
  @spec running_changeset(t(), pos_integer(), pos_integer(), DateTime.t()) :: Ecto.Changeset.t()
  def running_changeset(import, attempt, max_attempts, now \\ TimeHelpers.now()) do
    import
    |> change(
      status: "running",
      stage: "verifying",
      attempt: attempt,
      max_attempts: max_attempts,
      progress_bytes: 0,
      failure_code: nil,
      failure_details: %{},
      started_at: import.started_at || now,
      completed_at: nil
    )
    |> validate_required([:oban_job_id, :started_at])
    |> validate_common()
  end

  @doc "Advances a running operation to materialization."
  @spec stage_changeset(t(), String.t()) :: Ecto.Changeset.t()
  def stage_changeset(import, stage) do
    import
    |> change(stage: stage)
    |> validate_inclusion(:stage, @running_stages)
    |> validate_common()
  end

  @doc "Persists bounded byte progress while the archive is verified."
  @spec progress_changeset(t(), non_neg_integer()) :: Ecto.Changeset.t()
  def progress_changeset(import, progress_bytes) do
    import
    |> change(progress_bytes: min(progress_bytes, import.progress_total_bytes))
    |> validate_common()
  end

  @doc "Pins the checksum calculated by the asynchronous full verification pass."
  def verified_changeset(import, archive_checksum) do
    import
    |> change(archive_checksum: archive_checksum)
    |> validate_required([:archive_checksum])
    |> validate_common()
  end

  @doc "Heartbeats a direct upload and exposes its browser-side byte progress."
  def upload_progress_changeset(import, progress_bytes) when is_integer(progress_bytes) and progress_bytes >= 0 do
    import
    |> change(progress_bytes: min(progress_bytes, import.progress_total_bytes))
    |> validate_common()
  end

  @doc "Records a retryable failure without releasing reserved capacity."
  @spec retrying_changeset(t(), String.t(), map()) :: Ecto.Changeset.t()
  def retrying_changeset(import, failure_code, failure_details \\ %{}) do
    import
    |> change(
      status: "retrying",
      stage: "retrying",
      failure_code: failure_code,
      failure_details: failure_details,
      completed_at: nil
    )
    |> validate_required([:failure_code])
    |> validate_common()
  end

  @doc "Publishes the recovered project and releases the active reservation."
  @spec completed_changeset(t(), Project.t(), DateTime.t()) :: Ecto.Changeset.t()
  def completed_changeset(import, %Project{} = project, now \\ TimeHelpers.now()) do
    import
    |> change(
      status: "completed",
      stage: "completed",
      project_id: project.id,
      reserved_bytes: 0,
      progress_bytes: import.progress_total_bytes,
      failure_code: nil,
      failure_details: %{},
      completed_at: now
    )
    |> validate_reserved_project(project.id)
    |> validate_required([:project_id, :started_at, :completed_at])
    |> validate_common()
  end

  @doc "Terminalizes an import without publishing a project."
  @spec failed_changeset(t(), String.t(), map(), DateTime.t()) :: Ecto.Changeset.t()
  def failed_changeset(import, failure_code, failure_details \\ %{}, now \\ TimeHelpers.now()) do
    import
    |> change(
      status: "failed",
      stage: "failed",
      project_id: nil,
      reserved_bytes: 0,
      failure_code: failure_code,
      failure_details: failure_details,
      started_at: import.started_at || now,
      completed_at: now
    )
    |> validate_required([:failure_code, :started_at, :completed_at])
    |> validate_common()
  end

  defp validate_common(changeset) do
    changeset
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:stage, @stages)
    |> validate_length(:original_filename, min: 1, max: 255)
    |> validate_length(:project_name, min: 1, max: 255)
    |> validate_length(:archive_storage_key, min: 1, max: 520)
    |> validate_format(:archive_checksum, @sha256_regex)
    |> validate_format(:manifest_checksum, @sha256_regex)
    |> validate_format(:project_checksum, @sha256_regex)
    |> validate_length(:failure_code, max: 100)
    |> validate_number(:archive_size_bytes, greater_than: 0)
    |> validate_number(:reserved_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:progress_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:progress_total_bytes, greater_than: 0)
    |> validate_number(:attempt, greater_than_or_equal_to: 0)
    |> validate_number(:max_attempts, greater_than: 0)
    |> validate_progress_bounds()
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:oban_job_id)
    |> unique_constraint(:workspace_id,
      name: :workspace_snapshot_imports_one_active_idx
    )
    |> unique_constraint(:oban_job_id,
      name: :workspace_snapshot_imports_oban_job_idx
    )
    |> check_constraint(:status, name: :workspace_snapshot_imports_status_check)
    |> check_constraint(:stage, name: :workspace_snapshot_imports_stage_check)
    |> check_constraint(:status, name: :workspace_snapshot_imports_lifecycle_check)
    |> check_constraint(:archive_checksum, name: :workspace_snapshot_imports_identity_check)
    |> check_constraint(:failure_details, name: :workspace_snapshot_imports_payload_check)
  end

  defp validate_progress_bounds(changeset) do
    progress = get_field(changeset, :progress_bytes)
    total = get_field(changeset, :progress_total_bytes)

    if is_integer(progress) and is_integer(total) and progress > total,
      do: add_error(changeset, :progress_bytes, "cannot exceed total progress"),
      else: changeset
  end

  defp validate_reserved_project(changeset, project_id) do
    if get_field(changeset, :reserved_project_id) == project_id,
      do: changeset,
      else: add_error(changeset, :project_id, "does not match the reserved project identity")
  end
end
