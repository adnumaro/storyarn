defmodule StoryarnWeb.WorkspaceLive.Show do
  @moduledoc """
  LiveView for displaying a workspace dashboard with its projects.
  """
  use StoryarnWeb, :live_view
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Billing
  alias Storyarn.Projects
  alias Storyarn.Workspaces

  @impl true
  def mount(%{"workspace_slug" => workspace_slug}, _session, socket) do
    scope = socket.assigns.current_scope

    case Workspaces.get_workspace_by_slug(scope, workspace_slug) do
      {:ok, workspace, membership} ->
        projects = Projects.list_projects_for_workspace(workspace.id, scope)
        workspaces = Workspaces.list_workspaces_for_user(scope.user)
        can_create_project = Billing.can_create_project?(workspace) == :ok

        {:ok,
         socket
         |> assign(:page_title, workspace.name)
         |> assign(:workspace, workspace)
         |> assign(:workspaces, workspaces)
         |> assign(:current_workspace, workspace)
         |> assign(:membership, membership)
         |> assign(:all_projects, projects)
         |> assign(:projects, format_projects(projects, workspace))
         |> assign(:search_query, "")
         |> assign(:can_create_project, can_create_project)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("workspaces", "Workspace not found."))
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
  end

  defp apply_action(socket, :new_project, _params) do
    socket
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.workspace
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      current_workspace={@current_workspace}
      workspaces={@workspaces}
    >
      <.vue
        v-component="pages/workspaces/index"
        v-socket={@socket}
        id="workspace-show"
        workspace={
          %{
            name: @workspace.name,
            description: @workspace.description,
            banner_url: @workspace.banner_url
          }
        }
        class="container mx-auto"
        membership={%{role: @membership.role}}
        projects={@projects}
        search-query={@search_query}
        can-create-project={@can_create_project}
        new-project-url={~p"/workspaces/#{@workspace.slug}/projects/new"}
        settings-url={~p"/users/settings/workspaces/#{@workspace.slug}/general"}
      />

      <.modal
        :if={@live_action == :new_project}
        id="new-project-modal"
        show
        on_cancel={JS.patch(~p"/workspaces/#{@workspace.slug}")}
      >
        <.live_component
          module={StoryarnWeb.ProjectLive.Form}
          id="new-project-form"
          current_scope={@current_scope}
          workspace={@workspace}
          title={dgettext("workspaces", "New Project")}
          action={:new}
          navigate={~p"/workspaces/#{@workspace.slug}"}
        />
      </.modal>
    </Layouts.workspace>
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
          updated_at: project.updated_at && DateTime.to_iso8601(project.updated_at)
        },
        href: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets"
      }
    end)
  end

  @impl true
  def handle_info({StoryarnWeb.ProjectLive.Form, {:saved, project}}, socket) do
    socket =
      socket
      |> put_flash(:info, dgettext("workspaces", "Project created successfully."))
      |> push_navigate(
        to: ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{project.slug}/sheets"
      )

    {:noreply, socket}
  end
end
