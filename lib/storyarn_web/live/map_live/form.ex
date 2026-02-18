defmodule StoryarnWeb.MapLive.Form do
  @moduledoc false

  use StoryarnWeb, :live_component

  alias Storyarn.Maps
  alias Storyarn.Maps.Map, as: MapSchema

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.form
        for={@form}
        id="map-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:name]}
          type="text"
          label={gettext("Name")}
          placeholder={gettext("World Map")}
          required
        />
        <.input
          field={@form[:description]}
          type="textarea"
          label={gettext("Description")}
          placeholder={gettext("Describe this map...")}
          rows={3}
        />
        <div class="modal-action">
          <.link patch={@navigate} class="btn btn-ghost">
            {gettext("Cancel")}
          </.link>
          <.button variant="primary" phx-disable-with={gettext("Creating...")}>
            {gettext("Create Map")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    map_record = Map.get(assigns, :map, %MapSchema{})
    changeset = Maps.change_map(map_record)

    socket =
      socket
      |> assign(assigns)
      |> assign(:map, map_record)
      |> assign(:form, to_form(changeset))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"map" => map_params}, socket) do
    changeset =
      socket.assigns.map
      |> Maps.change_map(map_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"map" => map_params}, socket) do
    if socket.assigns[:can_edit] == false do
      {:noreply, socket}
    else
      case Maps.create_map(socket.assigns.project, map_params) do
        {:ok, map} ->
          notify_parent({:saved, map})
          {:noreply, socket}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
