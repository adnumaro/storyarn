defmodule StoryarnWeb.FlowLive.Form do
  @moduledoc false

  use StoryarnWeb, :live_component

  alias Storyarn.Flows
  alias Storyarn.Flows.Flow

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.form
        for={@form}
        id="flow-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:name]}
          type="text"
          label={gettext("Name")}
          placeholder={gettext("Main Story")}
          required
        />
        <.input
          field={@form[:description]}
          type="textarea"
          label={gettext("Description")}
          placeholder={gettext("Describe the purpose of this flow...")}
          rows={3}
        />
        <div class="modal-action">
          <.link patch={@navigate} class="btn btn-ghost">
            {gettext("Cancel")}
          </.link>
          <.button variant="primary" phx-disable-with={gettext("Creating...")}>
            {gettext("Create Flow")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    flow = Map.get(assigns, :flow, %Flow{})
    changeset = Flows.change_flow(flow)

    socket =
      socket
      |> assign(assigns)
      |> assign(:flow, flow)
      |> assign(:form, to_form(changeset))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"flow" => flow_params}, socket) do
    changeset =
      socket.assigns.flow
      |> Flows.change_flow(flow_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"flow" => flow_params}, socket) do
    case Flows.create_flow(socket.assigns.project, flow_params) do
      {:ok, flow} ->
        notify_parent({:saved, flow})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
