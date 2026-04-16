defmodule StoryarnWeb.SceneSidebarLive do
  @moduledoc """
  Scenes-specific left sidebar LiveView.

  Rendered as a sticky nested child of `ProjectShell` on scene routes.
  Owns the scenes tree + tree mutations. Layer events fired from
  `SceneLayerList.vue` (when the user is on a Show page) are forwarded
  via PubSub to `SceneLive.Show`, which keeps all layer logic
  (undo/redo, auto-snapshot, canvas `push_event`s) co-located with the
  scene state. When the Layers UI eventually moves to a right-side
  dock, the forwards here will be deleted.
  """

  use StoryarnWeb, :live_view
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Shared.MapUtils
  alias StoryarnWeb.SceneLive.Helpers.PropsSerializer

  @layer_events ~w(
    set_active_layer
    toggle_layer_visibility
    create_layer
    start_rename_layer
    rename_layer
    update_layer_fog
    set_pending_delete_layer
    confirm_delete_layer
    delete_layer
  )

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
      |> assign(:layers, session["initial_layers"] || [])
      |> assign(:active_layer_id, session["initial_active_layer_id"])
      |> assign(:edit_mode, session["initial_edit_mode"] || false)
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
            projectSlug: @project_slug,
            layers: @layers,
            activeLayerId: @active_layer_id,
            editMode: @edit_mode,
            hasScene: @scene_id != nil,
            hasLayers: @scene_id != nil
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
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

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
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

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

  # ── Layer events — forwarded to Show via PubSub ───────────────────────────
  # All layer mutations live in `SceneLive.Show` to keep them co-located with
  # the undo stack, auto-snapshot scheduler, collab `_broadcast` flag, and
  # canvas `push_event`s. The sidebar just relays.
  def handle_event(event, params, socket) when event in @layer_events do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      shell_topic(socket.assigns.project_id),
      {:layer_event, event, params}
    )

    {:noreply, socket}
  end

  # ── Shell → sidebar synchronization ───────────────────────────────────────
  @impl true
  def handle_info({:active_scene, scene_id}, socket) do
    {:noreply, assign(socket, :scene_id, scene_id)}
  end

  def handle_info({:scene_payload_changed, payload}, socket) do
    {:noreply,
     socket
     |> assign(:layers, payload[:layers] || socket.assigns.layers)
     |> assign(:active_layer_id, payload[:active_layer_id] || socket.assigns.active_layer_id)
     |> assign(:edit_mode, Map.get(payload, :edit_mode, socket.assigns.edit_mode))}
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

  # Ignore layer_event echoes (broadcast is non-self but keep a safe fallback).
  def handle_info({:layer_event, _event, _params}, socket), do: {:noreply, socket}

  def handle_info({:toolbar_event, _name, _params}, socket), do: {:noreply, socket}

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Helpers ───────────────────────────────────────────────────────────────
  defp with_edit(socket, fun) do
    if socket.assigns.can_edit do
      fun.(socket)
    else
      {:noreply, put_flash(socket, :error, gettext("You don't have permission to edit."))}
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
