defmodule StoryarnWeb.ProjectLive.Form do
  use StoryarnWeb, :live_component

  alias Storyarn.Projects
  alias Storyarn.Projects.Project

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.form
        for={@form}
        id="project-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:name]}
          type="text"
          label={gettext("Project Name")}
          placeholder={gettext("My Narrative Project")}
          required
        />
        <.input
          field={@form[:description]}
          type="textarea"
          label={gettext("Description")}
          placeholder={gettext("A brief description of your project")}
          rows={3}
        />
        <div class="modal-action">
          <.link patch={@navigate} class="btn btn-ghost">
            {gettext("Cancel")}
          </.link>
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Create Project")}
          </.button>
        </div>
      </.form>
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
    case Projects.create_project(socket.assigns.current_scope, project_params) do
      {:ok, project} ->
        notify_parent({:saved, project})
        {:noreply, socket}

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
