defmodule Storyarn.ProjectTemplates.Authorization do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.Repo
  alias Storyarn.Workspaces.WorkspaceMembership

  def ensure_private_visibility(attrs) do
    visibility = Map.get(attrs, :visibility) || Map.get(attrs, "visibility") || "private"

    if visibility == "private" do
      :ok
    else
      {:error, :public_visibility_requires_admin}
    end
  end

  def authorize_source_project(%Scope{user: user} = scope, %Project{id: project_id}) when not is_nil(user) do
    case Projects.get_project(scope, project_id) do
      {:ok, project, membership} ->
        if Projects.can?(membership.role, :manage_project) or source_project_admin?(user.id, project.workspace_id) do
          {:ok, project}
        else
          {:error, :unauthorized}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def authorize_source_project(_scope, _project), do: {:error, :unauthorized}

  def can_publish_source_project?(%Scope{user: user} = scope, %Project{} = project) when not is_nil(user) do
    case authorize_source_project(scope, project) do
      {:ok, _project} -> true
      {:error, _reason} -> false
    end
  end

  def can_publish_source_project?(_scope, _project), do: false

  def ensure_template_source(%ProjectTemplate{source_project_id: project_id}, %Project{id: project_id}), do: :ok
  def ensure_template_source(%ProjectTemplate{}, %Project{}), do: {:error, :invalid_source_project}

  def authorize_template_manager(%Scope{} = scope, %ProjectTemplate{} = template) do
    if can_manage_template?(scope, template) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  def authorize_template_manager(_scope, _template), do: {:error, :unauthorized}

  def can_manage_template?(%Scope{user: %{id: user_id}}, %ProjectTemplate{visibility: "private"} = template) do
    template.owner_id == user_id or source_template_admin?(user_id, template.source_project_id)
  end

  def can_manage_template?(%Scope{user: %{is_super_admin: true}} = scope, %ProjectTemplate{
        visibility: "public",
        source_project_id: source_project_id
      })
      when is_integer(source_project_id) do
    case Repo.get(Project, source_project_id) do
      %Project{} = source_project -> match?({:ok, _project}, authorize_source_project(scope, source_project))
      nil -> false
    end
  end

  def can_manage_template?(_scope, _template), do: false

  def authorize_template_visibility(
        %Scope{} = scope,
        %ProjectTemplate{status: "active", visibility: "private"} = template
      ) do
    if can_manage_template?(scope, template) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  def authorize_template_visibility(%Scope{user: %{}}, %ProjectTemplate{status: "active", visibility: "public"}) do
    :ok
  end

  def authorize_template_visibility(%Scope{}, %ProjectTemplate{status: "archived"}), do: {:error, :archived}

  def authorize_template_visibility(_scope, _template), do: {:error, :unauthorized}

  def source_template_admin?(_user_id, nil), do: false

  def source_template_admin?(user_id, source_project_id) do
    query =
      from membership in WorkspaceMembership,
        join: project in Project,
        on: project.workspace_id == membership.workspace_id,
        where:
          project.id == ^source_project_id and membership.user_id == ^user_id and
            membership.role in ["owner", "admin"],
        select: true,
        limit: 1

    Repo.exists?(query)
  end

  def source_project_admin?(user_id, workspace_id) do
    query =
      from membership in WorkspaceMembership,
        where:
          membership.workspace_id == ^workspace_id and membership.user_id == ^user_id and
            membership.role in ["owner", "admin"],
        select: true,
        limit: 1

    Repo.exists?(query)
  end
end
