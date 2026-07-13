defmodule StoryarnWeb.WorkspaceLive.Show do
  @moduledoc """
  LiveView for displaying a workspace dashboard with its projects.
  """
  use StoryarnWeb, :live_view
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Billing
  alias Storyarn.ProductMetrics.Taxonomy
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates
  alias Storyarn.Workspaces
  alias StoryarnWeb.PrivateMedia

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    workspace = socket.assigns.workspace

    projects = Projects.list_projects_for_workspace(workspace.id, scope)
    can_create_project = can_create_project?(workspace, socket.assigns.membership)

    if connected?(socket) do
      ProjectTemplates.subscribe_workspace_installations(workspace)
    end

    {:ok,
     socket
     |> assign(:page_title, workspace.name)
     |> assign(:all_projects, projects)
     |> assign(:projects, format_projects(projects, workspace))
     |> assign(:search_query, "")
     |> assign(:can_create_project, can_create_project)
     |> assign(:new_project_modal_open, false)
     |> assign(:project_form, to_form(Projects.change_new_project(%Project{})))
     |> assign(:project_templates, serialize_project_templates(ProjectTemplates.list_templates(scope)))
     |> assign(
       :template_installations,
       serialize_template_installations(ProjectTemplates.list_active_workspace_installations(scope, workspace))
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.WorkspaceLayout.workspace
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      current_workspace={@current_workspace}
      workspaces={@workspaces}
      onboarding={@onboarding}
      onboarding_guide={:workspace}
      onboarding_autostart
    >
      <.vue
        v-component="live/workspace/dashboard/WorkspaceDashboard"
        v-socket={@socket}
        v-inject="workspace-layout"
        id="workspace-show"
        workspace={
          %{
            name: @workspace.name,
            description: @workspace.description,
            banner_url: PrivateMedia.workspace_banner_url(@workspace)
          }
        }
        class="container mx-auto h-dvw h-full"
        membership={%{role: @membership.role}}
        projects={@projects}
        search-query={@search_query}
        can-create-project={@can_create_project}
        new-project-modal-open={@new_project_modal_open}
        new-project-form={@project_form}
        template-creation={%{templates: @project_templates, installations: @template_installations}}
        project-metrics-options={Taxonomy.project_options()}
        settings-url={~p"/users/settings/workspaces/#{@workspace.slug}/general"}
      />
    </StoryarnWeb.Components.WorkspaceLayout.workspace>
    """
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    filtered = filter_projects(socket.assigns.all_projects, query)

    {:noreply,
     assign(socket,
       projects: format_projects(filtered, socket.assigns.workspace),
       search_query: query
     )}
  end

  def handle_event("set_new_project_modal_open", %{"open" => open}, socket) when is_boolean(open) do
    {:noreply, assign(socket, :new_project_modal_open, open)}
  end

  def handle_event("create_project", %{"project" => project_params}, socket) do
    project_params = Map.put(project_params, "workspace_id", socket.assigns.workspace.id)

    case Projects.create_project(socket.assigns.current_scope, project_params) do
      {:ok, project} ->
        socket =
          socket
          |> put_flash(:info, dgettext("workspaces", "Project created successfully."))
          |> push_navigate(to: ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{project.slug}")

        {:noreply, socket}

      {:error, :limit_reached, _details} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Project limit reached for your plan"))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Workspace not found."))}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("workspaces", "You don't have permission to create projects in this workspace.")
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :project_form, to_form(changeset))}
    end
  end

  def handle_event("create_project_from_template", template_params, socket) do
    with {:ok, template_id} <- parse_template_id(template_params["template_id"]),
         {:ok, template} <- fetch_template(socket.assigns.current_scope, template_id),
         %{current_version: version} when not is_nil(version) <- template,
         {:ok, installation} <-
           ProjectTemplates.request_template_instantiation(
             socket.assigns.current_scope,
             version,
             socket.assigns.workspace,
             Map.put(template_params, "source", "workspace_dashboard")
           ) do
      socket =
        socket
        |> assign(:new_project_modal_open, false)
        |> refresh_template_installations()
        |> put_flash(:info, dgettext("projects", "Template installation started."))

      {:reply, %{status: "queued", installation_id: installation.id}, socket}
    else
      {:error, :limit_reached, _details} ->
        {:reply, %{status: "error"},
         put_flash(socket, :error, dgettext("workspaces", "Project limit reached for your plan"))}

      _reason ->
        {:reply, %{status: "error"}, put_flash(socket, :error, dgettext("projects", "Template could not be installed."))}
    end
  end

  @impl true
  def handle_info({:project_template_installation_updated, installation}, socket) do
    socket = refresh_template_installations(socket)
    own_installation? = installation.user_id == socket.assigns.current_scope.user.id

    socket =
      case {installation.status, own_installation?} do
        {"completed", true} ->
          socket
          |> refresh_projects()
          |> put_flash(:info, dgettext("projects", "Your project is ready."))

        {"completed", false} ->
          refresh_projects(socket)

        {"failed", true} ->
          put_flash(
            socket,
            :error,
            dgettext("projects", "Template installation failed. Reference: %{reference}", reference: installation.id)
          )

        {_status, _own_installation?} ->
          socket
      end

    {:noreply, socket}
  end

  defp can_create_project?(workspace, membership) do
    Workspaces.can?(membership.role, :create_project) and Billing.can_create_project?(workspace) == :ok
  end

  defp parse_template_id(value) when is_integer(value), do: {:ok, value}

  defp parse_template_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> {:error, :invalid_template_id}
    end
  end

  defp parse_template_id(_value), do: {:error, :invalid_template_id}

  defp fetch_template(scope, template_id) do
    ProjectTemplates.get_template(scope, template_id)
  end

  defp filter_projects(projects, query) when query in [nil, ""], do: projects

  defp filter_projects(projects, query) do
    downcased = String.downcase(query)

    Enum.filter(projects, fn %{project: project} ->
      String.contains?(String.downcase(project.name), downcased) or
        (project.description && String.contains?(String.downcase(project.description), downcased))
    end)
  end

  defp format_projects(projects, workspace) do
    Enum.map(projects, fn %{project: project} ->
      %{
        project: %{
          id: project.id,
          name: project.name,
          description: project.description,
          inserted_at_formatted: Calendar.strftime(project.inserted_at, "%b %d, %Y"),
          updated_at: datetime_to_iso8601(project.last_activity_at || project.updated_at)
        },
        href: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}"
      }
    end)
  end

  defp refresh_projects(socket) do
    projects = Projects.list_projects_for_workspace(socket.assigns.workspace.id, socket.assigns.current_scope)
    filtered = filter_projects(projects, socket.assigns.search_query)

    socket
    |> assign(:all_projects, projects)
    |> assign(:projects, format_projects(filtered, socket.assigns.workspace))
  end

  defp refresh_template_installations(socket) do
    installations =
      ProjectTemplates.list_active_workspace_installations(
        socket.assigns.current_scope,
        socket.assigns.workspace
      )

    assign(socket, :template_installations, serialize_template_installations(installations))
  end

  defp serialize_template_installations(installations) do
    Enum.map(installations, fn installation ->
      %{
        id: installation.id,
        project_name: installation.project_name,
        status: installation.status,
        stage: installation.stage,
        template_version_id: installation.project_template_version_id,
        template_id: installation.project_template_version.project_template_id
      }
    end)
  end

  defp serialize_project_templates(templates) do
    Enum.map(templates, fn template ->
      %{
        id: template.id,
        name: template.name,
        description: template.description,
        visibility: template.visibility,
        version_number: version_number(template.current_version),
        entity_counts: entity_counts(template.current_version),
        project_type: preview_project_field(template.current_version, "project_type"),
        project_subtype: preview_project_field(template.current_version, "project_subtype")
      }
    end)
  end

  defp preview_project_field(%{preview: %{"project" => project}}, field) when is_map(project) do
    Map.get(project, field)
  end

  defp preview_project_field(_version, _field), do: nil

  defp version_number(%{version_number: version_number}), do: version_number
  defp version_number(_version), do: nil

  defp entity_counts(%{entity_counts: counts}) when is_map(counts), do: counts
  defp entity_counts(_version), do: %{}

  defp datetime_to_iso8601(nil), do: nil
  defp datetime_to_iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp datetime_to_iso8601(%NaiveDateTime{} = datetime) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end
end
