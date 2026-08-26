defmodule Storyarn.Localization.Access.Queries.Projects do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.Access.Data.ProjectMembershipRecord
  alias Storyarn.Localization.Access.Data.ProjectRecord
  alias Storyarn.Localization.Access.Data.WorkspaceRecord
  alias Storyarn.Localization.Access.Queries.Memberships
  alias Storyarn.Repo

  @spec get_project(map(), term()) ::
          {:ok, ProjectRecord.t(), ProjectMembershipRecord.t()} | {:error, :not_found}
  def get_project(%{user: %{id: user_id}}, project_id) when is_integer(user_id) and user_id > 0 do
    project =
      Repo.one(
        from(project in ProjectRecord,
          where: project.id == ^project_id and is_nil(project.deleted_at),
          preload: [:workspace]
        )
      )

    authorize_project(project, user_id)
  end

  def get_project(_scope, _project_id), do: {:error, :not_found}

  @spec get_project_by_slugs(map(), String.t(), String.t()) ::
          {:ok, ProjectRecord.t(), ProjectMembershipRecord.t()} | {:error, :not_found}
  def get_project_by_slugs(%{user: %{id: user_id}}, workspace_slug, project_slug)
      when is_integer(user_id) and user_id > 0 and is_binary(workspace_slug) and is_binary(project_slug) do
    project =
      Repo.one(
        from(project in ProjectRecord,
          join: workspace in WorkspaceRecord,
          on: workspace.id == project.workspace_id,
          where:
            workspace.slug == ^workspace_slug and project.slug == ^project_slug and
              is_nil(project.deleted_at),
          preload: [workspace: workspace]
        )
      )

    authorize_project(project, user_id)
  end

  def get_project_by_slugs(_scope, _workspace_slug, _project_slug), do: {:error, :not_found}

  defdelegate get_effective_membership(project_id, user_id, workspace_id),
    to: Memberships,
    as: :get_effective

  defp authorize_project(nil, _user_id), do: {:error, :not_found}

  defp authorize_project(%ProjectRecord{} = project, user_id) do
    case Memberships.get_effective(project.id, user_id, project.workspace_id) do
      %ProjectMembershipRecord{} = membership -> {:ok, project, membership}
      nil -> {:error, :not_found}
    end
  end
end
