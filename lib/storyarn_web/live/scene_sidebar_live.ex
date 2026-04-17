defmodule StoryarnWeb.SceneSidebarLive do
  @moduledoc """
  Scenes-specific left sidebar LiveView.

  Rendered as a sticky nested child of `ProjectShell` on scene routes.
  Owns the scenes tree + tree mutations. Layers UI lives in a
  bottom-right floating popover rendered directly by `SceneLive.Show`
  — the sidebar stays focused on navigation.
  """

  use StoryarnWeb, :live_view
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Shared.MapUtils
  alias StoryarnWeb.SceneLive.Helpers.PropsSerializer

  @impl true
  def mount(_params, session, socket) do
    current_scope = session["current_scope"]
    project_id = session["project_id"]

    project =
      if project_id && current_scope do
        case Projects.get_project(current_scope, project_id) do
          {:ok, project, _membership} -> project
          _ -> nil
        end
      end

    socket =
      socket
      |> assign(:current_scope, current_scope)
      |> assign(:project, project)
      |> assign(:project_id, project_id)
      |> assign(:workspace_slug, session["workspace_slug"])
      |> assign(:project_slug, session["project_slug"])
      |> assign(:scene_id, session["scene_id"])
      |> assign(:can_edit, session["can_edit"] || false)
      |> assign(:active_tool, session["active_tool"] || "scenes")
      |> assign(:dashboard_url, session["dashboard_url"])
      |> assign(:tree_panel_open, false)
      |> assign(:tree_panel_pinned, false)
      |> assign(:pending_delete_id, nil)
      |> assign(:scenes_tree, load_scenes_tree(project_id))

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Storyarn.PubSub, shell_topic(project_id))
      Collaboration.subscribe_changes({:project, project_id})
    end

    {:ok, socket, layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.vue
        v-component="layout/TreePanel"
        v-socket={@socket}
        id="shell-tree-panel"
        tree-panel-open={@tree_panel_open}
        tree-panel-pinned={@tree_panel_pinned}
        show-pin={true}
        active-tool={@active_tool}
        dashboard-url={@dashboard_url}
        on-dashboard={is_nil(@scene_id)}
        tree-props={
          %{
            scenesTree: @scenes_tree,
            selectedSceneId: @scene_id,
            canEdit: @can_edit,
            workspaceSlug: @workspace_slug,
            projectSlug: @project_slug
          }
        }
      />
    </div>
    """
  end

  # ── Panel state events from TreePanel.vue ─────────────────────────────────
  @impl true
  def handle_event("tree_panel_init", %{"pinned" => pinned}, socket) do
    {:noreply,
     socket
     |> assign(:tree_panel_pinned, pinned)
     |> assign(:tree_panel_open, pinned)}
  end

  def handle_event("tree_panel_toggle", _params, socket) do
    {:noreply, assign(socket, :tree_panel_open, !socket.assigns.tree_panel_open)}
  end

  def handle_event("tree_panel_pin", _params, socket) do
    pinned = !socket.assigns.tree_panel_pinned

    {:noreply,
     socket
     |> assign(:tree_panel_pinned, pinned)
     |> assign(:tree_panel_open, pinned)}
  end

  # ── Tree mutations ────────────────────────────────────────────────────────
  def handle_event("create_scene", _params, socket) do
    with_edit(socket, fn socket ->
      case Scenes.create_scene(socket.assigns.project, %{name: dgettext("scenes", "Untitled")}) do
        {:ok, new_scene} ->
          {:noreply, on_tree_change_and_open(socket, new_scene.id)}

        {:error, :limit_reached, _} ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Item limit reached for your plan"))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not create scene."))}
      end
    end)
  end

  def handle_event("create_child_scene", %{"parent-id" => parent_id}, socket) do
    with_edit(socket, fn socket ->
      attrs = %{name: dgettext("scenes", "Untitled"), parent_id: parent_id}

      case Scenes.create_scene(socket.assigns.project, attrs) do
        {:ok, new_scene} ->
          {:noreply, on_tree_change_and_open(socket, new_scene.id)}

        {:error, :limit_reached, _} ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Item limit reached for your plan"))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not create scene."))}
      end
    end)
  end

  def handle_event("set_pending_delete_scene", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event("confirm_delete_scene", _params, socket) do
    with_edit(socket, fn socket ->
      case socket.assigns.pending_delete_id do
        nil ->
          {:noreply, socket}

        id ->
          with %{} = scene <- Scenes.get_scene(socket.assigns.project.id, id),
               {:ok, _} <- Scenes.delete_scene(scene) do
            {:noreply,
             socket
             |> assign(:pending_delete_id, nil)
             |> put_flash(:info, dgettext("scenes", "Scene moved to trash."))
             |> refresh_tree_and_broadcast()}
          else
            _ ->
              {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not delete scene."))}
          end
      end
    end)
  end

  def handle_event("move_to_parent", params, socket) do
    with_edit(socket, fn socket ->
      %{"item_id" => id, "new_parent_id" => new_parent_id, "position" => position} = params

      scene = Scenes.get_scene(socket.assigns.project.id, MapUtils.parse_int(id))

      if scene do
        parsed_parent =
          if new_parent_id in [nil, ""], do: nil, else: MapUtils.parse_int(new_parent_id)

        parsed_pos = MapUtils.parse_int(position) || 0

        case Scenes.move_scene_to_position(scene, parsed_parent, parsed_pos) do
          {:ok, _} ->
            {:noreply, refresh_tree_and_broadcast(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not move scene."))}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  # ── Shell → sidebar synchronization ───────────────────────────────────────
  @impl true
  def handle_info({:active_scene, scene_id}, socket) do
    {:noreply, assign(socket, :scene_id, scene_id)}
  end

  def handle_info({:tree_changed, :scenes}, socket) do
    {:noreply, assign(socket, :scenes_tree, load_scenes_tree(socket.assigns.project_id))}
  end

  def handle_info({:remote_change, action, _payload}, socket)
      when action in [:tree_changed, :scene_updated, :scene_restored] do
    {:noreply, assign(socket, :scenes_tree, load_scenes_tree(socket.assigns.project_id))}
  end

  def handle_info({:remote_change, _action, _payload}, socket), do: {:noreply, socket}

  # Forwarded from the page LV (LeftToolbar.vue's pushEvent lands there).
  def handle_info({:toolbar_event, "tree_panel_toggle", _params}, socket) do
    {:noreply, assign(socket, :tree_panel_open, !socket.assigns.tree_panel_open)}
  end

  def handle_info({:toolbar_event, "tree_panel_pin", _params}, socket) do
    pinned = !socket.assigns.tree_panel_pinned

    {:noreply,
     socket
     |> assign(:tree_panel_pinned, pinned)
     |> assign(:tree_panel_open, pinned)}
  end

  def handle_info({:toolbar_event, "tree_panel_init", %{"pinned" => pinned}}, socket) do
    {:noreply,
     socket
     |> assign(:tree_panel_pinned, pinned)
     |> assign(:tree_panel_open, pinned)}
  end

  def handle_info({:toolbar_event, _name, _params}, socket), do: {:noreply, socket}

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Helpers ───────────────────────────────────────────────────────────────
  defp with_edit(socket, fun) do
    if socket.assigns.can_edit do
      fun.(socket)
    else
      {:noreply, put_flash(socket, :error, dgettext("scenes", "You don't have permission to edit."))}
    end
  end

  defp refresh_tree_and_broadcast(socket) do
    socket = assign(socket, :scenes_tree, load_scenes_tree(socket.assigns.project_id))

    Phoenix.PubSub.broadcast_from(
      Storyarn.PubSub,
      self(),
      shell_topic(socket.assigns.project_id),
      {:tree_changed, :scenes}
    )

    socket
  end

  defp on_tree_change_and_open(socket, new_scene_id) do
    socket = refresh_tree_and_broadcast(socket)

    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      shell_topic(socket.assigns.project_id),
      {:open_scene, new_scene_id}
    )

    socket
  end

  defp load_scenes_tree(nil), do: []

  defp load_scenes_tree(project_id) do
    project_id
    |> Scenes.list_scenes_tree()
    |> PropsSerializer.prepare_scenes_tree()
  end

  def shell_topic(project_id), do: "project:#{project_id}:shell"
end
