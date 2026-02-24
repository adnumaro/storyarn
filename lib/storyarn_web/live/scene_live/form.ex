defmodule StoryarnWeb.SceneLive.Form do
  @moduledoc false

  use StoryarnWeb, :live_component

  alias Storyarn.Scenes
  alias Storyarn.Scenes.Scene

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.form
        for={@form}
        id="scene-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:name]}
          type="text"
          label={dgettext("scenes", "Name")}
          placeholder={dgettext("scenes", "World Map")}
          required
        />
        <.input
          field={@form[:description]}
          type="textarea"
          label={dgettext("scenes", "Description")}
          placeholder={dgettext("scenes", "Describe this scene...")}
          rows={3}
        />
        <div class="modal-action">
          <.link patch={@navigate} class="btn btn-ghost">
            {dgettext("scenes", "Cancel")}
          </.link>
          <.button variant="primary" phx-disable-with={dgettext("scenes", "Creating...")}>
            {dgettext("scenes", "Create Scene")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    scene_record = Map.get(assigns, :scene, %Scene{})
    changeset = Scenes.change_scene(scene_record)

    socket =
      socket
      |> assign(assigns)
      |> assign(:scene, scene_record)
      |> assign(:form, to_form(changeset))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"scene" => scene_params}, socket) do
    changeset =
      socket.assigns.scene
      |> Scenes.change_scene(scene_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"scene" => scene_params}, socket) do
    if socket.assigns[:can_edit] == false do
      {:noreply, socket}
    else
      case Scenes.create_scene(socket.assigns.project, scene_params) do
        {:ok, scene} ->
          notify_parent({:saved, scene})
          {:noreply, socket}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
