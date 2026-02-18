defmodule StoryarnWeb.MapLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Maps
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      maps_tree={@maps_tree}
      active_tool={:maps}
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps"}
      can_edit={@can_edit}
    >
      <div class="max-w-4xl mx-auto">
        <.header>
          {gettext("Maps")}
          <:subtitle>
            {gettext("Create maps to visualize your world")}
          </:subtitle>
          <:actions :if={@can_edit}>
            <.link
              patch={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps/new"}
              class="btn btn-primary"
            >
              <.icon name="plus" class="size-4 mr-2" />
              {gettext("New Map")}
            </.link>
          </:actions>
        </.header>

        <.empty_state :if={@maps == []} icon="map">
          {gettext("No maps yet. Create your first map to get started.")}
        </.empty_state>

        <div :if={@maps != []} class="mt-6 space-y-2">
          <.map_card
            :for={map <- @maps}
            map={map}
            project={@project}
            workspace={@workspace}
            can_edit={@can_edit}
          />
        </div>

        <.modal
          :if={@live_action == :new and @can_edit}
          id="new-map-modal"
          show
          on_cancel={JS.patch(~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps")}
        >
          <.live_component
            module={StoryarnWeb.MapLive.Form}
            id="new-map-form"
            project={@project}
            title={gettext("New Map")}
            navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps"}
          />
        </.modal>

        <.confirm_modal
          :if={@can_edit}
          id="delete-map-confirm"
          title={gettext("Delete map?")}
          message={gettext("Are you sure you want to delete this map?")}
          confirm_text={gettext("Delete")}
          confirm_variant="error"
          icon="alert-triangle"
          on_confirm={JS.push("confirm_delete")}
        />
      </div>
    </Layouts.project>
    """
  end

  attr :map, :map, required: true
  attr :project, :map, required: true
  attr :workspace, :map, required: true
  attr :can_edit, :boolean, default: false

  defp map_card(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md transition-shadow">
      <div class="card-body p-4">
        <div class="flex items-center justify-between">
          <.link
            navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps/#{@map.id}"}
            class="flex items-center gap-3 flex-1 min-w-0"
          >
            <div class="rounded-lg bg-primary/10 p-2">
              <.icon name="map" class="size-5 text-primary" />
            </div>
            <div class="flex-1 min-w-0">
              <h3 class="font-medium truncate flex items-center gap-2">
                {@map.name}
                <span
                  :if={@map.shortcut}
                  class="badge badge-ghost badge-xs font-mono"
                  title={gettext("Shortcut")}
                >
                  #{@map.shortcut}
                </span>
              </h3>
              <p :if={@map.description} class="text-sm text-base-content/60 truncate">
                {@map.description}
              </p>
            </div>
          </.link>
          <div :if={@can_edit} class="dropdown dropdown-end">
            <button
              type="button"
              tabindex="0"
              class="btn btn-ghost btn-sm btn-square"
              onclick="event.stopPropagation();"
            >
              <.icon name="more-horizontal" class="size-4" />
            </button>
            <ul
              tabindex="0"
              class="dropdown-content menu menu-sm bg-base-100 rounded-box shadow-lg border border-base-300 w-40 z-50"
            >
              <li>
                <button
                  type="button"
                  class="text-error"
                  phx-click={
                    JS.push("set_pending_delete", value: %{id: @map.id})
                    |> show_modal("delete-map-confirm")
                  }
                  onclick="event.stopPropagation();"
                >
                  <.icon name="trash-2" class="size-4" />
                  {gettext("Delete")}
                </button>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        project = Repo.preload(project, :workspace)
        maps = Maps.list_maps(project.id)
        maps_tree = Maps.list_maps_tree(project.id)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:maps, maps)
          |> assign(:maps_tree, maps_tree)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({StoryarnWeb.MapLive.Form, {:saved, map}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, gettext("Map created successfully."))
     |> push_navigate(
       to:
         ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{map.id}"
     )}
  end

  @impl true
  def handle_event("set_pending_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event("confirm_delete", _params, socket) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => map_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_map(socket.assigns.project.id, map_id) do
          nil -> {:noreply, put_flash(socket, :error, gettext("Map not found."))}
          map -> do_delete_map(socket, map)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("create_map", _params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.create_map(socket.assigns.project, %{name: gettext("Untitled")}) do
          {:ok, new_map} ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{new_map.id}"
             )}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not create map."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("create_child_map", %{"parent-id" => parent_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        attrs = %{name: gettext("Untitled"), parent_id: parent_id}

        case Maps.create_map(socket.assigns.project, attrs) do
          {:ok, new_map} ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{new_map.id}"
             )}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not create map."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_map(socket.assigns.project.id, item_id) do
          nil -> {:noreply, put_flash(socket, :error, gettext("Map not found."))}
          map -> do_move_map(socket, map, new_parent_id, position)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  defp do_delete_map(socket, map) do
    case Maps.delete_map(map) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Map moved to trash."))
         |> reload_maps()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete map."))}
    end
  end

  defp do_move_map(socket, map, new_parent_id, position) do
    new_parent_id = MapUtils.parse_int(new_parent_id)
    position = MapUtils.parse_int(position) || 0

    case Maps.move_map_to_position(map, new_parent_id, position) do
      {:ok, _} -> {:noreply, reload_maps(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not move map."))}
    end
  end

  defp reload_maps(socket) do
    project_id = socket.assigns.project.id

    socket
    |> assign(:maps, Maps.list_maps(project_id))
    |> assign(:maps_tree, Maps.list_maps_tree(project_id))
  end
end
