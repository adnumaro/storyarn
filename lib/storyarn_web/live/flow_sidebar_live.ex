defmodule StoryarnWeb.FlowSidebarLive do
  @moduledoc """
  Flows-specific left sidebar LiveView.

  Rendered as a sticky nested child of the project layout on flow routes.
  Owns the flows tree + tree mutations. The FlowHeader, canvas, debug
  panel and version history stay in `FlowLive.Show` — the sidebar is
  focused on navigation only.
  """

  use StoryarnWeb, :live_view
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Shared.MapUtils
  alias StoryarnWeb.Helpers.Authorize

  @impl true
  def mount(_params, session, socket) do
    current_scope = session["current_scope"]
    if locale = session["locale"], do: Gettext.put_locale(Storyarn.Gettext, locale)
    project_id = session["project_id"]

    # Dashboard mode (no flow_id at mount time): force the tree open.
    # Matches the previous dashboard tree behavior from FlowLive.Index.
    dashboard_mode = is_nil(session["flow_id"])

    socket =
      socket
      |> assign(:current_scope, current_scope)
      |> assign(:membership, session["membership"])
      |> assign(:project_id, project_id)
      |> assign(:workspace_slug, session["workspace_slug"])
      |> assign(:project_slug, session["project_slug"])
      |> assign(:flow_id, session["flow_id"])
      |> assign(:can_edit, session["can_edit"] || false)
      |> assign(:active_tool, session["active_tool"] || "flows")
      |> assign(:dashboard_url, session["dashboard_url"])
      |> assign(:dashboard_mode, dashboard_mode)
      |> assign(:main_sidebar_open, dashboard_mode)
      |> assign(:pending_delete_id, nil)
      |> assign(:flows_tree, load_flows_tree(project_id))

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
        v-component="live/flow/sidebar/FlowSidebar"
        v-socket={@socket}
        id="shell-main-sidebar"
        main-sidebar-open={@main_sidebar_open}
        active-tool={@active_tool}
        dashboard-url={@dashboard_url}
        on-dashboard={is_nil(@flow_id)}
        sidebar-props={
          %{
            flowsTree: @flows_tree,
            selectedFlowId: @flow_id,
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
  def handle_event("create_flow", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Flows.create_flow(
             socket.assigns.current_scope,
             socket.assigns.project_id,
             %{name: dgettext("flows", "Untitled")}
           ) do
        {:ok, new_flow} ->
          {:noreply, on_tree_change_and_open(socket, new_flow.id)}

        {:error, :limit_reached, _} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Item limit reached for your plan"))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not create flow."))}
      end
    end)
  end

  def handle_event("create_child_flow", %{"parent_id" => parent_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      attrs = %{name: dgettext("flows", "Untitled"), parent_id: parent_id}

      case Flows.create_flow(socket.assigns.current_scope, socket.assigns.project_id, attrs) do
        {:ok, new_flow} ->
          {:noreply, on_tree_change_and_open(socket, new_flow.id)}

        {:error, :limit_reached, _} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Item limit reached for your plan"))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not create flow."))}
      end
    end)
  end

  def handle_event("set_main_flow", %{"id" => flow_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with %{} = flow <- Flows.get_flow(socket.assigns.project_id, flow_id),
           {:ok, _} <- Flows.set_main_flow(flow) do
        {:noreply, refresh_tree_and_broadcast(socket)}
      else
        _ ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not set main flow."))}
      end
    end)
  end

  def handle_event("set_pending_delete_flow", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      {:noreply, assign(socket, :pending_delete_id, id)}
    end)
  end

  def handle_event("confirm_delete_flow", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, &confirm_delete_flow/1)
  end

  def handle_event("move_to_parent", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      move_flow_to_parent(socket, params)
    end)
  end

  # ── Shell → sidebar synchronization ───────────────────────────────────────
  @impl true
  def handle_info({:active_flow, flow_id}, socket) do
    # Entering / leaving dashboard mode: sync the forced-open state so a
    # user navigating back to the dashboard always lands on the open tree.
    dashboard_mode = is_nil(flow_id)
    was_dashboard = socket.assigns[:dashboard_mode] || false

    socket = assign(socket, :flow_id, flow_id)

    socket =
      cond do
        dashboard_mode and not was_dashboard ->
          socket
          |> assign(:dashboard_mode, true)
          |> assign(:main_sidebar_open, true)

        not dashboard_mode and was_dashboard ->
          assign(socket, :dashboard_mode, false)

        true ->
          socket
      end

    {:noreply, socket}
  end

  def handle_info({:tree_changed, :flows}, socket) do
    {:noreply, assign(socket, :flows_tree, load_flows_tree(socket.assigns.project_id))}
  end

  def handle_info({:remote_change, action, _payload}, socket)
      when action in [:tree_changed, :flow_updated, :flow_restored] do
    {:noreply, assign(socket, :flows_tree, load_flows_tree(socket.assigns.project_id))}
  end

  def handle_info({:remote_change, _action, _payload}, socket), do: {:noreply, socket}

  def handle_info({:toolbar_event, _name, _params}, socket), do: {:noreply, socket}

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Helpers ───────────────────────────────────────────────────────────────
  defp confirm_delete_flow(socket) do
    case socket.assigns.pending_delete_id do
      nil ->
        {:noreply, socket}

      id ->
        delete_pending_flow(socket, id)
    end
  end

  defp move_flow_to_parent(socket, params) do
    with %{"item_id" => id, "new_parent_id" => new_parent_id, "position" => position} <- params,
         %{} = flow <- Flows.get_flow(socket.assigns.project_id, MapUtils.parse_int(id)) do
      move_existing_flow(socket, flow, new_parent_id, position)
    else
      _invalid -> {:noreply, socket}
    end
  end

  defp delete_pending_flow(socket, id) do
    with %{} = flow <- Flows.get_flow(socket.assigns.project_id, id),
         {:ok, %{deleted_ids: deleted_ids}} <-
           Flows.delete_flow_subtree(socket.assigns.current_scope, flow) do
      broadcast_entities_deleted(socket, deleted_ids)

      socket =
        socket
        |> assign(:pending_delete_id, nil)
        |> put_flash(:info, dgettext("flows", "Flow moved to trash."))
        |> refresh_tree_and_broadcast()

      {:noreply, socket}
    else
      _error ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Could not delete flow."))}
    end
  end

  defp move_existing_flow(socket, flow, new_parent_id, position) do
    parent_id = if new_parent_id in [nil, ""], do: nil, else: MapUtils.parse_int(new_parent_id)
    position = MapUtils.parse_int(position) || 0

    case Flows.move_flow_to_position(flow, parent_id, position) do
      {:ok, _flow} ->
        {:noreply, refresh_tree_and_broadcast(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Could not move flow."))}
    end
  end

  defp refresh_tree_and_broadcast(socket) do
    socket = assign(socket, :flows_tree, load_flows_tree(socket.assigns.project_id))

    Phoenix.PubSub.broadcast_from(
      Storyarn.PubSub,
      self(),
      shell_topic(socket.assigns.project_id),
      {:tree_changed, :flows}
    )

    socket
  end

  defp broadcast_entities_deleted(socket, ids) do
    Phoenix.PubSub.broadcast_from(
      Storyarn.PubSub,
      self(),
      shell_topic(socket.assigns.project_id),
      {:entities_deleted, :flow, ids}
    )
  end

  defp on_tree_change_and_open(socket, new_flow_id) do
    socket = refresh_tree_and_broadcast(socket)

    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      shell_topic(socket.assigns.project_id),
      {:open_flow, new_flow_id}
    )

    socket
  end

  defp load_flows_tree(nil), do: []
  defp load_flows_tree(project_id), do: Flows.list_flows_tree(project_id)

  def shell_topic(project_id), do: "project:#{project_id}:shell"
end
