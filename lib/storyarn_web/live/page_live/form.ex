defmodule StoryarnWeb.PageLive.Form do
  @moduledoc false

  use StoryarnWeb, :live_component

  alias Storyarn.Pages
  alias Storyarn.Pages.Page

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.form
        for={@form}
        id="page-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:name]}
          type="text"
          label={gettext("Name")}
          placeholder={gettext("My Page")}
          required
          autofocus
        />
        <.input
          field={@form[:icon]}
          type="text"
          label={gettext("Icon")}
          placeholder="page"
        />
        <.input
          :if={@parent_options != []}
          field={@form[:parent_id]}
          type="select"
          label={gettext("Parent")}
          options={@parent_options}
          prompt={gettext("No parent (root level)")}
        />

        <div class="modal-action">
          <.link patch={@navigate} class="btn btn-ghost">
            {gettext("Cancel")}
          </.link>
          <.button variant="primary" phx-disable-with={gettext("Creating...")}>
            {gettext("Create Page")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    page = Map.get(assigns, :page, %Page{})
    changeset = Pages.change_page(page)

    socket =
      socket
      |> assign(assigns)
      |> assign(:page, page)
      |> assign(:form, to_form(changeset))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"page" => page_params}, socket) do
    changeset =
      socket.assigns.page
      |> Pages.change_page(page_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"page" => page_params}, socket) do
    case Pages.create_page(socket.assigns.project, page_params) do
      {:ok, page} ->
        notify_parent({:saved, page})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
