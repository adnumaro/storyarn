defmodule StoryarnWeb.SettingsLive.WorkspaceGeneral do
  @moduledoc """
  LiveView for workspace general settings.
  """
  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Localization
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
           |> assign(:page_title, dgettext("workspaces", "Workspace Settings"))
           |> assign(:current_path, ~p"/users/settings/workspaces/#{slug}/general")
           |> assign(:workspace, workspace)
           |> assign(:membership, membership)
           |> assign(:form, to_form(changeset))}
        else
          {:ok,
           socket
           |> put_flash(
             :error,
             dgettext("workspaces", "You don't have permission to manage this workspace.")
           )
           |> push_navigate(to: ~p"/users/settings")}
        end

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("workspaces", "Workspace not found."))
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
      <:title>{dgettext("workspaces", "General")}</:title>
      <:subtitle>
        {dgettext("workspaces", "Manage workspace details for %{name}", name: @workspace.name)}
      </:subtitle>

      <div class="space-y-8">
        <section>
          <.form for={@form} phx-submit="save" phx-change="validate" class="space-y-4">
            <.input
              field={@form[:name]}
              type="text"
              label={dgettext("workspaces", "Workspace name")}
              required
            />

            <.input
              field={@form[:description]}
              type="textarea"
              label={dgettext("workspaces", "Description")}
            />

            <.input
              field={@form[:banner_url]}
              type="text"
              label={dgettext("workspaces", "Banner URL")}
              placeholder="https://example.com/banner.jpg"
            />

            <.input
              field={@form[:source_locale]}
              type="select"
              label={dgettext("workspaces", "Source language")}
              options={Localization.language_options_for_select()}
              prompt={dgettext("workspaces", "Select language...")}
            />
            <p class="text-xs opacity-60 -mt-2 mb-2">
              {dgettext("workspaces", "Default source language for new projects in this workspace.")}
            </p>

            <div class="flex justify-end">
              <.button
                type="submit"
                variant="primary"
                phx-disable-with={dgettext("workspaces", "Saving...")}
              >
                {dgettext("workspaces", "Save Changes")}
              </.button>
            </div>
          </.form>
        </section>

        <div class="divider" />

        <section :if={@membership.role == "owner"}>
          <h3 class="text-lg font-semibold mb-4 text-error">
            {dgettext("workspaces", "Danger Zone")}
          </h3>

          <div class="border border-error/30 rounded-lg p-4">
            <p class="text-sm text-base-content/70 mb-4">
              {dgettext(
                "workspaces",
                "Once you delete a workspace, there is no going back. All projects will be deleted."
              )}
            </p>
            <button
              type="button"
              phx-click={show_modal("delete-workspace-confirm")}
              class="btn btn-error btn-sm"
            >
              {dgettext("workspaces", "Delete Workspace")}
            </button>
          </div>
        </section>
      </div>

      <.confirm_modal
        id="delete-workspace-confirm"
        title={dgettext("workspaces", "Delete workspace?")}
        message={dgettext("workspaces", "This action cannot be undone.")}
        confirm_text={dgettext("workspaces", "Delete")}
        confirm_variant="error"
        icon="alert-triangle"
        on_confirm={JS.push("delete")}
      />
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
    with_authorization(socket, :manage_workspace, fn socket ->
      case Workspaces.update_workspace(socket.assigns.workspace, workspace_params) do
        {:ok, workspace} ->
          {:noreply,
           socket
           |> assign(:workspace, workspace)
           |> assign(:form, to_form(Workspaces.change_workspace(workspace)))
           |> put_flash(:info, dgettext("workspaces", "Workspace updated successfully."))}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    end)
  end

  @impl true
  def handle_event("delete", _params, socket) do
    # Only owner can delete workspace
    if socket.assigns.membership.role == "owner" do
      case Workspaces.delete_workspace(socket.assigns.workspace) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("workspaces", "Workspace deleted."))
           |> push_navigate(to: ~p"/users/settings")}

        {:error, _} ->
          {:noreply,
           put_flash(socket, :error, dgettext("workspaces", "Failed to delete workspace."))}
      end
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("workspaces", "Only the workspace owner can delete the workspace.")
       )}
    end
  end
end
