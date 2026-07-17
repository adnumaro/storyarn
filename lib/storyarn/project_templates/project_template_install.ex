defmodule Storyarn.ProjectTemplates.ProjectTemplateInstall do
  @moduledoc """
  Durable state for a project created from a template version.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Workspaces.Workspace

  @statuses ~w(queued running retrying completed failed)
  @active_statuses ~w(queued running retrying)
  @stages ~w(queued verifying materializing retrying completed failed)
  @sources ~w(workspace_dashboard template_show internal)

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_template_version_id: integer() | nil,
          project_template_version: ProjectTemplateVersion.t() | NotLoaded.t() | nil,
          user_id: integer() | nil,
          user: User.t() | NotLoaded.t() | nil,
          workspace_id: integer() | nil,
          workspace: Workspace.t() | NotLoaded.t() | nil,
          project_id: integer() | nil,
          project: Project.t() | NotLoaded.t() | nil,
          oban_job_id: integer() | nil,
          status: String.t(),
          stage: String.t(),
          project_name: String.t() | nil,
          source: String.t(),
          idempotency_key: String.t() | nil,
          error_code: String.t() | nil,
          error_message: String.t() | nil,
          error_report: map(),
          feedback_dismissed_at: DateTime.t() | nil,
          installed_at: DateTime.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "project_template_installs" do
    field :status, :string, default: "completed"
    field :stage, :string, default: "completed"
    field :project_name, :string
    field :source, :string, default: "internal"
    field :idempotency_key, :string
    field :error_code, :string
    field :error_message, :string
    field :error_report, :map, default: %{}
    field :feedback_dismissed_at, :utc_datetime
    field :installed_at, :utc_datetime
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :oban_job_id, :integer

    belongs_to :project_template_version, ProjectTemplateVersion
    belongs_to :user, User
    belongs_to :workspace, Workspace
    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def active_statuses, do: @active_statuses
  def stages, do: @stages
  def sources, do: @sources

  def request_changeset(install, attrs) do
    install
    |> cast(attrs, [:status, :stage, :project_name, :source, :idempotency_key])
    |> validate_required([:status, :stage, :project_name, :source, :idempotency_key])
    |> validate_common()
  end

  def create_changeset(install, attrs) do
    install
    |> cast(attrs, [
      :status,
      :stage,
      :project_name,
      :source,
      :installed_at,
      :started_at,
      :completed_at
    ])
    |> validate_required([
      :status,
      :stage,
      :project_name,
      :source,
      :installed_at,
      :started_at,
      :completed_at
    ])
    |> validate_common()
  end

  def job_changeset(install, oban_job_id) do
    install
    |> change(oban_job_id: oban_job_id)
    |> foreign_key_constraint(:oban_job_id)
  end

  def running_changeset(install, now) do
    install
    |> change(
      status: "running",
      stage: "verifying",
      started_at: install.started_at || now,
      completed_at: nil,
      error_code: nil,
      error_message: nil,
      error_report: %{}
    )
    |> validate_common()
  end

  def stage_changeset(install, stage) do
    install
    |> change(stage: stage)
    |> validate_common()
  end

  def retrying_changeset(install, attrs) do
    install
    |> cast(attrs, [:status, :stage, :error_code, :error_message, :error_report])
    |> validate_required([:status, :stage])
    |> validate_common()
  end

  def failed_changeset(install, attrs) do
    install
    |> cast(attrs, [
      :status,
      :stage,
      :error_code,
      :error_message,
      :error_report,
      :completed_at
    ])
    |> change(project_id: nil, installed_at: nil)
    |> validate_required([:status, :stage, :error_code, :completed_at])
    |> validate_common()
  end

  def completed_changeset(install, project, now) do
    install
    |> change(
      status: "completed",
      stage: "completed",
      project_id: project.id,
      installed_at: now,
      completed_at: now,
      error_code: nil,
      error_message: nil,
      error_report: %{}
    )
    |> validate_common()
  end

  def dismiss_failure_changeset(install, now) do
    install
    |> change(feedback_dismissed_at: now)
    |> validate_common()
  end

  defp validate_common(changeset) do
    changeset
    |> validate_length(:project_name, min: 1, max: 100)
    |> validate_length(:idempotency_key, max: 64)
    |> validate_length(:error_code, max: 100)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:stage, @stages)
    |> validate_inclusion(:source, @sources)
    |> foreign_key_constraint(:project_template_version_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:oban_job_id)
    |> unique_constraint(:idempotency_key,
      name: :project_template_installs_active_idempotency_unique,
      message: "already has an active installation"
    )
    |> check_constraint(:status, name: :project_template_installs_status_check)
    |> check_constraint(:stage, name: :project_template_installs_stage_check)
    |> check_constraint(:source, name: :project_template_installs_source_check)
    |> check_constraint(:status, name: :project_template_installs_state_check)
    |> check_constraint(:feedback_dismissed_at,
      name: :project_template_installs_feedback_dismissal_check
    )
    |> check_constraint(:project_id, name: :project_template_installs_failed_project_check)
  end
end
