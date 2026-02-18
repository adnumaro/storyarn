defmodule StoryarnWeb.ScreenplayLive.Form do
  @moduledoc false

  use StoryarnWeb, :live_component

  alias Storyarn.Screenplays
  alias Storyarn.Screenplays.Screenplay

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.form
        for={@form}
        id="screenplay-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:name]}
          type="text"
          label={dgettext("screenplays", "Name")}
          placeholder={dgettext("screenplays", "Main Story")}
          required
        />
        <.input
          field={@form[:description]}
          type="textarea"
          label={dgettext("screenplays", "Description")}
          placeholder={dgettext("screenplays", "Describe the purpose of this screenplay...")}
          rows={3}
        />
        <div class="modal-action">
          <.link patch={@navigate} class="btn btn-ghost">
            {dgettext("screenplays", "Cancel")}
          </.link>
          <.button variant="primary" phx-disable-with={dgettext("screenplays", "Creating...")}>
            {dgettext("screenplays", "Create Screenplay")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    screenplay = Map.get(assigns, :screenplay, %Screenplay{})
    changeset = Screenplays.change_screenplay(screenplay)

    socket =
      socket
      |> assign(assigns)
      |> assign(:screenplay, screenplay)
      |> assign(:form, to_form(changeset))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"screenplay" => screenplay_params}, socket) do
    changeset =
      socket.assigns.screenplay
      |> Screenplays.change_screenplay(screenplay_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"screenplay" => screenplay_params}, socket) do
    case Screenplays.create_screenplay(socket.assigns.project, screenplay_params) do
      {:ok, screenplay} ->
        notify_parent({:saved, screenplay})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
