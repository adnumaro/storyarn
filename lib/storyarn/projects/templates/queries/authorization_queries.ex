defmodule Storyarn.Projects.ProjectTemplates.AuthorizationQueries do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Persistence.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  def get_source_project(project_id) when is_integer(project_id), do: Repo.get(Project, project_id)
  def get_source_project(_project_id), do: nil

  def source_template_admin?(_user_id, nil), do: false

  def source_template_admin?(user_id, source_project_id) do
    Repo.exists?(
      from membership in WorkspaceMembership,
        join: project in Project,
        on: project.workspace_id == membership.workspace_id,
        where:
          project.id == ^source_project_id and membership.user_id == ^user_id and
            membership.role in ["owner", "admin"]
    )
  end

  def source_project_admin?(user_id, workspace_id) do
    Repo.exists?(
      from membership in WorkspaceMembership,
        where:
          membership.workspace_id == ^workspace_id and membership.user_id == ^user_id and
            membership.role in ["owner", "admin"]
    )
  end
end
