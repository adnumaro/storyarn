defmodule StoryarnWeb.WorkspaceLive.New do
  @moduledoc """
  LiveView for creating a new workspace.
  """
  use StoryarnWeb, :live_view
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Workspaces

  @impl true
  def mount(_params, _session, socket) do
    changeset = Workspaces.change_new_workspace()

    {:ok,
     socket
     |> assign(:page_title, dgettext("workspaces", "New Workspace"))
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.WorkspaceLayout.workspace
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
    </StoryarnWeb.Components.WorkspaceLayout.workspace>
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

      {:error, :workspace_provisioning_failed} ->
        changeset =
          workspace_params
          |> Workspaces.change_new_workspace()
          |> Map.put(:action, :insert)

        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("workspaces", "We couldn't create your workspace. Please try again.")
         )
         |> assign(:form, to_form(changeset))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
