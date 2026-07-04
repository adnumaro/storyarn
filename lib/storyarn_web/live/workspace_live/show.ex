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

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    workspace = socket.assigns.workspace

    projects = Projects.list_projects_for_workspace(workspace.id, scope)
    can_create_project = can_create_project?(workspace, socket.assigns.membership)

    {:ok,
     socket
     |> assign(:page_title, workspace.name)
     |> assign(:all_projects, projects)
     |> assign(:projects, format_projects(projects, workspace))
     |> assign(:search_query, "")
     |> assign(:can_create_project, can_create_project)
     |> assign(:project_form, to_form(Projects.change_new_project(%Project{})))
     |> assign(:project_templates, serialize_project_templates(ProjectTemplates.list_templates(scope)))
     |> assign(:new_project_modal_open, false)}
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
            banner_url: @workspace.banner_url
          }
        }
        class="container mx-auto h-dvw h-full"
        membership={%{role: @membership.role}}
        projects={@projects}
        search-query={@search_query}
        can-create-project={@can_create_project}
        new-project-form={@project_form}
        new-project-modal-open={@new_project_modal_open}
        project-templates={@project_templates}
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

  def handle_event("set_new_project_modal_open", %{"open" => open}, socket) do
    {:noreply, assign(socket, :new_project_modal_open, open in [true, "true"])}
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
         {:ok, project} <-
           ProjectTemplates.instantiate_template(
             socket.assigns.current_scope,
             version,
             socket.assigns.workspace,
             template_params
           ) do
      socket =
        socket
        |> put_flash(:info, dgettext("workspaces", "Project created successfully."))
        |> push_navigate(to: ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{project.slug}")

      {:noreply, socket}
    else
      {:error, :limit_reached, _details} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Project limit reached for your plan"))}

      _reason ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Template could not be installed."))}
    end
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
    {:ok, ProjectTemplates.get_template!(scope, template_id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
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

  defp serialize_project_templates(templates) do
    Enum.map(templates, fn template ->
      %{
        id: template.id,
        name: template.name,
        description: template.description,
        visibility: template.visibility,
        version_number: version_number(template.current_version),
        entity_counts: entity_counts(template.current_version)
      }
    end)
  end

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
