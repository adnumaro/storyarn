defmodule Storyarn.ProjectTemplates.ProjectTemplateInstall do
  @moduledoc """
  Records a project created from a template version.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Workspaces.Workspace

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
          installed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "project_template_installs" do
    field :installed_at, :utc_datetime

    belongs_to :project_template_version, ProjectTemplateVersion
    belongs_to :user, User
    belongs_to :workspace, Workspace
    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  def create_changeset(install, attrs) do
    install
    |> cast(attrs, [:installed_at])
    |> validate_required([:installed_at])
    |> foreign_key_constraint(:project_template_version_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:project_id)
  end
end
