defmodule Storyarn.Projects.Lifecycle.Queries.ProjectQueries do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Memberships
  alias Storyarn.Projects.Persistence.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.Projects.Persistence.WorkspaceRecord, as: Workspace
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo

  def list_projects(%{user: user}) do
    Project
    |> where([project], is_nil(project.deleted_at))
    |> join(:inner, [project], membership in ProjectMembership,
      on: membership.project_id == project.id and membership.user_id == ^user.id
    )
    |> select([project, membership], %{project: project, role: membership.role})
    |> order_by([project], desc: fragment("COALESCE(?, ?)", project.last_activity_at, project.updated_at))
    |> Repo.all()
  end

  def list_projects_for_workspace(workspace_id, %{user: user}) do
    Project
    |> where([project], project.workspace_id == ^workspace_id and is_nil(project.deleted_at))
    |> join(:left, [project], project_membership in ProjectMembership,
      on: project_membership.project_id == project.id and project_membership.user_id == ^user.id
    )
    |> join(:left, [project, project_membership], workspace_membership in WorkspaceMembership,
      on:
        workspace_membership.workspace_id == project.workspace_id and
          workspace_membership.user_id == ^user.id
    )
    |> where(
      [project, project_membership, workspace_membership],
      not is_nil(project_membership.id) or not is_nil(workspace_membership.id)
    )
    |> select([project, project_membership, workspace_membership], %{
      project: project,
      project_role: project_membership.role,
      workspace_role: workspace_membership.role
    })
    |> order_by([project], desc: fragment("COALESCE(?, ?)", project.last_activity_at, project.updated_at))
    |> Repo.all()
  end

  def get_project(%{user: user}, id) do
    project = Repo.one(from(project in Project, where: project.id == ^id and is_nil(project.deleted_at)))

    with %Project{} <- project,
         %ProjectMembership{} = membership <-
           Memberships.get_effective_membership(project.id, user.id, project.workspace_id) do
      {:ok, project, membership}
    else
      nil -> {:error, :not_found}
    end
  end

  def reload_project(scope, id) do
    with {:ok, project, membership} <- get_project(scope, id) do
      {:ok, Repo.preload(project, :workspace), membership}
    end
  end

  def get_project!(id), do: Repo.get!(Project, id)

  def get_project_by_slugs(%{user: user}, workspace_slug, project_slug) do
    query =
      from project in Project,
        join: workspace in Workspace,
        on: workspace.id == project.workspace_id,
        where:
          workspace.slug == ^workspace_slug and project.slug == ^project_slug and
            is_nil(project.deleted_at),
        preload: [:workspace]

    with %Project{} = project <- Repo.one(query),
         %ProjectMembership{} = membership <-
           Memberships.get_effective_membership(project.id, user.id, project.workspace_id) do
      {:ok, project, membership}
    else
      nil -> {:error, :not_found}
    end
  end

  def list_deleted_projects(workspace_id) do
    Repo.all(
      from(project in Project,
        where: project.workspace_id == ^workspace_id and not is_nil(project.deleted_at),
        order_by: [desc: project.deleted_at],
        preload: [:deleted_by]
      )
    )
  end

  def get_deleted_project(workspace_id, project_id) do
    Repo.one(
      from(project in Project,
        where:
          project.id == ^project_id and project.workspace_id == ^workspace_id and
            not is_nil(project.deleted_at),
        preload: [:deleted_by]
      )
    )
  end

  @spec auto_versioning_enabled?(integer(), :flow | :scene | :sheet) :: boolean()
  def auto_versioning_enabled?(project_id, entity_type) do
    field = auto_version_field(entity_type)

    from(project in Project,
      where: project.id == ^project_id,
      select: field(project, ^field)
    )
    |> Repo.one()
    |> Kernel.||(false)
  end

  defp auto_version_field(:flow), do: :auto_version_flows
  defp auto_version_field(:scene), do: :auto_version_scenes
  defp auto_version_field(:sheet), do: :auto_version_sheets
end
