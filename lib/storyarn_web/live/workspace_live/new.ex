defmodule StoryarnWeb.WorkspaceLive.New do
  @moduledoc """
  LiveView for creating a new workspace.
  """
  use StoryarnWeb, :live_view
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace

  @impl true
  def mount(_params, _session, socket) do
    changeset = Workspaces.change_workspace(%Workspace{})

    {:ok,
     socket
     |> assign(:page_title, gettext("New Workspace"))
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} workspaces={@workspaces}>
      <div class="max-w-lg mx-auto py-8">
        <.header>
          {gettext("Create a new workspace")}
          <:subtitle>
            {gettext("Workspaces help you organize projects for different teams or purposes.")}
          </:subtitle>
        </.header>

        <.form for={@form} phx-submit="save" class="mt-8 space-y-4">
          <.input
            field={@form[:name]}
            type="text"
            label={gettext("Workspace name")}
            placeholder={gettext("My Workspace")}
            required
          />

          <.input
            field={@form[:description]}
            type="textarea"
            label={gettext("Description")}
            placeholder={gettext("What is this workspace for?")}
          />

          <div class="flex justify-end gap-2 pt-4">
            <.link navigate={~p"/workspaces"} class="btn btn-ghost">
              {gettext("Cancel")}
            </.link>
            <.button type="submit" phx-disable-with={gettext("Creating...")}>
              {gettext("Create Workspace")}
            </.button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("save", %{"workspace" => workspace_params}, socket) do
    scope = socket.assigns.current_scope

    # Generate slug from name
    slug = Workspaces.generate_slug(workspace_params["name"] || "workspace")
    workspace_params = Map.put(workspace_params, "slug", slug)

    case Workspaces.create_workspace(scope, workspace_params) do
      {:ok, workspace} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Workspace created successfully."))
         |> push_navigate(to: ~p"/workspaces/#{workspace.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
