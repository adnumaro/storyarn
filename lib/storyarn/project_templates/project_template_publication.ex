defmodule Storyarn.ProjectTemplates.ProjectTemplatePublication do
  @moduledoc """
  Durable state for an asynchronous project template publication.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion

  @modes ~w(new update)
  @statuses ~w(queued running retrying published failed)
  @active_statuses ~w(queued running retrying)

  @type t :: %__MODULE__{
          id: integer() | nil,
          owner_id: integer() | nil,
          owner: User.t() | NotLoaded.t() | nil,
          requested_by_id: integer() | nil,
          requested_by: User.t() | NotLoaded.t() | nil,
          source_project_id: integer() | nil,
          source_project: Project.t() | NotLoaded.t() | nil,
          project_template_id: integer() | nil,
          project_template: ProjectTemplate.t() | NotLoaded.t() | nil,
          project_template_version_id: integer() | nil,
          project_template_version: ProjectTemplateVersion.t() | NotLoaded.t() | nil,
          oban_job_id: integer() | nil,
          mode: String.t() | nil,
          status: String.t(),
          name: String.t() | nil,
          description: String.t() | nil,
          version_notes: String.t() | nil,
          snapshot_storage_key: String.t() | nil,
          asset_manifest_storage_key: String.t() | nil,
          checksum: String.t() | nil,
          entity_counts: map(),
          preview: map(),
          audit_report: map(),
          error_code: String.t() | nil,
          error_message: String.t() | nil,
          error_report: map(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "project_template_publications" do
    field :mode, :string
    field :status, :string, default: "queued"
    field :name, :string
    field :description, :string
    field :version_notes, :string
    field :snapshot_storage_key, :string
    field :asset_manifest_storage_key, :string
    field :checksum, :string
    field :entity_counts, :map, default: %{}
    field :preview, :map, default: %{}
    field :audit_report, :map, default: %{}
    field :error_code, :string
    field :error_message, :string
    field :error_report, :map, default: %{}
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :oban_job_id, :integer

    belongs_to :owner, User
    belongs_to :requested_by, User
    belongs_to :source_project, Project
    belongs_to :project_template, ProjectTemplate
    belongs_to :project_template_version, ProjectTemplateVersion

    timestamps(type: :utc_datetime)
  end

  def modes, do: @modes
  def statuses, do: @statuses
  def active_statuses, do: @active_statuses

  def create_changeset(publication, attrs) do
    publication
    |> cast(attrs, [:mode, :status, :name, :description, :version_notes])
    |> validate_required([:mode, :status, :name])
    |> validate_common()
  end

  def job_changeset(publication, oban_job_id) do
    publication
    |> change(oban_job_id: oban_job_id)
    |> foreign_key_constraint(:oban_job_id)
  end

  def running_changeset(publication, now) do
    publication
    |> change(status: "running", started_at: now, completed_at: nil)
    |> validate_common()
  end

  def retrying_changeset(publication, attrs) do
    publication
    |> cast(attrs, [:status, :error_code, :error_message, :error_report])
    |> validate_required([:status])
    |> validate_common()
  end

  def failed_changeset(publication, attrs) do
    publication
    |> cast(attrs, [:status, :error_code, :error_message, :error_report, :audit_report, :completed_at])
    |> validate_required([:status, :completed_at])
    |> validate_common()
  end

  def published_changeset(publication, attrs) do
    publication
    |> cast(attrs, [
      :status,
      :project_template_id,
      :project_template_version_id,
      :snapshot_storage_key,
      :asset_manifest_storage_key,
      :checksum,
      :entity_counts,
      :preview,
      :audit_report,
      :completed_at
    ])
    |> validate_required([
      :status,
      :project_template_id,
      :project_template_version_id,
      :snapshot_storage_key,
      :asset_manifest_storage_key,
      :checksum,
      :entity_counts,
      :preview,
      :audit_report,
      :completed_at
    ])
    |> validate_common()
  end

  defp validate_common(changeset) do
    changeset
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1_000)
    |> validate_length(:version_notes, max: 2_000)
    |> validate_length(:snapshot_storage_key, max: 255)
    |> validate_length(:asset_manifest_storage_key, max: 255)
    |> validate_format(:checksum, ~r/^[a-f0-9]{64}$/)
    |> validate_inclusion(:mode, @modes)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:owner_id)
    |> foreign_key_constraint(:requested_by_id)
    |> foreign_key_constraint(:source_project_id)
    |> foreign_key_constraint(:project_template_id)
    |> foreign_key_constraint(:project_template_version_id)
    |> foreign_key_constraint(:oban_job_id)
    |> unique_constraint(:project_template_id,
      name: :project_template_publications_active_template_unique,
      message: "already has an active publication"
    )
    |> unique_constraint(:source_project_id,
      name: :project_template_publications_active_new_source_unique,
      message: "already has an active publication"
    )
    |> check_constraint(:mode, name: :project_template_publications_mode_check)
    |> check_constraint(:status, name: :project_template_publications_status_check)
  end
end
