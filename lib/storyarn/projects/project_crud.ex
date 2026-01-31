defmodule Storyarn.Projects.ProjectCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Projects.{Project, ProjectMembership, SlugGenerator}
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @doc """
  Lists all projects the user has access to (owned or as a member).
  """
  def list_projects(%Scope{user: user}) do
    Project
    |> join(:inner, [p], m in ProjectMembership,
      on: m.project_id == p.id and m.user_id == ^user.id
    )
    |> select([p, m], %{project: p, role: m.role})
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Lists all projects in a workspace that the user has access to.
  """
  def list_projects_for_workspace(workspace_id, %Scope{user: user}) do
    Project
    |> where([p], p.workspace_id == ^workspace_id)
    |> join(:left, [p], pm in ProjectMembership,
      on: pm.project_id == p.id and pm.user_id == ^user.id
    )
    |> join(:left, [p, pm], wm in Storyarn.Workspaces.WorkspaceMembership,
      on: wm.workspace_id == p.workspace_id and wm.user_id == ^user.id
    )
    |> where([p, pm, wm], not is_nil(pm.id) or not is_nil(wm.id))
    |> select([p, pm, wm], %{
      project: p,
      project_role: pm.role,
      workspace_role: wm.role
    })
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a single project by ID with authorization check.
  """
  def get_project(%Scope{user: user}, id) do
    with %Project{} = project <- Repo.get(Project, id),
         %ProjectMembership{} = membership <- get_membership(project.id, user.id) do
      {:ok, project, membership}
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Gets a project without authorization check.
  """
  def get_project!(id), do: Repo.get!(Project, id)

  @doc """
  Gets a project by workspace slug and project slug with authorization check.
  """
  def get_project_by_slugs(%Scope{user: user}, workspace_slug, project_slug) do
    query =
      from p in Project,
        join: w in Workspace,
        on: w.id == p.workspace_id,
        where: w.slug == ^workspace_slug and p.slug == ^project_slug,
        select: p

    with %Project{} = project <- Repo.one(query),
         %ProjectMembership{} = membership <- get_membership(project.id, user.id) do
      {:ok, project, membership}
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Creates a project and sets up the owner membership.
  """
  def create_project(%Scope{user: user}, attrs) do
    Repo.transact(fn ->
      with {:ok, project} <- insert_project(user, attrs),
           {:ok, _membership} <- create_owner_membership(project, user) do
        {:ok, project}
      end
    end)
  end

  @doc """
  Returns a changeset for tracking project changes.
  """
  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.update_changeset(project, attrs)
  end

  @doc """
  Updates a project.
  """
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project.
  """
  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  # Private helpers

  defp insert_project(user, attrs) do
    workspace_id = attrs[:workspace_id] || attrs["workspace_id"]
    name = attrs[:name] || attrs["name"] || "untitled"
    slug = SlugGenerator.generate_slug(workspace_id, name)

    %Project{owner_id: user.id}
    |> Project.create_changeset(Map.put(attrs, :slug, slug))
    |> Repo.insert()
  end

  defp create_owner_membership(project, user) do
    %ProjectMembership{}
    |> ProjectMembership.changeset(%{project_id: project.id, user_id: user.id, role: "owner"})
    |> Repo.insert()
  end

  defp get_membership(project_id, user_id) do
    Repo.get_by(ProjectMembership, project_id: project_id, user_id: user_id)
  end
end
