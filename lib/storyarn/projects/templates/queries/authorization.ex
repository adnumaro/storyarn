defmodule Storyarn.Projects.ProjectTemplates.Authorization do
  @moduledoc false

  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectCrud
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Projects.ProjectTemplates.AuthorizationQueries
  alias Storyarn.Projects.ProjectTemplates.AuthorizationRules
  alias Storyarn.Projects.ProjectTemplates.ProjectTemplate

  defdelegate ensure_private_visibility(attrs), to: AuthorizationRules
  defdelegate ensure_template_source(template, project), to: AuthorizationRules

  def authorize_source_project(%{user: user} = scope, %Project{id: project_id}) when not is_nil(user) do
    case ProjectCrud.get_project(scope, project_id) do
      {:ok, project, membership} ->
        project_manager? = ProjectMembership.can?(membership.role, :manage_project)
        workspace_admin? = AuthorizationQueries.source_project_admin?(user.id, project.workspace_id)

        if AuthorizationRules.project_manager?(project_manager?, workspace_admin?),
          do: {:ok, project},
          else: {:error, :unauthorized}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def authorize_source_project(_scope, _project), do: {:error, :unauthorized}

  def can_publish_source_project?(%{user: user} = scope, %Project{} = project) when not is_nil(user) do
    match?({:ok, _project}, authorize_source_project(scope, project))
  end

  def can_publish_source_project?(_scope, _project), do: false

  def authorize_template_manager(%{user: _} = scope, %ProjectTemplate{} = template) do
    if can_manage_template?(scope, template), do: :ok, else: {:error, :unauthorized}
  end

  def authorize_template_manager(_scope, _template), do: {:error, :unauthorized}

  def can_manage_template?(%{user: %{id: user_id}}, %ProjectTemplate{visibility: "private"} = template) do
    source_admin? = AuthorizationQueries.source_template_admin?(user_id, template.source_project_id)
    AuthorizationRules.private_template_manager?(template, user_id, source_admin?)
  end

  def can_manage_template?(%{user: %{is_super_admin: true}} = scope, %ProjectTemplate{
        visibility: "public",
        source_project_id: source_project_id
      })
      when is_integer(source_project_id) do
    case AuthorizationQueries.get_source_project(source_project_id) do
      %Project{} = source_project ->
        match?({:ok, _project}, authorize_source_project(scope, source_project))

      nil ->
        false
    end
  end

  def can_manage_template?(_scope, _template), do: false

  def authorize_template_visibility(
        %{user: _} = scope,
        %ProjectTemplate{status: "active", visibility: "private"} = template
      ) do
    if AuthorizationRules.visibility_authorized?(template, can_manage_template?(scope, template)),
      do: :ok,
      else: {:error, :unauthorized}
  end

  def authorize_template_visibility(%{user: %{}}, %ProjectTemplate{status: "active", visibility: "public"}), do: :ok

  def authorize_template_visibility(%{user: _}, %ProjectTemplate{status: "archived"}), do: {:error, :archived}

  def authorize_template_visibility(_scope, _template), do: {:error, :unauthorized}
end
