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
  alias Storyarn.Flows.Condition
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Pages
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers
  alias StoryarnWeb.FlowLive.Helpers.ConnectionHelpers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

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

    {:noreply,
     socket
     |> assign(:selected_node, node)
     |> assign(:node_form, form)
     |> assign(:editing_mode, :sidebar)}
  end

  def handle_event("node_double_clicked", %{"id" => node_id}, socket) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    form = FormHelpers.node_data_to_form(node)
    user = socket.assigns.current_scope.user

    # Only dialogue nodes support screenplay mode
    editing_mode = if node.type == "dialogue", do: :screenplay, else: :sidebar

    socket =
      if socket.assigns.can_edit do
        handle_node_lock_acquisition(socket, node_id, user)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:selected_node, node)
     |> assign(:node_form, form)
     |> assign(:editing_mode, editing_mode)}
  end

  def handle_event("open_screenplay", _params, socket) do
    if socket.assigns.selected_node && socket.assigns.selected_node.type == "dialogue" do
      {:noreply, assign(socket, :editing_mode, :screenplay)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("open_sidebar", _params, socket) do
    {:noreply, assign(socket, :editing_mode, :sidebar)}
  end

  def handle_event("close_editor", _params, socket) do
    socket =
      if socket.assigns.selected_node && socket.assigns.can_edit do
        release_node_lock(socket, socket.assigns.selected_node.id)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:selected_node, nil)
     |> assign(:node_form, nil)
     |> assign(:editing_mode, nil)}
  end

  def handle_event("deselect_node", _params, socket) do
    socket =
      if socket.assigns.selected_node && socket.assigns.can_edit do
        release_node_lock(socket, socket.assigns.selected_node.id)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:selected_node, nil)
     |> assign(:node_form, nil)
     |> assign(:editing_mode, nil)}
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
    case authorize(socket, :edit_content) do
      :ok ->
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

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event("update_node_data", %{"node" => node_params}, socket) do
    case authorize(socket, :edit_content) do
      :ok -> NodeHelpers.update_node_data(socket, node_params)
      {:error, :unauthorized} -> {:noreply, socket}
    end
  end

  # Handle condition builder fields coming from the dialogue form
  # (when condition builder is inside the form without wrap_in_form)
  def handle_event("update_node_data", params, socket) when is_map(params) do
    # Check if this contains condition builder fields for a response
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
      # Route to response condition builder handler
      case authorize(socket, :edit_content) do
        :ok -> handle_response_condition_update(socket, params)
        {:error, :unauthorized} -> {:noreply, socket}
      end
    else
      # Ignore other events without node params
      {:noreply, socket}
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

  def handle_event("generate_technical_id", _params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        node = socket.assigns.selected_node

        if node && node.type == "dialogue" do
          flow = socket.assigns.flow
          speaker_page_id = node.data["speaker_page_id"]
          speaker_name = get_speaker_name(socket, speaker_page_id)
          speaker_count = count_speaker_in_flow(flow, speaker_page_id, node.id)
          technical_id = generate_technical_id(flow.shortcut, speaker_name, speaker_count)

          NodeHelpers.update_node_field(socket, node.id, "technical_id", technical_id)
        else
          {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event("update_node_field", %{"field" => field, "value" => value}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        node = socket.assigns.selected_node

        if node do
          NodeHelpers.update_node_field(socket, node.id, field, value)
        else
          {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
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

  def handle_event(
        "update_response_instruction",
        %{"response-id" => response_id, "node-id" => node_id, "value" => instruction},
        socket
      ) do
    case authorize(socket, :edit_content) do
      :ok ->
        value = if instruction == "", do: nil, else: instruction
        NodeHelpers.update_response_field(socket, node_id, response_id, "instruction", value)

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  # ===========================================================================
  # Event Handlers: Panel UI
  # ===========================================================================

  def handle_event("toggle_panel_section", %{"section" => section}, socket) do
    panel_sections = socket.assigns.panel_sections
    current_state = Map.get(panel_sections, section, false)
    updated_sections = Map.put(panel_sections, section, !current_state)

    {:noreply, assign(socket, :panel_sections, updated_sections)}
  end

  # ===========================================================================
  # Event Handlers: Connections
  # ===========================================================================

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
  # Event Handlers: Response Condition Builder
  # ===========================================================================

  def handle_event("update_response_condition_builder", params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        handle_response_condition_update(socket, params)

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  # ===========================================================================
  # Event Handlers: Condition Node Builder
  # ===========================================================================

  def handle_event("update_condition_builder", params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        handle_condition_node_update(socket, params)

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_switch_mode", _params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        node = socket.assigns.selected_node

        if node && node.type == "condition" do
          current_switch_mode = node.data["switch_mode"] || false
          new_switch_mode = !current_switch_mode

          # When switching to switch mode, add labels to existing rules
          updated_condition =
            if new_switch_mode do
              condition = node.data["condition"] || Condition.new()
              rules = condition["rules"] || []

              updated_rules =
                Enum.map(rules, fn rule ->
                  Map.put_new(rule, "label", "")
                end)

              Map.put(condition, "rules", updated_rules)
            else
              node.data["condition"]
            end

          updated_data =
            node.data
            |> Map.put("switch_mode", new_switch_mode)
            |> Map.put("condition", updated_condition)

          case Flows.update_node_data(node, updated_data) do
            {:ok, updated_node} ->
              form = FormHelpers.node_data_to_form(updated_node)
              schedule_save_status_reset()

              {:noreply,
               socket
               |> reload_flow_data()
               |> assign(:selected_node, updated_node)
               |> assign(:node_form, form)
               |> assign(:save_status, :saved)
               |> push_event("node_updated", %{id: node.id, data: updated_node.data})}

            {:error, _} ->
              {:noreply, socket}
          end
        else
          {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
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

  # Handle node updates from ScreenplayEditor LiveComponent
  def handle_info({:node_updated, updated_node}, socket) do
    form = FormHelpers.node_data_to_form(updated_node)
    schedule_save_status_reset()

    {:noreply,
     socket
     |> reload_flow_data()
     |> assign(:selected_node, updated_node)
     |> assign(:node_form, form)
     |> assign(:save_status, :saved)
     |> push_event("node_updated", %{id: updated_node.id, data: updated_node.data})}
  end

  def handle_info({:close_preview}, socket) do
    {:noreply, assign(socket, preview_show: false, preview_node: nil)}
  end

  # Handle mention suggestions from ScreenplayEditor LiveComponent
  def handle_info({:mention_suggestions, query, component_cid}, socket) do
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

    {:noreply, push_event(socket, "mention_suggestions_result", %{items: items, target: component_cid})}
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


  # Condition node builder helpers

  defp handle_condition_node_update(socket, params) do
    node = socket.assigns.selected_node

    if node && node.type == "condition" do
      current_condition = node.data["condition"] || Condition.new()
      updated_condition = apply_condition_update(current_condition, params)

      # Update the node data with the new condition
      updated_data = Map.put(node.data, "condition", updated_condition)

      case Flows.update_node_data(node, updated_data) do
        {:ok, updated_node} ->
          form = FormHelpers.node_data_to_form(updated_node)
          schedule_save_status_reset()

          {:noreply,
           socket
           |> reload_flow_data()
           |> assign(:selected_node, updated_node)
           |> assign(:node_form, form)
           |> assign(:save_status, :saved)
           |> push_event("node_updated", %{id: node.id, data: updated_node.data})}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Response condition builder helpers

  defp handle_response_condition_update(socket, params) do
    response_id = params["response-id"]
    node_id = params["node-id"]

    case get_response_for_update(socket, node_id, response_id) do
      {:ok, response} ->
        current_condition = parse_response_condition(response)
        updated_condition = apply_condition_update(current_condition, params)
        new_condition_string = Condition.to_json(updated_condition)
        NodeHelpers.update_response_field(socket, node_id, response_id, "condition", new_condition_string)

      :error ->
        {:noreply, socket}
    end
  end

  defp get_response_for_update(_socket, nil, _response_id), do: :error
  defp get_response_for_update(_socket, _node_id, nil), do: :error

  defp get_response_for_update(socket, node_id, response_id) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    responses = node.data["responses"] || []

    case Enum.find(responses, fn r -> r["id"] == response_id end) do
      nil -> :error
      response -> {:ok, response}
    end
  end

  defp parse_response_condition(response) do
    raw_condition = response["condition"] || ""

    case Condition.parse(raw_condition) do
      :legacy -> Condition.new()
      nil -> Condition.new()
      cond -> cond
    end
  end

  defp apply_condition_update(current_condition, params) do
    cond do
      Map.has_key?(params, "logic") ->
        Condition.set_logic(current_condition, params["logic"])

      params["action"] == "add_rule" ->
        # Check if switch mode is enabled
        with_label = params["switch-mode"] == "true"
        Condition.add_rule(current_condition, with_label: with_label)

      params["action"] == "remove_rule" ->
        Condition.remove_rule(current_condition, params["rule-id"])

      true ->
        apply_rule_field_update(current_condition, params)
    end
  end

  defp apply_rule_field_update(current_condition, params) do
    # Use _target from phx-change to identify which field was changed
    target = params["_target"] || []
    target_field = List.first(target)

    rule_update =
      cond do
        # If we have a target, only process that specific field
        target_field && String.starts_with?(target_field, "rule_page_") ->
          rule_id = String.replace_prefix(target_field, "rule_page_", "")
          {:page, rule_id, params[target_field]}

        target_field && String.starts_with?(target_field, "rule_variable_") ->
          rule_id = String.replace_prefix(target_field, "rule_variable_", "")
          {:variable, rule_id, params[target_field]}

        target_field && String.starts_with?(target_field, "rule_operator_") ->
          rule_id = String.replace_prefix(target_field, "rule_operator_", "")
          {:operator, rule_id, params[target_field]}

        target_field && String.starts_with?(target_field, "rule_value_") ->
          rule_id = String.replace_prefix(target_field, "rule_value_", "")
          {:value, rule_id, params[target_field]}

        target_field && String.starts_with?(target_field, "rule_label_") ->
          rule_id = String.replace_prefix(target_field, "rule_label_", "")
          {:label, rule_id, params[target_field]}

        # Fallback: find any rule field (for non-form events)
        true ->
          Enum.find_value(params, fn
            {"rule_page_" <> rule_id, value} -> {:page, rule_id, value}
            {"rule_variable_" <> rule_id, value} -> {:variable, rule_id, value}
            {"rule_operator_" <> rule_id, value} -> {:operator, rule_id, value}
            {"rule_value_" <> rule_id, value} -> {:value, rule_id, value}
            {"rule_label_" <> rule_id, value} -> {:label, rule_id, value}
            _ -> nil
          end)
      end

    case rule_update do
      {field, rule_id, value} ->
        Condition.update_rule(current_condition, rule_id, Atom.to_string(field), value)

      nil ->
        current_condition
    end
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

  defp reload_flow_data(socket) do
    flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
    flow_data = Flows.serialize_for_canvas(flow)
    flow_hubs = Flows.list_hubs(flow.id)

    socket
    |> assign(:flow, flow)
    |> assign(:flow_data, flow_data)
    |> assign(:flow_hubs, flow_hubs)
  end

  defp get_speaker_name(_socket, nil), do: nil

  defp get_speaker_name(socket, speaker_page_id) do
    Enum.find_value(socket.assigns.leaf_pages, fn page ->
      if to_string(page.id) == to_string(speaker_page_id), do: page.name
    end)
  end

  # Counts how many dialogue nodes with the same speaker exist in the flow
  # Returns the position of the current node (1-indexed)
  defp count_speaker_in_flow(flow, speaker_page_id, current_node_id) do
    flow = Repo.preload(flow, :nodes)

    # Get all dialogue nodes with same speaker, ordered by creation
    same_speaker_nodes =
      flow.nodes
      |> Enum.filter(fn node ->
        node.type == "dialogue" &&
          to_string(node.data["speaker_page_id"]) == to_string(speaker_page_id)
      end)
      |> Enum.sort_by(& &1.inserted_at)

    # Find position of current node (1-indexed)
    case Enum.find_index(same_speaker_nodes, &(&1.id == current_node_id)) do
      nil -> length(same_speaker_nodes) + 1
      index -> index + 1
    end
  end

end
