defmodule StoryarnWeb.FlowLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.LiveHelpers.Authorize

  import StoryarnWeb.Components.CollaborationComponents
  import StoryarnWeb.Components.SaveIndicator
  import StoryarnWeb.FlowLive.Components.NodeTypeHelpers
  import StoryarnWeb.FlowLive.Components.PropertiesPanels
  import StoryarnWeb.Layouts, only: [flash_group: 1]

  alias StoryarnWeb.FlowLive.Components.ScreenplayEditor

  alias Storyarn.Assets
  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Pages
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias StoryarnWeb.FlowLive.Handlers.CollaborationEventHandlers
  alias StoryarnWeb.FlowLive.Handlers.ConditionEventHandlers
  alias StoryarnWeb.FlowLive.Handlers.EditorInfoHandlers
  alias StoryarnWeb.FlowLive.Handlers.NodeEventHandlers
  alias StoryarnWeb.FlowLive.Handlers.ResponseEventHandlers
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers
  alias StoryarnWeb.FlowLive.Helpers.ConnectionHelpers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers

  # Filter out entry from user-addable node types (entry is auto-created with flow)
  @node_types FlowNode.node_types() |> Enum.reject(&(&1 == "entry"))

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
            <h1
              :if={@can_edit}
              id="flow-title"
              class="text-lg font-medium outline-none rounded px-1 -mx-1 empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
              contenteditable="true"
              phx-hook="EditableTitle"
              phx-update="ignore"
              data-placeholder={gettext("Untitled")}
              data-name={@flow.name}
            >
              {@flow.name}
            </h1>
            <h1 :if={!@can_edit} class="text-lg font-medium">{@flow.name}</h1>
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

        <%!-- Node Properties Panel (Sidebar mode) --%>
        <.node_properties_panel
          :if={@selected_node && @editing_mode == :sidebar}
          node={@selected_node}
          form={@node_form}
          can_edit={@can_edit}
          leaf_pages={@leaf_pages}
          flow_hubs={@flow_hubs}
          audio_assets={@audio_assets}
          panel_sections={@panel_sections}
          project_variables={@project_variables}
        />
      </div>

      <.flash_group flash={@flash} />

      <%!-- Screenplay Editor (fullscreen overlay) --%>
      <.live_component
        :if={@selected_node && @editing_mode == :screenplay}
        module={ScreenplayEditor}
        id={"screenplay-editor-#{@selected_node.id}"}
        node={@selected_node}
        can_edit={@can_edit}
        leaf_pages={@leaf_pages}
        on_close={JS.push("close_editor")}
        on_open_sidebar={JS.push("open_sidebar")}
      />

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
    flow_hubs = Flows.list_hubs(flow.id)
    audio_assets = Assets.list_assets(project.id, content_type: "audio/")
    project_variables = Pages.list_project_variables(project.id)
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
    |> assign(:flow_hubs, flow_hubs)
    |> assign(:audio_assets, audio_assets)
    |> assign(:project_variables, project_variables)
    |> assign(:selected_node, nil)
    |> assign(:node_form, nil)
    |> assign(:editing_mode, nil)
    |> assign(:save_status, :idle)
    |> assign(:preview_show, false)
    |> assign(:preview_node, nil)
    |> assign(:online_users, online_users)
    |> assign(:node_locks, node_locks)
    |> assign(:collab_toast, nil)
    |> assign(:remote_cursors, %{})
    |> assign(:panel_sections, %{})
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # ===========================================================================
  # Event Handlers (thin delegation)
  # ===========================================================================

  @impl true
  def handle_event("add_node", params, socket) do
    with_auth(:edit_content, socket, fn -> NodeEventHandlers.handle_add_node(params, socket) end)
  end

  def handle_event("save_name", params, socket) do
    with_auth(:edit_content, socket, fn ->
      NodeEventHandlers.handle_save_name(params, socket)
    end)
  end

  def handle_event("save_shortcut", params, socket) do
    with_auth(:edit_content, socket, fn ->
      NodeEventHandlers.handle_save_shortcut(params, socket)
    end)
  end

  def handle_event("node_selected", params, socket) do
    NodeEventHandlers.handle_node_selected(params, socket)
  end

  def handle_event("node_double_clicked", params, socket) do
    NodeEventHandlers.handle_node_double_clicked(params, socket)
  end

  def handle_event("open_screenplay", _params, socket) do
    NodeEventHandlers.handle_open_screenplay(socket)
  end

  def handle_event("open_sidebar", _params, socket) do
    NodeEventHandlers.handle_open_sidebar(socket)
  end

  def handle_event("close_editor", _params, socket) do
    NodeEventHandlers.handle_close_editor(socket)
  end

  def handle_event("deselect_node", _params, socket) do
    NodeEventHandlers.handle_deselect_node(socket)
  end

  def handle_event("create_page", _params, socket) do
    with_auth(:edit_content, socket, fn -> NodeEventHandlers.handle_create_page(socket) end)
  end

  def handle_event("node_moved", params, socket) do
    with_auth(:edit_content, socket, fn ->
      NodeEventHandlers.handle_node_moved(params, socket)
    end)
  end

  def handle_event("update_node_data", %{"node" => _} = params, socket) do
    with_auth(:edit_content, socket, fn ->
      NodeEventHandlers.handle_update_node_data(params, socket)
    end)
  end

  # Handle condition builder fields coming from the dialogue form
  def handle_event("update_node_data", params, socket) when is_map(params) do
    has_response_condition_fields =
      Map.has_key?(params, "response-id") and Map.has_key?(params, "node-id")

    has_rule_fields =
      Enum.any?(params, fn {key, _} ->
        String.starts_with?(key, "rule_page_") or
          String.starts_with?(key, "rule_variable_") or
          String.starts_with?(key, "rule_operator_") or
          String.starts_with?(key, "rule_value_")
      end)

    if has_response_condition_fields and has_rule_fields do
      with_auth(:edit_content, socket, fn ->
        ConditionEventHandlers.handle_response_condition_from_form(params, socket)
      end)
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_node_text", params, socket) do
    with_auth(:edit_content, socket, fn ->
      NodeEventHandlers.handle_update_node_text(params, socket)
    end)
  end

  def handle_event("mention_suggestions", params, socket) do
    NodeEventHandlers.handle_mention_suggestions(params, socket)
  end

  def handle_event("delete_node", params, socket) do
    with_auth(:edit_content, socket, fn -> NodeEventHandlers.handle_delete_node(params, socket) end)
  end

  def handle_event("duplicate_node", params, socket) do
    with_auth(:edit_content, socket, fn ->
      NodeEventHandlers.handle_duplicate_node(params, socket)
    end)
  end

  def handle_event("generate_technical_id", _params, socket) do
    with_auth(:edit_content, socket, fn ->
      NodeEventHandlers.handle_generate_technical_id(socket)
    end)
  end

  def handle_event("update_node_field", params, socket) do
    with_auth(:edit_content, socket, fn ->
      NodeEventHandlers.handle_update_node_field(params, socket)
    end)
  end

  # Responses
  def handle_event("add_response", params, socket) do
    with_auth(:edit_content, socket, fn ->
      ResponseEventHandlers.handle_add_response(params, socket)
    end)
  end

  def handle_event("remove_response", params, socket) do
    with_auth(:edit_content, socket, fn ->
      ResponseEventHandlers.handle_remove_response(params, socket)
    end)
  end

  def handle_event("update_response_text", params, socket) do
    with_auth(:edit_content, socket, fn ->
      ResponseEventHandlers.handle_update_response_text(params, socket)
    end)
  end

  def handle_event("update_response_condition", params, socket) do
    with_auth(:edit_content, socket, fn ->
      ResponseEventHandlers.handle_update_response_condition(params, socket)
    end)
  end

  def handle_event("update_response_instruction", params, socket) do
    with_auth(:edit_content, socket, fn ->
      ResponseEventHandlers.handle_update_response_instruction(params, socket)
    end)
  end

  # Panel UI
  def handle_event("toggle_panel_section", %{"section" => section}, socket) do
    panel_sections = socket.assigns.panel_sections
    current_state = Map.get(panel_sections, section, false)
    updated_sections = Map.put(panel_sections, section, !current_state)
    {:noreply, assign(socket, :panel_sections, updated_sections)}
  end

  # Connections
  def handle_event("connection_created", params, socket) do
    ConnectionHelpers.create_connection(socket, params)
  end

  def handle_event("connection_deleted", %{"source_node_id" => source_id, "target_node_id" => target_id}, socket) do
    ConnectionHelpers.delete_connection_by_nodes(socket, source_id, target_id)
  end

  # Condition builders
  def handle_event("update_response_condition_builder", params, socket) do
    with_auth(:edit_content, socket, fn ->
      ConditionEventHandlers.handle_update_response_condition_builder(params, socket)
    end)
  end

  def handle_event("update_condition_builder", params, socket) do
    with_auth(:edit_content, socket, fn ->
      ConditionEventHandlers.handle_update_condition_builder(params, socket)
    end)
  end

  def handle_event("toggle_switch_mode", _params, socket) do
    with_auth(:edit_content, socket, fn ->
      ConditionEventHandlers.handle_toggle_switch_mode(socket)
    end)
  end

  # Collaboration & Preview
  def handle_event("cursor_moved", params, socket) do
    CollaborationEventHandlers.handle_cursor_moved(params, socket)
  end

  def handle_event("start_preview", params, socket) do
    NodeEventHandlers.handle_start_preview(params, socket)
  end

  # ===========================================================================
  # Handle Info (thin delegation)
  # ===========================================================================

  @impl true
  def handle_info(:reset_save_status, socket),
    do: EditorInfoHandlers.handle_reset_save_status(socket)

  def handle_info({:node_updated, updated_node}, socket),
    do: EditorInfoHandlers.handle_node_updated(updated_node, socket)

  def handle_info({:close_preview}, socket),
    do: EditorInfoHandlers.handle_close_preview(socket)

  def handle_info({:mention_suggestions, query, component_cid}, socket),
    do: EditorInfoHandlers.handle_mention_suggestions(query, component_cid, socket)

  def handle_info(:clear_collab_toast, socket),
    do: CollaborationEventHandlers.handle_clear_collab_toast(socket)

  def handle_info(%{event: "presence_diff", payload: _diff}, socket),
    do: CollaborationEventHandlers.handle_presence_diff(socket)

  def handle_info({:cursor_update, cursor_data}, socket),
    do: CollaborationEventHandlers.handle_cursor_update(cursor_data, socket)

  def handle_info({:cursor_leave, user_id}, socket),
    do: CollaborationEventHandlers.handle_cursor_leave(user_id, socket)

  def handle_info({:lock_change, action, payload}, socket),
    do: CollaborationEventHandlers.handle_lock_change(action, payload, socket)

  def handle_info({:remote_change, action, payload}, socket),
    do: CollaborationEventHandlers.handle_remote_change(action, payload, socket)

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp with_auth(action, socket, fun) do
    case authorize(socket, action) do
      :ok -> fun.()
      {:error, :unauthorized} -> {:noreply, unauthorized_flash(socket)}
    end
  end

  defp unauthorized_flash(socket) do
    put_flash(socket, :error, gettext("You don't have permission to perform this action."))
  end
end
