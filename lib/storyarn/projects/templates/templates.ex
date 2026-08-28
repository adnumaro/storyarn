defmodule Storyarn.Projects.Templates do
  @moduledoc """
  Project-owned boundary for publishing, installing, and exchanging templates.

  `Storyarn.Projects.ProjectTemplates` remains the stable implementation
  identity. This module gives the root `Storyarn.Projects` facade a single
  capability boundary without changing any template behavior or data format.
  """

  alias Storyarn.Projects.Access
  alias Storyarn.Projects.Lifecycle
  alias Storyarn.Projects.ProjectTemplates

  defdelegate list_templates(scope, opts \\ []), to: ProjectTemplates
  defdelegate paginate_templates(scope, opts \\ []), to: ProjectTemplates
  defdelegate get_template(scope, id, opts \\ []), to: ProjectTemplates
  defdelegate get_template!(scope, id), to: ProjectTemplates
  defdelegate list_template_versions(scope, template), to: ProjectTemplates
  defdelegate list_template_installs(scope, template, opts \\ []), to: ProjectTemplates
  defdelegate list_template_publications(scope, opts \\ []), to: ProjectTemplates
  defdelegate can_manage_template?(scope, template), to: ProjectTemplates
  defdelegate can_publish_source_project?(scope, project), to: ProjectTemplates
  defdelegate get_template_publication!(scope, id), to: ProjectTemplates
  defdelegate request_template_publication(scope, source_project, attrs), to: ProjectTemplates

  defdelegate request_template_version_publication(scope, template, source_project, attrs),
    to: ProjectTemplates

  defdelegate perform_template_publication(publication_id, opts \\ []), to: ProjectTemplates
  defdelegate subscribe_template_publications(project_or_template), to: ProjectTemplates
  defdelegate create_template_from_project(scope, source_project, attrs), to: ProjectTemplates
  defdelegate publish_new_version(scope, template, source_project), to: ProjectTemplates
  defdelegate update_template(scope, template, attrs), to: ProjectTemplates
  defdelegate archive_template(scope, template), to: ProjectTemplates
  defdelegate unarchive_template(scope, template), to: ProjectTemplates
  defdelegate delete_template(scope, template), to: ProjectTemplates
  defdelegate perform_template_artifact_gc(storage_keys), to: ProjectTemplates

  defdelegate update_template_and_publish_new_version(scope, template, source_project, attrs),
    to: ProjectTemplates

  defdelegate instantiate_template(scope, version, workspace, attrs), to: ProjectTemplates
  defdelegate request_template_instantiation(scope, version, workspace, attrs), to: ProjectTemplates
  defdelegate perform_template_installation(installation_id, opts \\ []), to: ProjectTemplates
  defdelegate list_active_workspace_installations(scope, workspace), to: ProjectTemplates

  defdelegate list_pending_workspace_installation_failures(scope, workspace),
    to: ProjectTemplates

  defdelegate list_pending_template_installation_failures(scope, template),
    to: ProjectTemplates

  defdelegate pending_installation_failure?(scope, workspace, installation_id),
    to: ProjectTemplates

  defdelegate dismiss_installation_failure(scope, workspace, installation_id),
    to: ProjectTemplates

  defdelegate list_active_template_installations(scope, template), to: ProjectTemplates
  defdelegate subscribe_workspace_installations(workspace), to: ProjectTemplates
  defdelegate subscribe_user_installations(scope), to: ProjectTemplates
  defdelegate export_portable_template(project_id, output_path, opts \\ []), to: ProjectTemplates
  defdelegate preview_portable_template(path, opts \\ []), to: ProjectTemplates
  defdelegate import_portable_template(path, opts \\ []), to: ProjectTemplates

  def request_project_template_version_publication(scope, template_id, project_id, attrs)
      when is_integer(template_id) and is_integer(project_id) and is_map(attrs) do
    with {:ok, template} <- ProjectTemplates.get_template(scope, template_id),
         {:ok, project, _membership} <- Lifecycle.get_project(scope, project_id) do
      ProjectTemplates.request_template_version_publication(scope, template, project, attrs)
    end
  end

  def request_project_template_version_publication(_scope, _template_id, _project_id, _attrs), do: {:error, :not_found}

  def request_project_template_instantiation(scope, template_id, version_id, workspace_id, attrs)
      when is_integer(template_id) and is_integer(version_id) and is_integer(workspace_id) and is_map(attrs) do
    with {:ok, template} <- ProjectTemplates.get_template(scope, template_id),
         version when not is_nil(version) <-
           scope
           |> ProjectTemplates.list_template_versions(template)
           |> Enum.find(&(&1.id == version_id)),
         {:ok, workspace, _membership} <-
           Access.authorize_workspace(scope, workspace_id, :create_project) do
      ProjectTemplates.request_template_instantiation(scope, version, workspace, attrs)
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def request_project_template_instantiation(_scope, _template_id, _version_id, _workspace_id, _attrs),
    do: {:error, :not_found}

  def list_active_workspace_template_installations(scope, workspace_id) do
    case Access.authorize_workspace(scope, workspace_id, :view) do
      {:ok, workspace, _membership} -> ProjectTemplates.list_active_workspace_installations(scope, workspace)
      {:error, _reason} -> []
    end
  end

  def list_pending_workspace_template_installation_failures(scope, workspace_id) do
    case Access.authorize_workspace(scope, workspace_id, :view) do
      {:ok, workspace, _membership} ->
        ProjectTemplates.list_pending_workspace_installation_failures(scope, workspace)

      {:error, _reason} ->
        []
    end
  end

  def dismiss_project_template_installation_failure(scope, workspace_id, installation_id) do
    with {:ok, workspace, _membership} <- Access.authorize_workspace(scope, workspace_id, :view) do
      ProjectTemplates.dismiss_installation_failure(scope, workspace, installation_id)
    end
  end

  def subscribe_workspace_template_installations(scope, workspace_id) do
    with {:ok, workspace, _membership} <- Access.authorize_workspace(scope, workspace_id, :view) do
      ProjectTemplates.subscribe_workspace_installations(workspace)
    end
  end
end
