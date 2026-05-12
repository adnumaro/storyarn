defmodule StoryarnWeb.WorkspaceLive.New do
  @moduledoc """
  LiveView for creating a new workspace.
  """
  use StoryarnWeb, :live_view
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace

  @impl true
  def mount(_params, _session, socket) do
    changeset = Workspaces.change_workspace(%Workspace{})

    {:ok,
     socket
     |> assign(:page_title, dgettext("workspaces", "New Workspace"))
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.workspace
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      workspaces={@workspaces}
    >
      <.vue
        v-component="live/workspace/form/WorkspaceNewWorkspaceForm"
        v-socket={@socket}
        v-inject="workspace-layout"
        id="workspace-new"
        form={@form}
        cancel-url={~p"/workspaces"}
      />
    </Layouts.workspace>
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
         |> put_flash(:info, dgettext("workspaces", "Workspace created successfully."))
         |> push_navigate(to: ~p"/workspaces/#{workspace.slug}")}

      {:error, :limit_reached, _details} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("workspaces", "You have reached the workspace limit for your plan.")
         )
         |> push_navigate(to: ~p"/workspaces")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
