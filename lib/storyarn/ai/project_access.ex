defmodule Storyarn.AI.ProjectAccess do
  @moduledoc """
  AI-owned project access reads over the shared project tables.

  ENG-92 copy of the Projects access reads the AI kernel depends on:
  effective membership resolution (direct project role first, then the
  workspace role mapped to a synthetic project role).
  """

  import Ecto.Query, warn: false

  alias Storyarn.AI.Persistence.ProjectMembershipRecord, as: ProjectMembership
  alias Storyarn.AI.Persistence.ProjectRecord, as: Project
  alias Storyarn.AI.Persistence.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.Repo

  @workspace_to_project_role %{
    "owner" => "editor",
    "admin" => "editor",
    "member" => "editor",
    "viewer" => "viewer"
  }

  @doc """
  Gets a project by ID with the effective membership for the scope's user.
  """
  def get_project(%{user: user}, id) do
    project = Repo.one(from(p in Project, where: p.id == ^id and is_nil(p.deleted_at)))

    with %Project{} <- project,
         %ProjectMembership{} = membership <- get_effective_membership(project.id, user.id, project.workspace_id) do
      {:ok, project, membership}
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Checks whether a project role can perform an action.

  Copy of the project permission table: owner does everything; editor edits
  content, uses AI and views; viewer only views.
  """
  def can?(role, action)

  def can?("owner", _action), do: true
  def can?("editor", :edit_content), do: true
  def can?("editor", :use_ai), do: true
  def can?("editor", :view), do: true
  def can?("viewer", :view), do: true
  def can?(_role, _action), do: false

  @doc """
  Resolves the effective project role from a direct project role and a
  workspace role: a direct project membership wins; otherwise the workspace
  role maps to a synthetic project role. Returns `nil` when the user has
  neither.
  """
  def effective_role(project_role, workspace_role)

  def effective_role(nil, nil), do: nil
  def effective_role(nil, workspace_role), do: Map.get(@workspace_to_project_role, workspace_role, "viewer")
  def effective_role(project_role, _workspace_role), do: project_role

  defp get_effective_membership(project_id, user_id, workspace_id) do
    case Repo.get_by(ProjectMembership, project_id: project_id, user_id: user_id) do
      %ProjectMembership{} = membership ->
        membership

      nil ->
        case Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id) do
          %WorkspaceMembership{role: workspace_role} ->
            %ProjectMembership{
              project_id: project_id,
              user_id: user_id,
              role: Map.get(@workspace_to_project_role, workspace_role, "viewer")
            }

          nil ->
            nil
        end
    end
  end
end
