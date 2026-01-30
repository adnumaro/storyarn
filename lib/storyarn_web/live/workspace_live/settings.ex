defmodule StoryarnWeb.WorkspaceLive.Settings do
  @moduledoc """
  LiveView for workspace settings.
  """
  use StoryarnWeb, :live_view
  use Gettext, backend: StoryarnWeb.Gettext

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
           |> assign(:workspace, workspace)
           |> assign(:current_workspace, workspace)
           |> assign(:membership, membership)
           |> assign(:form, to_form(changeset))}
        else
          {:ok,
           socket
           |> put_flash(:error, gettext("You don't have permission to manage this workspace."))
           |> push_navigate(to: ~p"/workspaces/#{slug}")}
        end

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Workspace not found."))
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      workspaces={@workspaces}
      current_workspace={@current_workspace}
    >
      <div class="max-w-2xl mx-auto py-8">
        <.link
          navigate={~p"/workspaces/#{@workspace.slug}"}
          class="text-sm text-base-content/70 hover:text-base-content mb-4 inline-flex items-center gap-1"
        >
          <.icon name="hero-arrow-left" class="size-4" />
          {gettext("Back to workspace")}
        </.link>

        <.header>
          {gettext("Workspace Settings")}
          <:subtitle>
            {gettext("Manage your workspace details")}
          </:subtitle>
        </.header>

        <div class="divider"></div>

        <section class="mb-8">
          <h3 class="text-lg font-semibold mb-4">{gettext("General")}</h3>

          <.form for={@form} phx-submit="save" class="space-y-4">
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
              <.button type="submit" phx-disable-with={gettext("Saving...")}>
                {gettext("Save Changes")}
              </.button>
            </div>
          </.form>
        </section>

        <div class="divider"></div>

        <section :if={@membership.role == "owner"} class="mb-8">
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
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("save", %{"workspace" => workspace_params}, socket) do
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
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case Workspaces.delete_workspace(socket.assigns.workspace) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Workspace deleted."))
         |> push_navigate(to: ~p"/workspaces")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete workspace."))}
    end
  end
end
