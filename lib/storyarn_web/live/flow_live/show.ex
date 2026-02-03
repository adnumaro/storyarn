defmodule StoryarnWeb.FlowLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.LiveHelpers.Authorize

  import StoryarnWeb.Components.CollaborationComponents
  import StoryarnWeb.Components.SaveIndicator
  import StoryarnWeb.FlowLive.Components.NodeTypeHelpers
  import StoryarnWeb.FlowLive.Components.PropertiesPanels
  import StoryarnWeb.Layouts, only: [flash_group: 1]

  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Pages
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers
  alias StoryarnWeb.FlowLive.Helpers.ConnectionHelpers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  @node_types FlowNode.node_types()

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col">
      <%!-- Header --%>
      <header class="navbar bg-base-100 border-b border-base-300 px-4 shrink-0">
        <div class="flex-none">
          <.link
            navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows"}
            class="btn btn-ghost btn-sm gap-2"
          >
            <.icon name="chevron-left" class="size-4" />
            {gettext("Flows")}
          </.link>
        </div>
        <div class="flex-1 flex items-center gap-3 ml-4">
          <div>
            <h1 class="text-lg font-medium">{@flow.name}</h1>
            <div :if={@can_edit} class="flex items-center gap-1 text-xs">
              <span class="text-base-content/50">#</span>
              <span
                id="flow-shortcut"
                class="text-base-content/50 outline-none hover:text-base-content empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
                contenteditable="true"
                phx-hook="EditableShortcut"
                phx-update="ignore"
                data-placeholder={gettext("add-shortcut")}
                data-shortcut={@flow.shortcut || ""}
              >
                {@flow.shortcut}
              </span>
            </div>
            <div :if={!@can_edit && @flow.shortcut} class="text-xs text-base-content/50">
              #{@flow.shortcut}
            </div>
          </div>
          <span :if={@flow.is_main} class="badge badge-primary badge-sm" title={gettext("Main flow")}>
            {gettext("Main")}
          </span>
        </div>
        <div class="flex-none flex items-center gap-4">
          <.online_users users={@online_users} current_user_id={@current_scope.user.id} />
          <.save_indicator :if={@can_edit} status={@save_status} />
          <div :if={@can_edit} class="dropdown dropdown-end">
            <button type="button" tabindex="0" class="btn btn-primary btn-sm gap-2">
              <.icon name="plus" class="size-4" />
              {gettext("Add Node")}
            </button>
            <ul
              tabindex="0"
              class="dropdown-content menu menu-sm bg-base-100 rounded-box shadow-lg border border-base-300 w-48 z-50 mt-2"
            >
              <li :for={type <- @node_types}>
                <button type="button" phx-click="add_node" phx-value-type={type}>
                  <.node_type_icon type={type} />
                  {node_type_label(type)}
                </button>
              </li>
            </ul>
          </div>
        </div>
      </header>

      <%!-- Collaboration Toast --%>
      <.collab_toast
        :if={@collab_toast}
        action={@collab_toast.action}
        user_email={@collab_toast.user_email}
        user_color={@collab_toast.user_color}
      />

      <%!-- Main content: Canvas + Properties Panel --%>
      <div class="flex-1 flex overflow-hidden">
        <%!-- Canvas --%>
        <div class="flex-1 relative bg-base-200">
          <div
            id="flow-canvas"
            phx-hook="FlowCanvas"
            phx-update="ignore"
            class="absolute inset-0"
            data-flow={Jason.encode!(@flow_data)}
            data-pages={Jason.encode!(FormHelpers.pages_map(@leaf_pages))}
            data-locks={Jason.encode!(@node_locks)}
            data-user-id={@current_scope.user.id}
            data-user-color={Collaboration.user_color(@current_scope.user.id)}
          >
          </div>
        </div>

        <%!-- Node Properties Panel --%>
        <.node_properties_panel
          :if={@selected_node}
          node={@selected_node}
          form={@node_form}
          can_edit={@can_edit}
          leaf_pages={@leaf_pages}
        />

        <%!-- Connection Properties Panel --%>
        <.connection_properties_panel
          :if={@selected_connection && !@selected_node}
          connection={@selected_connection}
          form={@connection_form}
          can_edit={@can_edit}
        />
      </div>

      <.flash_group flash={@flash} />

      <%!-- Preview Modal --%>
      <.live_component
        module={StoryarnWeb.FlowLive.PreviewComponent}
        id="flow-preview"
        show={@preview_show}
        start_node={@preview_node}
        project={@project}
        pages_map={FormHelpers.pages_map(@leaf_pages)}
      />
    </div>
    """
  end

  # ===========================================================================
  # Mount & Setup
  # ===========================================================================

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug, "id" => flow_id},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(socket.assigns.current_scope, workspace_slug, project_slug) do
      {:ok, project, membership} ->
        mount_with_project(socket, workspace_slug, project_slug, flow_id, project, membership)

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  defp mount_with_project(socket, workspace_slug, project_slug, flow_id, project, membership) do
    case Flows.get_flow(project.id, flow_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Flow not found."))
         |> redirect(to: ~p"/workspaces/#{workspace_slug}/projects/#{project_slug}/flows")}

      flow ->
        {:ok, setup_flow_view(socket, project, membership, flow)}
    end
  end

  defp setup_flow_view(socket, project, membership, flow) do
    project = Repo.preload(project, :workspace)
    can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)
    flow_data = Flows.serialize_for_canvas(flow)
    leaf_pages = Pages.list_leaf_pages(project.id)
    user = socket.assigns.current_scope.user

    CollaborationHelpers.setup_collaboration(socket, flow, user)
    {online_users, node_locks} = CollaborationHelpers.get_initial_collab_state(socket, flow)

    socket
    |> assign(:project, project)
    |> assign(:workspace, project.workspace)
    |> assign(:membership, membership)
    |> assign(:flow, flow)
    |> assign(:flow_data, flow_data)
    |> assign(:can_edit, can_edit)
    |> assign(:node_types, @node_types)
    |> assign(:leaf_pages, leaf_pages)
    |> assign(:selected_node, nil)
    |> assign(:node_form, nil)
    |> assign(:selected_connection, nil)
    |> assign(:connection_form, nil)
    |> assign(:save_status, :idle)
    |> assign(:preview_show, false)
    |> assign(:preview_node, nil)
    |> assign(:online_users, online_users)
    |> assign(:node_locks, node_locks)
    |> assign(:collab_toast, nil)
    |> assign(:remote_cursors, %{})
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # ===========================================================================
  # Event Handlers: Nodes
  # ===========================================================================

  @impl true
  def handle_event("add_node", %{"type" => type}, socket) do
    case authorize(socket, :edit_content) do
      :ok -> NodeHelpers.add_node(socket, type)
      {:error, :unauthorized} -> {:noreply, unauthorized_flash(socket)}
    end
  end

  def handle_event("save_shortcut", %{"shortcut" => shortcut}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        flow = socket.assigns.flow
        shortcut = if shortcut == "", do: nil, else: shortcut

        case Flows.update_flow(flow, %{shortcut: shortcut}) do
          {:ok, updated_flow} ->
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:flow, updated_flow)
             |> assign(:save_status, :saved)}

          {:error, changeset} ->
            error_msg = format_shortcut_error(changeset)
            {:noreply, put_flash(socket, :error, error_msg)}
        end

      {:error, :unauthorized} ->
        {:noreply, unauthorized_flash(socket)}
    end
  end

  def handle_event("node_selected", %{"id" => node_id}, socket) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    form = FormHelpers.node_data_to_form(node)
    user = socket.assigns.current_scope.user

    socket =
      if socket.assigns.can_edit do
        handle_node_lock_acquisition(socket, node_id, user)
      else
        socket
      end

    {:noreply, socket |> assign(:selected_node, node) |> assign(:node_form, form)}
  end

  def handle_event("deselect_node", _params, socket) do
    socket =
      if socket.assigns.selected_node && socket.assigns.can_edit do
        release_node_lock(socket, socket.assigns.selected_node.id)
      else
        socket
      end

    {:noreply, socket |> assign(:selected_node, nil) |> assign(:node_form, nil)}
  end

  def handle_event("create_page", _params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Pages.create_page(socket.assigns.project, %{name: gettext("Untitled")}) do
          {:ok, new_page} ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/pages/#{new_page.id}"
             )}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not create page."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("node_moved", %{"id" => node_id, "position_x" => x, "position_y" => y}, socket) do
    node = Flows.get_node_by_id!(node_id)

    case Flows.update_node_position(node, %{position_x: x, position_y: y}) do
      {:ok, _} ->
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:save_status, :saved)
         |> CollaborationHelpers.broadcast_change(:node_moved, %{node_id: node_id, x: x, y: y})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("update_node_data", %{"node" => node_params}, socket) do
    case authorize(socket, :edit_content) do
      :ok -> NodeHelpers.update_node_data(socket, node_params)
      {:error, :unauthorized} -> {:noreply, socket}
    end
  end

  def handle_event("update_node_text", %{"id" => node_id, "content" => content}, socket) do
    case authorize(socket, :edit_content) do
      :ok -> NodeHelpers.update_node_text(socket, node_id, content)
      {:error, :unauthorized} -> {:noreply, socket}
    end
  end

  def handle_event("mention_suggestions", %{"query" => query}, socket) do
    project_id = socket.assigns.project.id
    results = Pages.search_referenceable(project_id, query, ["page", "flow"])

    items =
      Enum.map(results, fn result ->
        %{
          id: result.id,
          type: result.type,
          name: result.name,
          shortcut: result.shortcut,
          label: result.shortcut || result.name
        }
      end)

    {:noreply, push_event(socket, "mention_suggestions_result", %{items: items})}
  end

  def handle_event("delete_node", %{"id" => node_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok -> NodeHelpers.delete_node(socket, node_id)
      {:error, :unauthorized} -> {:noreply, unauthorized_flash(socket)}
    end
  end

  def handle_event("duplicate_node", %{"id" => node_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok -> NodeHelpers.duplicate_node(socket, node_id)
      {:error, :unauthorized} -> {:noreply, unauthorized_flash(socket)}
    end
  end

  # ===========================================================================
  # Event Handlers: Responses
  # ===========================================================================

  def handle_event("add_response", %{"node-id" => node_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok -> NodeHelpers.add_response(socket, node_id)
      {:error, :unauthorized} -> {:noreply, socket}
    end
  end

  def handle_event(
        "remove_response",
        %{"response-id" => response_id, "node-id" => node_id},
        socket
      ) do
    case authorize(socket, :edit_content) do
      :ok -> NodeHelpers.remove_response(socket, node_id, response_id)
      {:error, :unauthorized} -> {:noreply, socket}
    end
  end

  def handle_event(
        "update_response_text",
        %{"response-id" => response_id, "node-id" => node_id, "value" => text},
        socket
      ) do
    case authorize(socket, :edit_content) do
      :ok -> NodeHelpers.update_response_field(socket, node_id, response_id, "text", text)
      {:error, :unauthorized} -> {:noreply, socket}
    end
  end

  def handle_event(
        "update_response_condition",
        %{"response-id" => response_id, "node-id" => node_id, "value" => condition},
        socket
      ) do
    case authorize(socket, :edit_content) do
      :ok ->
        value = if condition == "", do: nil, else: condition
        NodeHelpers.update_response_field(socket, node_id, response_id, "condition", value)

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  # ===========================================================================
  # Event Handlers: Connections
  # ===========================================================================

  def handle_event("connection_selected", %{"id" => connection_id}, socket) do
    ConnectionHelpers.select_connection(socket, connection_id)
  end

  def handle_event("deselect_connection", _params, socket) do
    ConnectionHelpers.deselect_connection(socket)
  end

  def handle_event("update_connection_data", %{"connection" => conn_params}, socket) do
    case authorize(socket, :edit_content) do
      :ok -> ConnectionHelpers.update_connection_data(socket, conn_params)
      {:error, :unauthorized} -> {:noreply, socket}
    end
  end

  def handle_event("delete_connection", %{"id" => connection_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok -> ConnectionHelpers.delete_connection(socket, connection_id)
      {:error, :unauthorized} -> {:noreply, unauthorized_flash(socket)}
    end
  end

  def handle_event("connection_created", params, socket) do
    ConnectionHelpers.create_connection(socket, params)
  end

  def handle_event(
        "connection_deleted",
        %{"source_node_id" => source_id, "target_node_id" => target_id},
        socket
      ) do
    ConnectionHelpers.delete_connection_by_nodes(socket, source_id, target_id)
  end

  # ===========================================================================
  # Event Handlers: Collaboration & Other
  # ===========================================================================

  def handle_event("cursor_moved", %{"x" => x, "y" => y}, socket) do
    user = socket.assigns.current_scope.user
    Collaboration.broadcast_cursor(socket.assigns.flow.id, user, x, y)
    {:noreply, socket}
  end

  def handle_event("start_preview", %{"id" => node_id}, socket) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    {:noreply, socket |> assign(:preview_show, true) |> assign(:preview_node, node)}
  end

  # ===========================================================================
  # Handle Info: System Messages
  # ===========================================================================

  @impl true
  def handle_info(:reset_save_status, socket) do
    {:noreply, assign(socket, :save_status, :idle)}
  end

  def handle_info({:close_preview}, socket) do
    {:noreply, assign(socket, preview_show: false, preview_node: nil)}
  end

  def handle_info(:clear_collab_toast, socket) do
    {:noreply, assign(socket, :collab_toast, nil)}
  end

  # ===========================================================================
  # Handle Info: Collaboration
  # ===========================================================================

  def handle_info(%{event: "presence_diff", payload: _diff}, socket) do
    online_users = Collaboration.list_online_users(socket.assigns.flow.id)
    {:noreply, assign(socket, :online_users, online_users)}
  end

  def handle_info({:cursor_update, cursor_data}, socket) do
    if cursor_data.user_id == socket.assigns.current_scope.user.id do
      {:noreply, socket}
    else
      remote_cursors = Map.put(socket.assigns.remote_cursors, cursor_data.user_id, cursor_data)

      {:noreply,
       socket
       |> assign(:remote_cursors, remote_cursors)
       |> push_event("cursor_update", cursor_data)}
    end
  end

  def handle_info({:cursor_leave, user_id}, socket) do
    remote_cursors = Map.delete(socket.assigns.remote_cursors, user_id)

    {:noreply,
     socket
     |> assign(:remote_cursors, remote_cursors)
     |> push_event("cursor_leave", %{user_id: user_id})}
  end

  def handle_info({:lock_change, action, payload}, socket) do
    node_locks = Collaboration.list_locks(socket.assigns.flow.id)

    socket =
      socket
      |> assign(:node_locks, node_locks)
      |> push_event("locks_updated", %{locks: node_locks})

    socket =
      if payload.user_id != socket.assigns.current_scope.user.id do
        CollaborationHelpers.show_collab_toast(socket, action, payload)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:remote_change, action, payload}, socket) do
    if payload.user_id == socket.assigns.current_scope.user.id do
      {:noreply, socket}
    else
      flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
      flow_data = Flows.serialize_for_canvas(flow)

      socket =
        socket
        |> assign(:flow, flow)
        |> assign(:flow_data, flow_data)
        |> CollaborationHelpers.push_remote_change_event(action, payload)
        |> CollaborationHelpers.show_collab_toast(action, payload)

      {:noreply, socket}
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp schedule_save_status_reset do
    Process.send_after(self(), :reset_save_status, 2000)
  end

  defp format_shortcut_error(changeset) do
    case changeset.errors[:shortcut] do
      {msg, _opts} -> gettext("Shortcut %{error}", error: msg)
      nil -> gettext("Could not save shortcut.")
    end
  end

  defp unauthorized_flash(socket) do
    put_flash(socket, :error, gettext("You don't have permission to perform this action."))
  end

  # Node locking

  defp handle_node_lock_acquisition(socket, node_id, user) do
    case Collaboration.acquire_lock(socket.assigns.flow.id, node_id, user) do
      {:ok, _lock_info} ->
        CollaborationHelpers.broadcast_lock_change(socket, :node_locked, node_id)
        node_locks = Collaboration.list_locks(socket.assigns.flow.id)

        socket
        |> assign(:node_locks, node_locks)
        |> push_event("locks_updated", %{locks: node_locks})

      {:error, :already_locked, lock_info} ->
        put_flash(
          socket,
          :info,
          gettext("This node is being edited by %{user}",
            user: FormHelpers.get_email_name(lock_info.user_email)
          )
        )
    end
  end

  defp release_node_lock(socket, node_id) do
    user_id = socket.assigns.current_scope.user.id
    Collaboration.release_lock(socket.assigns.flow.id, node_id, user_id)
    CollaborationHelpers.broadcast_lock_change(socket, :node_unlocked, node_id)
    node_locks = Collaboration.list_locks(socket.assigns.flow.id)
    socket |> assign(:node_locks, node_locks) |> push_event("locks_updated", %{locks: node_locks})
  end
end
