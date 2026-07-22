defmodule StoryarnWeb.SceneSidebarLive do
  @moduledoc """
  Scenes-specific left sidebar LiveView.

  Rendered as a sticky nested child of `ProjectLayout` on scene routes.
  Owns the scenes tree + tree mutations. Layers UI lives in a
  bottom-right floating popover rendered directly by `SceneLive.Show`
  — the sidebar stays focused on navigation.
  """

  use StoryarnWeb, :live_view
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias StoryarnWeb.Live.TreeSidebarActions
  alias StoryarnWeb.SceneLive.Helpers.PropsSerializer

  @impl true
  def mount(_params, session, socket) do
    current_scope = session["current_scope"]
    if locale = session["locale"], do: Gettext.put_locale(Storyarn.Gettext, locale)
    project_id = session["project_id"]

    project =
      if project_id && current_scope do
        case Projects.get_project(current_scope, project_id) do
          {:ok, project, _membership} -> project
          _ -> nil
        end
      end

    dashboard_mode = is_nil(session["scene_id"])

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
      |> assign(:dashboard_mode, dashboard_mode)
      |> assign(:main_sidebar_open, dashboard_mode)
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
        v-component="live/scene/sidebar/SceneSidebar"
        v-socket={@socket}
        id="shell-main-sidebar"
        main-sidebar-open={@main_sidebar_open}
        active-tool={@active_tool}
        dashboard-url={@dashboard_url}
        on-dashboard={is_nil(@scene_id)}
        sidebar-props={
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

  # ── Tree mutations ────────────────────────────────────────────────────────
  @impl true
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

  def handle_event("create_child_scene", params, socket) do
    with_edit(socket, fn socket ->
      parent_id = params["parent_id"] || params["parent-id"]
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
    with_edit(socket, &confirm_delete_scene/1)
  end

  def handle_event("move_to_parent", params, socket) do
    with_edit(socket, fn socket -> move_scene_to_parent(socket, params) end)
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

  def handle_info({:toolbar_event, _name, _params}, socket), do: {:noreply, socket}

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Helpers ───────────────────────────────────────────────────────────────
  defp with_edit(socket, fun) do
    TreeSidebarActions.with_edit(socket, dgettext("scenes", "You don't have permission to edit."), fun)
  end

  defp confirm_delete_scene(socket) do
    TreeSidebarActions.confirm_delete(socket, %{
      get_entity: &Scenes.get_scene/2,
      subtree_ids: &Scenes.subtree_ids/1,
      delete_entity: &Scenes.delete_scene/1,
      broadcast_deleted: &broadcast_entities_deleted/2,
      refresh_tree: &refresh_tree_and_broadcast/1,
      deleted_message: dgettext("scenes", "Scene moved to trash."),
      delete_error_message: dgettext("scenes", "Could not delete scene.")
    })
  end

  defp move_scene_to_parent(socket, params) do
    TreeSidebarActions.move_to_parent(socket, params, %{
      get_entity: &Scenes.get_scene/2,
      move_entity: &Scenes.move_scene_to_position/3,
      refresh_tree: &refresh_tree_and_broadcast/1,
      move_error_message: dgettext("scenes", "Could not move scene.")
    })
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

  defp broadcast_entities_deleted(socket, ids) do
    Phoenix.PubSub.broadcast_from(
      Storyarn.PubSub,
      self(),
      shell_topic(socket.assigns.project_id),
      {:entities_deleted, :scene, ids}
    )
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
