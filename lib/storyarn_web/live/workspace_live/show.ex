defmodule StoryarnWeb.WorkspaceLive.Show do
  @moduledoc """
  LiveView for displaying a workspace dashboard with its projects.
  """
  use StoryarnWeb, :live_view
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Projects
  alias Storyarn.Workspaces

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope

    case Workspaces.get_workspace_by_slug(scope, slug) do
      {:ok, workspace, membership} ->
        projects = Projects.list_projects_for_workspace(workspace.id, scope)

        {:ok,
         socket
         |> assign(:page_title, workspace.name)
         |> assign(:workspace, workspace)
         |> assign(:current_workspace, workspace)
         |> assign(:membership, membership)
         |> assign(:projects, projects)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Workspace not found."))
         |> push_navigate(to: ~p"/workspaces")}
    end
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
      <div>
        <!-- Workspace Header -->
        <header class="relative">
          <div class={[
            "h-48 overflow-hidden",
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
                navigate={~p"/workspaces/#{@workspace.slug}/settings"}
                class="btn btn-ghost btn-sm"
              >
                <.icon name="hero-cog-6-tooth" class="size-4" />
              </.link>
            </div>
          </div>
        </header>
        
    <!-- Toolbar -->
        <div class="p-4 flex items-center justify-between border-b border-base-300">
          <div class="flex items-center gap-2">
            <div class="form-control">
              <input
                type="text"
                placeholder={gettext("Search projects...")}
                class="input input-sm input-bordered w-64"
                phx-change="search"
                phx-debounce="300"
                name="search"
              />
            </div>
          </div>

          <.link
            :if={@membership.role in ["owner", "admin", "member"]}
            navigate={~p"/projects/new?workspace=#{@workspace.slug}"}
            class="btn btn-primary btn-sm"
          >
            <.icon name="hero-plus" class="size-4" />
            {gettext("New Project")}
          </.link>
        </div>
        
    <!-- Projects Grid -->
        <div class="p-4">
          <div
            :if={@projects != []}
            class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4"
          >
            <.project_card :for={project_data <- @projects} project={project_data.project} />
          </div>

          <div :if={@projects == []} class="text-center py-12 text-base-content/50">
            <.icon name="hero-folder-open" class="size-12 mx-auto mb-4" />
            <p>{gettext("No projects yet")}</p>
            <p class="text-sm">{gettext("Create your first project to get started")}</p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp project_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/projects/#{@project.id}"}
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
      diff < 60 -> gettext("just now")
      diff < 3600 -> gettext("%{count} min ago", count: div(diff, 60))
      diff < 86_400 -> gettext("%{count} hours ago", count: div(diff, 3600))
      true -> gettext("%{count} days ago", count: div(diff, 86_400))
    end
  end

  @impl true
  def handle_event("search", %{"search" => _query}, socket) do
    # TODO: Implement search
    {:noreply, socket}
  end
end
