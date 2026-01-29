defmodule StoryarnWeb.ProjectLive.Dashboard do
  use StoryarnWeb, :live_view

  alias Storyarn.Projects

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center mb-8">
        <.header>
          {gettext("Projects")}
          <:subtitle>
            {gettext("Manage your narrative projects")}
          </:subtitle>
          <:actions>
            <.link patch={~p"/projects/new"} class="btn btn-primary">
              <.icon name="hero-plus" class="size-4 mr-2" />
              {gettext("New Project")}
            </.link>
          </:actions>
        </.header>
      </div>

      <div :if={@projects == []} class="text-center py-12">
        <.icon name="hero-folder" class="size-12 mx-auto text-base-content/30 mb-4" />
        <p class="text-base-content/70">
          {gettext("No projects yet. Create your first project to get started.")}
        </p>
      </div>

      <div :if={@projects != []} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <.project_card
          :for={%{project: project, role: role} <- @projects}
          project={project}
          role={role}
        />
      </div>

      <.modal
        :if={@live_action == :new}
        id="new-project-modal"
        show
        on_cancel={JS.patch(~p"/projects")}
      >
        <.live_component
          module={StoryarnWeb.ProjectLive.Form}
          id="new-project-form"
          current_scope={@current_scope}
          title={gettext("New Project")}
          action={:new}
          navigate={~p"/projects"}
        />
      </.modal>
    </Layouts.app>
    """
  end

  attr :project, :map, required: true
  attr :role, :string, required: true

  defp project_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/projects/#{@project.id}"}
      class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md transition-shadow"
    >
      <div class="card-body">
        <div class="flex items-start justify-between gap-2">
          <h3 class="card-title text-lg">{@project.name}</h3>
          <.role_badge role={@role} />
        </div>
        <p :if={@project.description} class="text-sm text-base-content/70 line-clamp-2">
          {@project.description}
        </p>
        <p :if={!@project.description} class="text-sm text-base-content/50 italic">
          {gettext("No description")}
        </p>
        <div class="card-actions justify-end mt-2">
          <span class="text-xs text-base-content/50">
            {gettext("Updated")} {Calendar.strftime(@project.updated_at, "%b %d, %Y")}
          </span>
        </div>
      </div>
    </.link>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    projects = Projects.list_projects(socket.assigns.current_scope)
    {:ok, assign(socket, projects: projects)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({StoryarnWeb.ProjectLive.Form, {:saved, project}}, socket) do
    socket =
      socket
      |> put_flash(:info, gettext("Project created successfully."))
      |> push_navigate(to: ~p"/projects/#{project.id}")

    {:noreply, socket}
  end
end
