defmodule StoryarnWeb.ProjectLive.Form do
  @moduledoc false

  use StoryarnWeb, :live_component

  alias Storyarn.Projects
  alias Storyarn.Projects.Project

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.vue
        v-component="project/ProjectForm"
        v-socket={@socket}
        id="project-form-vue"
        form={@form}
        title={@title}
        submit-label={if @action == :new, do: dgettext("projects", "Create Project"), else: dgettext("projects", "Save")}
        cancel-url={@navigate}
      />
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    project = Map.get(assigns, :project, %Project{})
    changeset = Projects.change_project(project)

    socket =
      socket
      |> assign(assigns)
      |> assign(:project, project)
      |> assign(:form, to_form(changeset))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"project" => project_params}, socket) do
    changeset =
      socket.assigns.project
      |> Projects.change_project(project_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"project" => project_params}, socket) do
    case socket.assigns.action do
      :new -> create_project(socket, project_params)
      :edit -> update_project(socket, project_params)
    end
  end

  defp create_project(socket, project_params) do
    project_params =
      if workspace = socket.assigns[:workspace] do
        Map.put(project_params, "workspace_id", workspace.id)
      else
        project_params
      end

    case Projects.create_project(socket.assigns.current_scope, project_params) do
      {:ok, project} ->
        notify_parent({:saved, project})
        {:noreply, socket}

      {:error, :limit_reached, _details} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("workspaces", "Project limit reached for your plan"))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp update_project(socket, project_params) do
    case Projects.update_project(socket.assigns.project, project_params) do
      {:ok, project} ->
        notify_parent({:saved, project})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
