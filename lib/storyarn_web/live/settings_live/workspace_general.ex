defmodule StoryarnWeb.SettingsLive.WorkspaceGeneral do
  @moduledoc """
  LiveView for workspace general settings.
  """
  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Workspaces

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope

    case Workspaces.get_workspace_by_slug(scope, slug) do
      {:ok, workspace, membership} ->
        if membership.role in ["owner", "admin"] do
          changeset = Workspaces.change_workspace(workspace)

          {:ok,
           socket
           |> assign(:page_title, gettext("Workspace Settings"))
           |> assign(:current_path, ~p"/users/settings/workspaces/#{slug}/general")
           |> assign(:workspace, workspace)
           |> assign(:membership, membership)
           |> assign(:form, to_form(changeset))}
        else
          {:ok,
           socket
           |> put_flash(:error, gettext("You don't have permission to manage this workspace."))
           |> push_navigate(to: ~p"/users/settings")}
        end

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Workspace not found."))
         |> push_navigate(to: ~p"/users/settings")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      flash={@flash}
      current_scope={@current_scope}
      workspaces={@workspaces}
      current_path={@current_path}
    >
      <:title>{gettext("General")}</:title>
      <:subtitle>
        {gettext("Manage workspace details for %{name}", name: @workspace.name)}
      </:subtitle>

      <div class="space-y-8">
        <section>
          <.form for={@form} phx-submit="save" phx-change="validate" class="space-y-4">
            <.input
              field={@form[:name]}
              type="text"
              label={gettext("Workspace name")}
              required
            />

            <.input
              field={@form[:description]}
              type="textarea"
              label={gettext("Description")}
            />

            <.input
              field={@form[:banner_url]}
              type="text"
              label={gettext("Banner URL")}
              placeholder="https://example.com/banner.jpg"
            />

            <div class="flex justify-end">
              <.button type="submit" variant="primary" phx-disable-with={gettext("Saving...")}>
                {gettext("Save Changes")}
              </.button>
            </div>
          </.form>
        </section>

        <div class="divider" />

        <section :if={@membership.role == "owner"}>
          <h3 class="text-lg font-semibold mb-4 text-error">{gettext("Danger Zone")}</h3>

          <div class="border border-error/30 rounded-lg p-4">
            <p class="text-sm text-base-content/70 mb-4">
              {gettext(
                "Once you delete a workspace, there is no going back. All projects will be deleted."
              )}
            </p>
            <button
              type="button"
              phx-click="delete"
              data-confirm={
                gettext(
                  "Are you sure you want to delete this workspace? This action cannot be undone."
                )
              }
              class="btn btn-error btn-sm"
            >
              {gettext("Delete Workspace")}
            </button>
          </div>
        </section>
      </div>
    </Layouts.settings>
    """
  end

  @impl true
  def handle_event("validate", %{"workspace" => workspace_params}, socket) do
    changeset =
      socket.assigns.workspace
      |> Workspaces.change_workspace(workspace_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"workspace" => workspace_params}, socket) do
    case authorize(socket, :manage_workspace) do
      :ok ->
        case Workspaces.update_workspace(socket.assigns.workspace, workspace_params) do
          {:ok, workspace} ->
            {:noreply,
             socket
             |> assign(:workspace, workspace)
             |> assign(:form, to_form(Workspaces.change_workspace(workspace)))
             |> put_flash(:info, gettext("Workspace updated successfully."))}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    # Only owner can delete workspace
    if socket.assigns.membership.role == "owner" do
      case Workspaces.delete_workspace(socket.assigns.workspace) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Workspace deleted."))
           |> push_navigate(to: ~p"/users/settings")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Failed to delete workspace."))}
      end
    else
      {:noreply,
       put_flash(socket, :error, gettext("Only the workspace owner can delete the workspace."))}
    end
  end
end
