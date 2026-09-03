defmodule StoryarnWeb.ProjectSettingsLive.Templates do
  @moduledoc """
  Project › Templates: publish the project as a private workspace template
  and follow the publication history. Open to the project owner and to
  workspace members who may publish templates.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Projects

  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      current_path={@current_path}
      settings_nav={@settings_nav}
    >
      <.vue
        v-component="live/project/settings/ProjectSettingsTemplates"
        v-socket={@socket}
        v-inject="settings-layout"
        id="project-settings-templates"
        project-name={@project.name}
        project-description={@project.description || ""}
        project-templates={serialize_project_templates(@project_templates)}
        project-template-publications={serialize_template_publications(@template_publications)}
        can-publish={@can_publish}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    stale_project = socket.assigns.project

    if connected?(socket) do
      :ok = Projects.subscribe_project_ownership_changes(stale_project.id)
      :ok = Projects.subscribe_project_template_publications(stale_project)
    end

    with {:ok, project, membership} <-
           Projects.reload_project(socket.assigns.current_scope, stale_project.id),
         true <- can_open?(socket.assigns.current_scope, project, membership) do
      {:ok,
       socket
       |> assign(:project, project)
       |> assign(:workspace, project.workspace)
       |> assign(:membership, membership)
       |> assign(:current_workspace, project.workspace)
       |> assign(:page_title, dgettext("projects", "Templates"))
       |> assign_publish_permission()
       |> assign_project_templates()
       |> assign_template_publications()}
    else
      _lost_access ->
        {:ok,
         socket
         |> put_flash(
           :error,
           dgettext("projects", "You don't have permission to manage this project.")
         )
         |> redirect(to: ~p"/workspaces/#{stale_project.workspace.slug}/projects/#{stale_project.slug}")}
    end
  end

  @impl true
  def handle_params(_params, url, socket) do
    {:noreply, assign(socket, :current_path, URI.parse(url).path)}
  end

  @impl true
  def handle_event("publish_template", %{"template" => template_params}, socket) do
    if Projects.can_publish_project_template?(socket.assigns.current_scope, socket.assigns.project) do
      {:noreply, enqueue_template_publication(socket, template_params)}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("projects", "You don't have permission to publish templates from this project.")
       )}
    end
  end

  @impl true
  def handle_info({:project_template_publication_updated, _publication}, socket) do
    {:noreply,
     socket
     |> assign_project_templates()
     |> assign_template_publications()}
  end

  def handle_info(
        {:project_ownership_transferred, %{project_id: project_id}},
        %{assigns: %{project: %{id: project_id}}} = socket
      ) do
    with {:ok, project, membership} <-
           Projects.reload_project(socket.assigns.current_scope, project_id),
         true <- can_open?(socket.assigns.current_scope, project, membership) do
      {:noreply,
       socket
       |> assign(:project, project)
       |> assign(:membership, membership)
       |> assign(:current_workspace, project.workspace)
       |> assign_publish_permission()
       |> assign_project_templates()
       |> assign_template_publications()}
    else
      _lost_access ->
        project = socket.assigns.project

        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("projects", "You don't have permission to manage this project.")
         )
         |> push_navigate(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp can_open?(scope, project, membership) do
    (project.owner_id == scope.user.id and Projects.can?(membership.role, :manage_project)) or
      Projects.can_publish_project_template?(scope, project)
  end

  defp assign_publish_permission(socket) do
    assign(
      socket,
      :can_publish,
      Projects.can_publish_project_template?(socket.assigns.current_scope, socket.assigns.project)
    )
  end

  defp publish_template_from_settings(socket, %{"mode" => "new"} = params) do
    Projects.request_project_template_publication(
      socket.assigns.current_scope,
      socket.assigns.project,
      template_attrs(params)
    )
  end

  defp publish_template_from_settings(socket, %{"mode" => "update"} = params) do
    with {:ok, template_id} <- parse_template_id(params["template_id"]),
         {:ok, template} <- Projects.get_project_template(socket.assigns.current_scope, template_id) do
      Projects.request_project_template_version_publication(
        socket.assigns.current_scope,
        template.id,
        socket.assigns.project.id,
        template_attrs(params)
      )
    end
  end

  defp publish_template_from_settings(_socket, _params), do: {:error, :invalid_mode}

  defp enqueue_template_publication(socket, template_params) do
    case publish_template_from_settings(socket, template_params) do
      {:ok, _publication} ->
        socket
        |> assign_project_templates()
        |> assign_template_publications()
        |> put_flash(:info, dgettext("projects", "Template publication queued."))

      {:error, :limit_reached, details} ->
        Logger.warning(fn ->
          "Template publication enqueue blocked by plan limit project_id=#{socket.assigns.project.id} " <>
            "details=#{inspect(details)}"
        end)

        put_flash(socket, :error, template_publication_error_message({:limit_reached, details}))

      {:error, reason} ->
        Logger.warning(fn ->
          "Template publication enqueue failed project_id=#{socket.assigns.project.id} " <>
            "reason=#{inspect(template_publication_failure_summary(reason))}"
        end)

        put_flash(socket, :error, template_publication_error_message(reason))
    end
  end

  defp template_publication_failure_summary(%{"errors" => errors, "materialization" => materialization} = report) do
    %{
      status: Map.get(report, "status"),
      error_count: length(errors || []),
      first_errors: Enum.take(errors || [], 5),
      materialization: materialization
    }
  end

  defp template_publication_failure_summary(%Ecto.Changeset{} = changeset) do
    %{changeset_valid?: changeset.valid?, errors: changeset.errors}
  end

  defp template_publication_failure_summary(reason), do: reason

  defp template_publication_error_message(:publication_already_active) do
    dgettext("projects", "A template publication is already running.")
  end

  defp template_publication_error_message({:limit_reached, %{resource: :project_templates_per_workspace}}) do
    dgettext("projects", "Template limit reached for your plan.")
  end

  defp template_publication_error_message({:limit_reached, %{resource: :project_template_versions_per_template}}) do
    dgettext("projects", "Template version limit reached for your plan.")
  end

  defp template_publication_error_message(_reason) do
    dgettext("projects", "Template could not be queued.")
  end

  defp template_attrs(params) do
    %{
      "name" => params["name"],
      "description" => params["description"],
      "version_notes" => params["version_notes"]
    }
  end

  defp parse_template_id(value) when is_integer(value), do: {:ok, value}

  defp parse_template_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> {:error, :invalid_template_id}
    end
  end

  defp parse_template_id(_value), do: {:error, :invalid_template_id}

  defp assign_project_templates(socket) do
    templates =
      socket.assigns.current_scope
      |> Projects.list_project_templates(source_project_id: socket.assigns.project.id)
      |> Enum.filter(&(&1.visibility == "private" and &1.source_project_id == socket.assigns.project.id))

    assign(socket, :project_templates, templates)
  end

  defp assign_template_publications(socket) do
    assign(
      socket,
      :template_publications,
      Projects.list_project_template_publications(socket.assigns.current_scope,
        source_project_id: socket.assigns.project.id,
        limit: 10
      )
    )
  end

  defp serialize_project_templates(templates) do
    Enum.map(templates, fn template ->
      %{
        id: template.id,
        name: template.name,
        description: template.description || "",
        current_version_number: version_number(template.current_version)
      }
    end)
  end

  defp version_number(%{version_number: version_number}), do: version_number
  defp version_number(_version), do: nil

  defp serialize_template_publications(publications) do
    Enum.map(publications, fn publication ->
      %{
        id: publication.id,
        mode: publication.mode,
        status: publication.status,
        template_id: publication.project_template_id,
        template_version_id: publication.project_template_version_id,
        name: publication.name,
        description: publication.description || "",
        version_notes: publication.version_notes || "",
        error_message: publication.error_message,
        inserted_at: iso_datetime(publication.inserted_at),
        completed_at: iso_datetime(publication.completed_at)
      }
    end)
  end

  defp iso_datetime(nil), do: nil
  defp iso_datetime(datetime), do: DateTime.to_iso8601(datetime)
end
