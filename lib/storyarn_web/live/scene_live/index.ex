defmodule StoryarnWeb.SceneLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Live.Shared.TreePanelHandlers

  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Shared.MapUtils
  alias StoryarnWeb.Components.Sidebar.SceneTree

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:scenes}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      can_edit={@can_edit}
    >
      <:tree_content>
        <div role="tablist" class="tabs tabs-border tabs-sm mb-6">
          <button
            role="tab"
            class={["tab", @tree_panel_tab == "scenes" && "tab-active"]}
            phx-click="switch_tree_tab"
            phx-value-tab="scenes"
          >
            <.icon name="map" class="size-3.5 mr-1" />{dgettext("scenes", "Scenes")}
          </button>
          <button
            role="tab"
            class={["tab", @tree_panel_tab == "layers" && "tab-active"]}
            phx-click="switch_tree_tab"
            phx-value-tab="layers"
          >
            <.icon name="layers" class="size-3.5 mr-1" />{dgettext("scenes", "Layers")}
          </button>
        </div>
        <div :if={@tree_panel_tab == "scenes"}>
          <SceneTree.scenes_section
            scenes_tree={@scenes_tree}
            workspace={@workspace}
            project={@project}
            can_edit={@can_edit}
          />
        </div>
        <div :if={@tree_panel_tab == "layers"} class="px-3 py-6">
          <.empty_state icon="layers">
            {dgettext("scenes", "Select a scene to manage layers.")}
          </.empty_state>
        </div>
      </:tree_content>
      <div class="max-w-4xl mx-auto">
        <.header>
          {dgettext("scenes", "Scenes")}
          <:subtitle>
            {dgettext("scenes", "Create scenes to visualize your world")}
          </:subtitle>
        </.header>

        <.empty_state :if={@scenes == []} icon="map">
          {dgettext("scenes", "No scenes yet. Create your first scene to get started.")}
        </.empty_state>

        <div :if={@scenes != []} class="mt-6 space-y-2">
          <.scene_card
            :for={scene <- @scenes}
            scene={scene}
            project={@project}
            workspace={@workspace}
            can_edit={@can_edit}
          />
        </div>

        <.modal
          :if={@live_action == :new and @can_edit}
          id="new-scene-modal"
          show
          on_cancel={JS.patch(~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/scenes")}
        >
          <.live_component
            module={StoryarnWeb.SceneLive.Form}
            id="new-scene-form"
            project={@project}
            title={dgettext("scenes", "New Scene")}
            navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/scenes"}
          />
        </.modal>

        <.confirm_modal
          :if={@can_edit}
          id="delete-scene-confirm"
          title={dgettext("scenes", "Delete scene?")}
          message={dgettext("scenes", "Are you sure you want to delete this scene?")}
          confirm_text={dgettext("scenes", "Delete")}
          confirm_variant="error"
          icon="alert-triangle"
          on_confirm={JS.push("confirm_delete")}
        />
      </div>
    </Layouts.focus>
    """
  end

  attr :scene, :map, required: true
  attr :project, :map, required: true
  attr :workspace, :map, required: true
  attr :can_edit, :boolean, default: false

  defp scene_card(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md transition-shadow">
      <div class="card-body p-4">
        <div class="flex items-center justify-between">
          <.link
            navigate={
              ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/scenes/#{@scene.id}"
            }
            class="flex items-center gap-3 flex-1 min-w-0"
          >
            <div class="rounded-lg bg-primary/10 p-2">
              <.icon name="map" class="size-5 text-primary" />
            </div>
            <div class="flex-1 min-w-0">
              <h3 class="font-medium truncate flex items-center gap-2">
                {@scene.name}
                <span
                  :if={@scene.shortcut}
                  class="badge badge-ghost badge-xs font-mono"
                  title={dgettext("scenes", "Shortcut")}
                >
                  #{@scene.shortcut}
                </span>
              </h3>
              <p :if={@scene.description} class="text-sm text-base-content/60 truncate">
                {@scene.description}
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
                    JS.push("set_pending_delete", value: %{id: @scene.id})
                    |> show_modal("delete-scene-confirm")
                  }
                  onclick="event.stopPropagation();"
                >
                  <.icon name="trash-2" class="size-4" />
                  {dgettext("scenes", "Delete")}
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
        scenes = Scenes.list_scenes(project.id)
        scenes_tree = Scenes.list_scenes_tree(project.id)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(focus_layout_defaults())
          |> assign(:tree_panel_tab, "scenes")
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:scenes, scenes)
          |> assign(:scenes_tree, scenes_tree)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("scenes", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({StoryarnWeb.SceneLive.Form, {:saved, scene}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, dgettext("scenes", "Scene created successfully."))
     |> push_navigate(
       to:
         ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{scene.id}"
     )}
  end

  @impl true
  # Tree panel events (from FocusLayout)
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

  def handle_event("switch_tree_tab", %{"tab" => tab}, socket)
      when tab in ~w(scenes layers) do
    {:noreply, assign(socket, :tree_panel_tab, tab)}
  end

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

  def handle_event("delete", %{"id" => scene_id}, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      case Scenes.get_scene(socket.assigns.project.id, scene_id) do
        nil -> {:noreply, put_flash(socket, :error, dgettext("scenes", "Scene not found."))}
        scene -> do_delete_scene(socket, scene)
      end
    end)
  end

  def handle_event("create_scene", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      case Scenes.create_scene(socket.assigns.project, %{name: dgettext("scenes", "Untitled")}) do
        {:ok, new_scene} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{new_scene.id}"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not create scene."))}
      end
    end)
  end

  def handle_event("create_child_scene", %{"parent-id" => parent_id}, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      attrs = %{name: dgettext("scenes", "Untitled"), parent_id: parent_id}

      case Scenes.create_scene(socket.assigns.project, attrs) do
        {:ok, new_scene} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{new_scene.id}"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not create scene."))}
      end
    end)
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    with_authorization(socket, :edit_content, fn socket ->
      case Scenes.get_scene(socket.assigns.project.id, item_id) do
        nil -> {:noreply, put_flash(socket, :error, dgettext("scenes", "Scene not found."))}
        scene -> do_move_scene(socket, scene, new_parent_id, position)
      end
    end)
  end

  defp do_delete_scene(socket, scene) do
    case Scenes.delete_scene(scene) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("scenes", "Scene moved to trash."))
         |> reload_scenes()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not delete scene."))}
    end
  end

  defp do_move_scene(socket, scene, new_parent_id, position) do
    new_parent_id = MapUtils.parse_int(new_parent_id)
    position = MapUtils.parse_int(position) || 0

    case Scenes.move_scene_to_position(scene, new_parent_id, position) do
      {:ok, _} ->
        {:noreply, reload_scenes(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not move scene."))}
    end
  end

  defp reload_scenes(socket) do
    project_id = socket.assigns.project.id

    socket
    |> assign(:scenes, Scenes.list_scenes(project_id))
    |> assign(:scenes_tree, Scenes.list_scenes_tree(project_id))
  end
end
