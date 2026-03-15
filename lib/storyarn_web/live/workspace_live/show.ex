defmodule StoryarnWeb.WorkspaceLive.Show do
  @moduledoc """
  LiveView for displaying a workspace dashboard with its projects.
  """
  use StoryarnWeb, :live_view
  use Gettext, backend: Storyarn.Gettext

  import StoryarnWeb.Components.UIComponents, only: [empty_state: 1]

  alias Storyarn.Billing
  alias Storyarn.Projects
  alias Storyarn.Workspaces

  @impl true
  def mount(%{"workspace_slug" => workspace_slug}, _session, socket) do
    scope = socket.assigns.current_scope

    case Workspaces.get_workspace_by_slug(scope, workspace_slug) do
      {:ok, workspace, membership} ->
        projects = Projects.list_projects_for_workspace(workspace.id, scope)
        can_create_project = Billing.can_create_project?(workspace) == :ok

        {:ok,
         socket
         |> assign(:page_title, workspace.name)
         |> assign(:workspace, workspace)
         |> assign(:current_workspace, workspace)
         |> assign(:membership, membership)
         |> assign(:all_projects, projects)
         |> assign(:projects, projects)
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
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      workspaces={@workspaces}
      current_workspace={@current_workspace}
    >
      <%!-- Workspace Banner --%>
      <header class="relative">
        <div class={[
          "h-48 overflow-hidden rounded-xl",
          !@workspace.banner_url && "bg-gradient-to-r from-primary/20 to-secondary/20"
        ]}>
          <img
            :if={@workspace.banner_url}
            src={@workspace.banner_url}
            alt=""
            class="w-full h-full object-cover"
          />
        </div>

        <div class="absolute bottom-0 left-0 right-0 p-6 bg-gradient-to-t from-base-100/90 to-transparent">
          <div class="flex items-end justify-between">
            <div>
              <h1 class="text-3xl font-bold">{@workspace.name}</h1>
              <p :if={@workspace.description} class="text-base-content/70 mt-1 max-w-2xl">
                {@workspace.description}
              </p>
            </div>
            <.link
              :if={@membership.role in ["owner", "admin"]}
              navigate={~p"/users/settings/workspaces/#{@workspace.slug}/general"}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="settings" class="size-4" />
            </.link>
          </div>
        </div>
      </header>

      <%!-- Toolbar --%>
      <div class="pt-4 pb-2 flex items-center justify-between">
        <div class="flex items-center gap-2">
          <input
            type="text"
            placeholder={dgettext("workspaces", "Search projects...")}
            class="input input-sm input-bordered w-64"
            phx-change="search"
            phx-debounce="300"
            name="search"
            value={@search_query}
          />
        </div>

        <.link
          :if={@membership.role in ["owner", "admin", "member"] and @can_create_project}
          patch={~p"/workspaces/#{@workspace.slug}/projects/new"}
          class="btn btn-primary btn-sm"
        >
          <.icon name="plus" class="size-4" />
          {dgettext("workspaces", "New Project")}
        </.link>
        <div
          :if={@membership.role in ["owner", "admin", "member"] and not @can_create_project}
          class="tooltip tooltip-left"
          data-tip={dgettext("workspaces", "Project limit reached for your plan")}
        >
          <button class="btn btn-primary btn-sm btn-disabled" disabled>
            <.icon name="plus" class="size-4" />
            {dgettext("workspaces", "New Project")}
          </button>
        </div>
      </div>

      <%!-- Projects Grid --%>
      <div class="pt-2">
        <div
          :if={@projects != []}
          class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
        >
          <.project_card
            :for={project_data <- @projects}
            project={project_data.project}
            workspace={@workspace}
          />
        </div>

        <.empty_state
          :if={@projects == [] and @search_query == ""}
          icon="folder-open"
          title={dgettext("workspaces", "No projects yet")}
        >
          {dgettext("workspaces", "Create your first project to get started")}
        </.empty_state>

        <.empty_state
          :if={@projects == [] and @search_query != ""}
          icon="search"
          title={dgettext("workspaces", "No projects found")}
        >
          {dgettext("workspaces", "Try a different search term")}
        </.empty_state>
      </div>

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
    </Layouts.app>
    """
  end

  attr :project, :map, required: true
  attr :workspace, :map, required: true

  defp project_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets"}
      class="card bg-base-200 hover:bg-base-300 transition-colors cursor-pointer"
    >
      <div class="card-body p-4">
        <div class="text-xs text-base-content/50">
          {Calendar.strftime(@project.inserted_at, "%b %d, %Y")}
        </div>

        <h3 class="card-title text-base">{@project.name}</h3>

        <p :if={@project.description} class="text-sm text-base-content/70 line-clamp-2">
          {@project.description}
        </p>

        <div class="flex items-center justify-between mt-2">
          <div class="avatar-group -space-x-2">
            <!-- TODO: Show project members avatars -->
          </div>
          <span class="text-xs text-base-content/50">
            {time_ago(@project.updated_at)}
          </span>
        </div>
      </div>
    </.link>
    """
  end

  defp time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> dgettext("workspaces", "just now")
      diff < 3600 -> dgettext("workspaces", "%{count} min ago", count: div(diff, 60))
      diff < 86_400 -> dgettext("workspaces", "%{count} hours ago", count: div(diff, 3600))
      true -> dgettext("workspaces", "%{count} days ago", count: div(diff, 86_400))
    end
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    filtered = filter_projects(socket.assigns.all_projects, query)
    {:noreply, assign(socket, projects: filtered, search_query: query)}
  end

  defp filter_projects(projects, query) when query in [nil, ""], do: projects

  defp filter_projects(projects, query) do
    downcased = String.downcase(query)

    Enum.filter(projects, fn %{project: project} ->
      String.contains?(String.downcase(project.name), downcased) or
        (project.description && String.contains?(String.downcase(project.description), downcased))
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
