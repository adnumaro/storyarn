defmodule StoryarnWeb.FlowLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Live.Shared.RestorationHandlers

  import StoryarnWeb.Components.CollaborationComponents
  import StoryarnWeb.FlowLive.Components.BuilderPanel
  import StoryarnWeb.FlowLive.Components.DebugPanel
  import StoryarnWeb.FlowLive.Components.FlowDock
  import StoryarnWeb.FlowLive.Components.FlowHeader
  import StoryarnWeb.Components.CanvasToolbar
  import StoryarnWeb.Components.RightSidebar
  import StoryarnWeb.FlowLive.Components.FlowToolbar
  import StoryarnWeb.Live.Shared.TreePanelHandlers

  alias StoryarnWeb.Components.Sidebar.FlowTree
  alias StoryarnWeb.FlowLive.Components.ScreenplayEditor

  alias StoryarnWeb.Components.DraftComponents
  alias StoryarnWeb.Live.Shared.DraftHandlers

  alias Storyarn.Collaboration
  alias Storyarn.Drafts
  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias StoryarnWeb.FlowLive.Handlers.CollaborationEventHandlers
  alias StoryarnWeb.FlowLive.Handlers.DebugHandlers
  alias StoryarnWeb.FlowLive.Handlers.EditorInfoHandlers
  alias StoryarnWeb.FlowLive.Handlers.GenericNodeHandlers
  alias StoryarnWeb.FlowLive.Handlers.NavigationHandlers
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers
  alias StoryarnWeb.FlowLive.Helpers.ConnectionHelpers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.NavigationHistory
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers
  alias StoryarnWeb.FlowLive.Helpers.SocketHelpers
  alias StoryarnWeb.FlowLive.Nodes.Condition
  alias StoryarnWeb.FlowLive.Nodes.Dialogue
  alias StoryarnWeb.FlowLive.Nodes.Exit, as: ExitNode
  alias StoryarnWeb.FlowLive.Nodes.Instruction
  alias StoryarnWeb.FlowLive.Nodes.SlugLine
  alias StoryarnWeb.FlowLive.Nodes.Subflow
  alias StoryarnWeb.FlowLive.NodeTypeRegistry
  alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: Collab

  # Node types are now rendered by flow_dock.ex
  @lock_heartbeat_interval 10_000

  @impl true
  def render(%{loading: true} = assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:flows}
      has_tree={@flows_tree != []}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      can_edit={@can_edit}
      canvas_mode={true}
      restoration_banner={@restoration_banner}
      my_drafts={@my_drafts}
      renaming_draft={@renaming_draft}
    >
      <:tree_content>
        <FlowTree.flows_section
          flows_tree={@flows_tree}
          workspace={@workspace}
          project={@project}
          selected_flow_id={@flow && to_string(@flow.id)}
          can_edit={@can_edit}
        />
      </:tree_content>
      <FlowTree.delete_modal :if={@can_edit} />
      <div id={"flow-loader-#{@flow && @flow.id}"} phx-hook="FlowLoader" class="hidden"></div>
    </Layouts.focus>
    """
  end

  def render(%{compact: true, loading: true} = assigns) do
    ~H"""
    <Layouts.compare flash={@flash}>
      <div id={"flow-loader-#{@flow && @flow.id}"} phx-hook="FlowLoader" class="hidden"></div>
    </Layouts.compare>
    """
  end

  def render(%{compact: true} = assigns) do
    render_compact(assigns)
  end

  def render(assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:flows}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      can_edit={@can_edit}
      online_users={@online_users}
      canvas_mode={true}
      restoration_banner={@restoration_banner}
      my_drafts={@my_drafts}
      renaming_draft={@renaming_draft}
    >
      <:top_bar_extra>
        <DraftComponents.draft_banner is_draft={@is_draft} />
        <.flow_info_bar
          flow={@flow}
          can_edit={@can_edit}
          save_status={@save_status}
          nav_history={@nav_history}
          scene_name={@scene_name}
          scene_inherited={@scene_inherited}
          available_scenes={@available_scenes}
          flow_word_count={@flow_word_count}
          flow_error_nodes={@flow_error_nodes}
          flow_info_nodes={@flow_info_nodes}
          is_draft={@is_draft}
        />
      </:top_bar_extra>
      <:tree_content>
        <FlowTree.flows_section
          flows_tree={@flows_tree}
          workspace={@workspace}
          project={@project}
          selected_flow_id={@flow && to_string(@flow.id)}
          can_edit={@can_edit}
        />
      </:tree_content>
      <FlowTree.delete_modal :if={@can_edit} />
      <DraftComponents.discard_draft_modal is_draft={@is_draft} />
      <DraftComponents.merge_review_modal is_draft={@is_draft} merge_summary={@merge_summary} />
      <div class="h-full relative">
        <%!-- Canvas fills the entire area --%>
        <div class="absolute inset-0 flex flex-col">
          <div class="flex-1 relative bg-base-200">
            <div
              id={"flow-canvas-#{@flow.id}"}
              phx-hook="FlowCanvas"
              phx-update="ignore"
              class="absolute inset-0"
              data-flow={Jason.encode!(@flow_data)}
              data-sheets={Jason.encode!(FormHelpers.sheets_map(@all_sheets, @gallery_by_sheet))}
              data-locks={Jason.encode!(@node_locks)}
              data-user-id={@current_scope.user.id}
              data-user-color={Collaboration.user_color(@current_scope.user.id)}
              data-labels={Jason.encode!(flow_canvas_labels())}
            >
            </div>

            <%!-- Floating Toolbar --%>
            <.canvas_toolbar
              id="flow-floating-toolbar"
              canvas_id={"flow-canvas-#{@flow.id}"}
              visible={@selected_node != nil && @editing_mode in [:toolbar, :annotation]}
            >
              <%= if @editing_mode == :annotation do %>
                <.annotation_toolbar node={@selected_node} can_edit={@can_edit} />
              <% else %>
                <.node_toolbar
                  node={@selected_node}
                  form={@node_form}
                  can_edit={@can_edit}
                  all_sheets={@all_sheets}
                  gallery_by_sheet={@gallery_by_sheet}
                  flow_hubs={@flow_hubs}
                  available_flows={@available_flows}
                  available_scenes={assigns[:available_scenes] || []}
                  flow_search_has_more={@flow_search_has_more}
                  flow_search_deep={@flow_search_deep}
                  subflow_exits={@subflow_exits}
                  referencing_jumps={@referencing_jumps}
                  referencing_flows={@referencing_flows}
                  project_scenes={@project_scenes}
                  node_select_loading={@node_select_loading}
                />
              <% end %>
            </.canvas_toolbar>

            <%!-- Bottom dock --%>
            <.flow_dock
              flow={@flow}
              workspace={@workspace}
              project={@project}
              can_edit={@can_edit}
              debug_panel_open={@debug_panel_open}
            />

            <%!-- Version History Panel --%>
            <.right_sidebar
              id="flow-versions-panel"
              title={dgettext("flows", "Version History")}
              open_event="open_versions_panel"
              close_event="close_versions_panel"
              width="320px"
              loading={!@versions_panel_open}
            >
              <:actions>
                <button
                  :if={@can_edit && @versions_panel_open}
                  type="button"
                  class="btn btn-ghost btn-xs btn-square"
                  phx-click="show_create_version_modal"
                >
                  <.icon name="plus" class="size-4" />
                </button>
              </:actions>
              <.live_component
                :if={@versions_panel_open}
                module={StoryarnWeb.Components.VersionsSection}
                id="flow-versions-section"
                entity={@flow}
                entity_type="flow"
                project_id={@project.id}
                current_user_id={@current_scope.user.id}
                can_edit={@can_edit}
                current_version_id={@flow.current_version_id}
                workspace_id={@workspace.id}
              />
            </.right_sidebar>
          </div>

          <.debug_panel
            :if={@debug_panel_open && @debug_state}
            debug_state={@debug_state}
            debug_active_tab={@debug_active_tab}
            debug_nodes={@debug_nodes}
            debug_auto_playing={@debug_auto_playing}
            debug_speed={@debug_speed}
            debug_editing_var={@debug_editing_var}
            debug_var_filter={@debug_var_filter}
            debug_var_changed_only={@debug_var_changed_only}
            debug_current_flow_name={@flow.name}
            debug_step_limit_reached={@debug_step_limit_reached}
          />
        </div>

        <%!-- Collaboration Toast --%>
        <.collab_toast
          :if={@collab_toast}
          action={@collab_toast.action}
          user_email={@collab_toast.user_email}
          user_color={@collab_toast.user_color}
        />
      </div>

      <%!-- Builder Sidebar (condition / instruction nodes) --%>
      <div
        id="builder-sidebar"
        phx-hook="RightSidebar"
        data-right-panel
        data-open-event="open_builder"
        data-close-event="close_builder"
        class={[
          "fixed flex flex-col overflow-hidden right-sidebar",
          "inset-0 z-[1030] bg-base-100",
          "xl:inset-auto xl:right-3 xl:top-[76px] xl:bottom-3 xl:w-[480px]"
        ]}
      >
        <div :if={@selected_node && @editing_mode == :builder}>
          <.builder_content
            node={@selected_node}
            form={@node_form}
            can_edit={@can_edit}
            project_variables={@project_variables}
            panel_sections={@panel_sections}
          />
        </div>
        <div
          :if={!(@selected_node && @editing_mode == :builder)}
          class="flex items-center justify-center h-full"
        >
          <span class="loading loading-spinner loading-md text-base-content/40"></span>
        </div>
      </div>

      <%!-- Screenplay Editor sidebar --%>
      <.live_component
        :if={@selected_node && @editing_mode in [:screenplay, :editor]}
        module={ScreenplayEditor}
        id={"screenplay-editor-#{@selected_node.id}"}
        node={@selected_node}
        can_edit={@can_edit}
        all_sheets={@all_sheets}
        project_variables={@project_variables}
        project={@project}
        current_user={@current_scope.user}
        panel_sections={@panel_sections}
      />

      <%!-- Preview Modal --%>
      <.live_component
        module={StoryarnWeb.FlowLive.PreviewComponent}
        id="flow-preview"
        show={@preview_show}
        start_node={@preview_node}
        project={@project}
        sheets_map={FormHelpers.sheets_map(@all_sheets)}
      />
    </Layouts.focus>
    """
  end

  defp render_compact(assigns) do
    ~H"""
    <Layouts.compare flash={@flash}>
      <div class="h-full relative">
        <%!-- Canvas fills the entire area --%>
        <div class="absolute inset-0 flex flex-col">
          <div class="flex-1 relative bg-base-200">
            <div
              id={"flow-canvas-#{@flow.id}"}
              phx-hook="FlowCanvas"
              phx-update="ignore"
              class="absolute inset-0"
              data-flow={Jason.encode!(@flow_data)}
              data-sheets={Jason.encode!(FormHelpers.sheets_map(@all_sheets, @gallery_by_sheet))}
              data-locks={Jason.encode!(@node_locks)}
              data-user-id={@current_scope.user.id}
              data-user-color={Collaboration.user_color(@current_scope.user.id)}
              data-labels={Jason.encode!(flow_canvas_labels())}
            >
            </div>

            <%!-- Floating Toolbar --%>
            <.canvas_toolbar
              id="flow-floating-toolbar"
              canvas_id={"flow-canvas-#{@flow.id}"}
              visible={@selected_node != nil && @editing_mode in [:toolbar, :annotation]}
            >
              <%= if @editing_mode == :annotation do %>
                <.annotation_toolbar node={@selected_node} can_edit={@can_edit} />
              <% else %>
                <.node_toolbar
                  node={@selected_node}
                  form={@node_form}
                  can_edit={@can_edit}
                  all_sheets={@all_sheets}
                  gallery_by_sheet={@gallery_by_sheet}
                  flow_hubs={@flow_hubs}
                  available_flows={@available_flows}
                  available_scenes={assigns[:available_scenes] || []}
                  flow_search_has_more={@flow_search_has_more}
                  flow_search_deep={@flow_search_deep}
                  subflow_exits={@subflow_exits}
                  referencing_jumps={@referencing_jumps}
                  referencing_flows={@referencing_flows}
                  project_scenes={@project_scenes}
                  node_select_loading={@node_select_loading}
                />
              <% end %>
            </.canvas_toolbar>

            <%!-- Bottom dock --%>
            <.flow_dock
              flow={@flow}
              workspace={@workspace}
              project={@project}
              can_edit={@can_edit}
              debug_panel_open={@debug_panel_open}
              compact={true}
            />
          </div>
        </div>
      </div>

      <%!-- Builder Sidebar (condition / instruction nodes) --%>
      <div
        id="builder-sidebar"
        phx-hook="RightSidebar"
        data-right-panel
        data-open-event="open_builder"
        data-close-event="close_builder"
        class={[
          "fixed flex flex-col overflow-hidden right-sidebar",
          "inset-0 z-[1030] bg-base-100",
          "xl:inset-auto xl:right-3 xl:top-3 xl:bottom-3 xl:w-[480px]"
        ]}
      >
        <div :if={@selected_node && @editing_mode == :builder}>
          <.builder_content
            node={@selected_node}
            form={@node_form}
            can_edit={@can_edit}
            project_variables={@project_variables}
            panel_sections={@panel_sections}
          />
        </div>
        <div
          :if={!(@selected_node && @editing_mode == :builder)}
          class="flex items-center justify-center h-full"
        >
          <span class="loading loading-spinner loading-md text-base-content/40"></span>
        </div>
      </div>

      <%!-- Screenplay Editor sidebar --%>
      <.live_component
        :if={@selected_node && @editing_mode in [:screenplay, :editor]}
        module={ScreenplayEditor}
        id={"screenplay-editor-#{@selected_node.id}"}
        node={@selected_node}
        can_edit={@can_edit}
        all_sheets={@all_sheets}
        project_variables={@project_variables}
        project={@project}
        current_user={@current_scope.user}
        panel_sections={@panel_sections}
      />
    </Layouts.compare>
    """
  end

  # ===========================================================================
  # Mount & Setup
  # ===========================================================================

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(socket.assigns.current_scope, workspace_slug, project_slug) do
      {:ok, project, membership} ->
        can_edit = Projects.can?(membership.role, :edit_content)

        if connected?(socket), do: Collaboration.subscribe_restoration(project.id)

        {can_edit, restoration_banner} =
          RestorationHandlers.check_restoration_lock(project.id, can_edit)

        socket =
          socket
          |> assign(focus_layout_defaults())
          |> assign(:compact, false)
          |> assign(:loading, true)
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:restoration_banner, restoration_banner)
          # Defaults — flow loaded in handle_params
          |> assign(:flow, nil)
          |> assign(:nav_history, nil)
          |> assign(:flows_tree, Flows.list_flows_tree(project.id))
          |> assign(:pending_delete_id, nil)
          |> assign(:scene_name, nil)
          |> assign(:scene_inherited, false)
          |> assign(:available_scenes, [])
          |> assign(:flow_word_count, 0)
          |> assign(:flow_error_nodes, [])
          |> assign(:flow_info_nodes, [])
          |> assign(:is_draft, false)
          |> assign(:draft, nil)
          |> assign(:merge_summary, nil)
          |> assign(:renaming_draft, nil)
          |> assign(:_draft_touch_ref, nil)
          |> assign(
            :my_drafts,
            Drafts.list_my_drafts(project.id, socket.assigns.current_scope.user.id)
          )

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("flows", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  defp maybe_restore_debug_session(socket) do
    user_id = socket.assigns.current_scope.user.id
    project_id = socket.assigns.project.id

    case Flows.debug_session_take({user_id, project_id}) do
      nil ->
        socket

      debug_assigns ->
        socket =
          if debug_assigns.debug_auto_playing do
            ref = Process.send_after(self(), :debug_auto_step, debug_assigns.debug_speed)
            assign(socket, :debug_auto_timer, ref)
          else
            socket
          end

        socket
        |> assign(:debug_state, debug_assigns.debug_state)
        |> assign(:debug_panel_open, debug_assigns.debug_panel_open)
        |> assign(:debug_active_tab, debug_assigns.debug_active_tab)
        |> assign(:debug_nodes, debug_assigns.debug_nodes)
        |> assign(:debug_connections, debug_assigns.debug_connections)
        |> assign(:debug_speed, debug_assigns.debug_speed)
        |> assign(:debug_auto_playing, debug_assigns.debug_auto_playing)
        |> assign(:debug_editing_var, debug_assigns.debug_editing_var)
        |> assign(:debug_var_filter, debug_assigns.debug_var_filter)
        |> assign(:debug_var_changed_only, debug_assigns.debug_var_changed_only)
        |> assign(:debug_step_limit_reached, debug_assigns[:debug_step_limit_reached] || false)
        |> push_debug_canvas_events(debug_assigns.debug_state)
    end
  end

  defp push_debug_canvas_events(socket, state) do
    # execution_path is stored newest-first; reverse for display
    path = Enum.reverse(state.execution_path)

    socket
    |> push_event("debug_highlight_node", %{
      node_id: state.current_node_id,
      status: to_string(state.status),
      execution_path: path
    })
    |> push_event("debug_highlight_connections", %{
      active_connection: nil,
      execution_path: path
    })
    |> push_event("debug_update_breakpoints", %{
      breakpoint_ids: MapSet.to_list(state.breakpoints)
    })
  end

  @impl true
  def handle_params(%{"id" => _flow_id, "draft_id" => draft_id} = params, _url, socket) do
    compact = params["layout"] == "compact"
    {:noreply, socket |> assign(:compact, compact) |> load_draft_flow(draft_id)}
  end

  def handle_params(%{"id" => flow_id} = params, _url, socket) do
    compact = params["layout"] == "compact"
    socket = assign(socket, :compact, compact)

    current_id =
      case socket.assigns.flow do
        %{id: id} -> to_string(id)
        _ -> nil
      end

    if flow_id == current_id do
      # Same flow — just handle ?node= param
      if socket.assigns.loading do
        {:noreply, socket}
      else
        {:noreply, maybe_navigate_to_node(socket, params["node"])}
      end
    else
      {:noreply, load_flow(socket, flow_id)}
    end
  end

  defp load_draft_flow(socket, draft_id) do
    %{project: project, current_scope: scope} = socket.assigns

    with draft when not is_nil(draft) <- Drafts.get_my_draft(draft_id, scope.user.id, project.id),
         true <- draft.entity_type == "flow" and draft.status == "active",
         entity when not is_nil(entity) <- Drafts.get_draft_entity(draft) do
      socket
      |> assign(:loading, true)
      |> assign(:is_draft, true)
      |> assign(:draft, draft)
      |> assign(:flow, entity)
    else
      _ ->
        socket
        |> put_flash(:error, dgettext("flows", "Draft not found."))
        |> push_navigate(
          to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )
    end
  end

  defp load_flow(socket, flow_id) do
    %{project: project} = socket.assigns

    case Flows.get_flow_brief(project.id, flow_id) do
      nil ->
        socket
        |> put_flash(:error, dgettext("flows", "Flow not found."))
        |> push_navigate(
          to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      flow ->
        # Teardown collaboration for previous flow (if switching)
        case socket.assigns.flow do
          %{id: prev_id} when prev_id != flow.id ->
            CollaborationHelpers.teardown_collaboration(
              prev_id,
              socket.assigns.current_scope.user.id
            )

          _ ->
            :ok
        end

        socket
        |> assign(:loading, true)
        |> assign(:flow, flow)
    end
  end

  defp maybe_navigate_to_node(socket, nil), do: socket

  defp maybe_navigate_to_node(socket, node_id) do
    case Integer.parse(node_id) do
      {id, ""} -> push_event(socket, "navigate_to_node", %{node_db_id: id})
      _ -> socket
    end
  end

  # ===========================================================================
  # Event Handlers (thin delegation)
  # ===========================================================================

  @impl true
  # Tree panel events (from FocusLayout)
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

  def handle_event("open_versions_panel", _params, %{assigns: %{compact: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("open_versions_panel", _params, socket) do
    {:noreply, assign(socket, :versions_panel_open, true)}
  end

  def handle_event("close_versions_panel", _params, socket) do
    {:noreply, assign(socket, :versions_panel_open, false)}
  end

  def handle_event("show_create_version_modal", _params, socket) do
    send_update(StoryarnWeb.Components.VersionsSection,
      id: "flow-versions-section",
      action: :show_create_version_modal
    )

    {:noreply, socket}
  end

  # Triggered by the FlowLoader hook after the browser has painted the spinner.
  def handle_event("load_flow_data", _params, socket) do
    %{flow: flow, project: project, is_draft: is_draft} = socket.assigns

    socket =
      start_async(socket, :load_flow_data, fn ->
        full_flow = Flows.get_flow!(project.id, flow.id, include_drafts: is_draft)
        project_variables = Sheets.list_project_variables(project.id)

        %{
          flow: full_flow,
          flow_data: Flows.serialize_for_canvas(full_flow, project_variables: project_variables),
          all_sheets: Sheets.list_all_sheets(project.id),
          gallery_by_sheet: Sheets.batch_load_gallery_data_by_sheet(project.id),
          flow_hubs: Flows.list_hubs(flow.id),
          project_variables: project_variables,
          flows_tree: Flows.list_flows_tree(project.id),
          available_scenes: Scenes.list_scenes(project.id)
        }
      end)

    {:noreply, socket}
  end

  def handle_event("add_node", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_add_node(params, socket)
    end)
  end

  def handle_event("add_annotation", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_add_node(
        %{
          "type" => "annotation",
          "position_x" => params["position_x"] || 100,
          "position_y" => params["position_y"] || 100
        },
        socket
      )
    end)
  end

  def handle_event("save_name", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_save_name(params, socket)
    end)
  end

  def handle_event("save_shortcut", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_save_shortcut(params, socket)
    end)
  end

  def handle_event("restore_flow_meta", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_restore_flow_meta(params, socket)
    end)
  end

  def handle_event("node_selected", params, socket) do
    GenericNodeHandlers.handle_node_selected(params, socket)
  end

  def handle_event("node_double_clicked", params, socket) do
    GenericNodeHandlers.handle_node_double_clicked(params, socket)
  end

  def handle_event("open_screenplay", params, socket) do
    Dialogue.Node.handle_open_screenplay(params, socket)
  end

  def handle_event("open_sidebar", _params, socket) do
    GenericNodeHandlers.handle_open_sidebar(socket)
  end

  def handle_event("open_builder", _params, socket) do
    case socket.assigns.selected_node do
      nil ->
        {:noreply, socket}

      node ->
        socket =
          socket
          |> assign(:editing_mode, :builder)
          |> push_event("center_on_node", %{id: node.id, sidebar_width: 480})

        {:noreply, socket}
    end
  end

  def handle_event("close_builder", _params, socket) do
    {:noreply, assign(socket, :editing_mode, :toolbar)}
  end

  def handle_event("close_editor", _params, socket) do
    GenericNodeHandlers.handle_close_editor(socket)
  end

  def handle_event("deselect_node", _params, socket) do
    GenericNodeHandlers.handle_deselect_node(socket)
  end

  def handle_event("create_sheet", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_create_sheet(socket)
    end)
  end

  def handle_event("node_dragging", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_node_dragging(params, socket)
    end)
  end

  def handle_event("node_moved", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_node_moved(params, socket)
    end)
  end

  def handle_event("batch_update_positions", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_batch_update_positions(params, socket)
    end)
  end

  def handle_event("search_available_flows", params, socket) do
    GenericNodeHandlers.handle_search_available_flows(params, socket)
  end

  def handle_event("search_flows_more", _params, socket) do
    GenericNodeHandlers.handle_search_flows_more(socket)
  end

  def handle_event("toggle_deep_search", _params, socket) do
    GenericNodeHandlers.handle_toggle_deep_search(socket)
  end

  def handle_event("update_node_data", %{"node" => _} = params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_update_node_data(params, socket)
    end)
  end

  # Catch-all for update_node_data events without the "node" key (no-op)
  def handle_event("update_node_data", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_node_text", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_update_node_text(params, socket)
    end)
  end

  def handle_event("mention_suggestions", params, socket) do
    GenericNodeHandlers.handle_mention_suggestions(params, socket)
  end

  def handle_event("delete_node", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_delete_node(params, socket)
    end)
  end

  def handle_event("restore_node", %{"id" => node_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      NodeHelpers.restore_node(socket, node_id)
    end)
  end

  def handle_event("restore_node_data", %{"id" => node_id, "data" => data}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      NodeHelpers.restore_node_data(socket, node_id, data)
    end)
  end

  def handle_event("duplicate_node", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_duplicate_node(params, socket)
    end)
  end

  def handle_event("generate_technical_id", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      node = socket.assigns.selected_node

      cond do
        node && node.type == "dialogue" ->
          Dialogue.Node.handle_generate_technical_id(socket)

        node && node.type == "exit" ->
          ExitNode.Node.handle_generate_technical_id(socket)

        node && node.type == "slug_line" ->
          SlugLine.Node.handle_generate_technical_id(socket)

        true ->
          {:noreply, socket}
      end
    end)
  end

  def handle_event("update_node_field", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_update_node_field(params, socket)
    end)
  end

  def handle_event("update_annotation_color", %{"value" => color}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      update_selected_node_data(socket, "color", color)
    end)
  end

  def handle_event("update_annotation_font_size", %{"value" => size}, socket)
      when size in ["sm", "md", "lg"] do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      update_selected_node_data(socket, "font_size", size)
    end)
  end

  # Responses (dialogue-specific)
  def handle_event("add_response", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_add_response(params, socket)
    end)
  end

  def handle_event("remove_response", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_remove_response(params, socket)
    end)
  end

  def handle_event("update_response_text", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_update_response_text(params, socket)
    end)
  end

  def handle_event("update_response_condition", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_update_response_condition(params, socket)
    end)
  end

  def handle_event("update_response_instruction", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_update_response_instruction(params, socket)
    end)
  end

  def handle_event("update_response_instruction_builder", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_update_response_instruction_builder(params, socket)
    end)
  end

  # Connections
  def handle_event("connection_created", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ConnectionHelpers.create_connection(socket, params)
    end)
  end

  def handle_event(
        "connection_deleted",
        %{"source_node_id" => source_id, "target_node_id" => target_id},
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ConnectionHelpers.delete_connection_by_nodes(socket, source_id, target_id)
    end)
  end

  # Condition builders
  def handle_event("update_response_condition_builder", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Condition.Node.handle_update_response_condition_builder(params, socket)
    end)
  end

  def handle_event("update_condition_builder", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Condition.Node.handle_update_condition_builder(params, socket)
    end)
  end

  def handle_event("toggle_switch_mode", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Condition.Node.handle_toggle_switch_mode(socket)
    end)
  end

  # Instruction builder
  def handle_event("update_instruction_builder", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Instruction.Node.handle_update_instruction_builder(params, socket)
    end)
  end

  # Expression editor tab toggle (Builder ↔ Code)
  def handle_event("toggle_expression_tab", %{"id" => id, "tab" => tab}, socket) do
    panel_sections = Map.put(socket.assigns.panel_sections, "tab_#{id}", tab)
    {:noreply, assign(socket, :panel_sections, panel_sections)}
  end

  # Subflow
  def handle_event("navigate_to_subflow", %{"flow-id" => flow_id_str}, socket) do
    NavigationHandlers.handle_navigate_to_flow(flow_id_str, socket)
  end

  def handle_event("nav_back", _params, %{assigns: %{nav_history: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("nav_back", _params, socket) do
    case NavigationHistory.back(socket.assigns.nav_history) do
      {:ok, entry, updated_history} ->
        store_nav_history(socket, updated_history)

        {:noreply,
         push_patch(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{entry.flow_id}"
         )}

      :at_start ->
        {:noreply, socket}
    end
  end

  def handle_event("nav_forward", _params, %{assigns: %{nav_history: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("nav_forward", _params, socket) do
    case NavigationHistory.forward(socket.assigns.nav_history) do
      {:ok, entry, updated_history} ->
        store_nav_history(socket, updated_history)

        {:noreply,
         push_patch(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{entry.flow_id}"
         )}

      :at_end ->
        {:noreply, socket}
    end
  end

  def handle_event("update_subflow_reference", %{"referenced_flow_id" => ref_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Subflow.Node.handle_update_reference(ref_id, socket)
    end)
  end

  # Create linked flow (exit flow_reference / subflow)
  def handle_event("create_linked_flow", %{"node-id" => node_id_str}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      case Flows.get_node(socket.assigns.flow.id, node_id_str) do
        nil ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Node not found."))}

        node ->
          do_create_linked_flow(socket, node)
      end
    end)
  end

  # Exit node events
  def handle_event("update_exit_mode", %{"mode" => mode}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_update_exit_mode(mode, socket)
    end)
  end

  def handle_event("update_exit_reference", %{"flow-id" => flow_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_update_exit_reference(flow_id, socket)
    end)
  end

  def handle_event("add_outcome_tag", %{"tag" => tag}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_add_outcome_tag(tag, socket)
    end)
  end

  def handle_event("remove_outcome_tag", %{"tag" => tag}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_remove_outcome_tag(tag, socket)
    end)
  end

  def handle_event("update_outcome_color", %{"value" => color}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_update_outcome_color(color, socket)
    end)
  end

  def handle_event("update_exit_target", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_update_exit_target(params, socket)
    end)
  end

  # Scene map
  def handle_event("update_scene", %{"scene_id" => scene_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      scene_id =
        if scene_id in [nil, "", "null"],
          do: nil,
          else: Storyarn.Shared.MapUtils.parse_int(scene_id)

      case Flows.update_flow_scene(socket.assigns.flow, %{scene_id: scene_id}) do
        {:ok, updated_flow} ->
          {:noreply,
           socket
           |> assign(:flow, updated_flow)
           |> assign_scene_info(updated_flow)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not update scene map."))}
      end
    end)
  end

  # Hub color picker
  def handle_event("update_hub_color", %{"color" => color}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      validated =
        StoryarnWeb.FlowLive.Components.NodeTypeHelpers.validate_hex_color(
          color,
          Flows.hub_colors_default_hex()
        )

      update_selected_node_data(socket, "color", validated)
    end)
  end

  def handle_event("navigate_to_exit_flow", %{"flow-id" => flow_id_str}, socket) do
    NavigationHandlers.handle_navigate_to_flow(flow_id_str, socket)
  end

  def handle_event("navigate_to_referencing_flow", %{"flow-id" => flow_id_str}, socket) do
    NavigationHandlers.handle_navigate_to_flow(flow_id_str, socket)
  end

  # Debug
  def handle_event("debug_start", _params, socket) do
    DebugHandlers.handle_debug_start(socket)
  end

  def handle_event("debug_step", _params, socket) do
    DebugHandlers.handle_debug_step(socket)
  end

  def handle_event("debug_step_back", _params, socket) do
    DebugHandlers.handle_debug_step_back(socket)
  end

  def handle_event("debug_choose_response", params, socket) do
    DebugHandlers.handle_debug_choose_response(params, socket)
  end

  def handle_event("debug_reset", _params, socket) do
    DebugHandlers.handle_debug_reset(socket)
  end

  def handle_event("debug_stop", _params, socket) do
    DebugHandlers.handle_debug_stop(socket)
  end

  def handle_event("debug_tab_change", params, socket) do
    DebugHandlers.handle_debug_tab_change(params, socket)
  end

  def handle_event("debug_play", _params, socket) do
    DebugHandlers.handle_debug_play(socket)
  end

  def handle_event("debug_pause", _params, socket) do
    DebugHandlers.handle_debug_pause(socket)
  end

  def handle_event("debug_set_speed", params, socket) do
    DebugHandlers.handle_debug_set_speed(params, socket)
  end

  def handle_event("debug_edit_variable", params, socket) do
    DebugHandlers.handle_debug_edit_variable(params, socket)
  end

  def handle_event("debug_cancel_edit", _params, socket) do
    DebugHandlers.handle_debug_cancel_edit(socket)
  end

  def handle_event("debug_set_variable", params, socket) do
    DebugHandlers.handle_debug_set_variable(params, socket)
  end

  def handle_event("debug_var_filter", params, socket) do
    DebugHandlers.handle_debug_var_filter(params, socket)
  end

  def handle_event("debug_var_toggle_changed", _params, socket) do
    DebugHandlers.handle_debug_var_toggle_changed(socket)
  end

  def handle_event("debug_change_start_node", params, socket) do
    DebugHandlers.handle_debug_change_start_node(params, socket)
  end

  def handle_event("debug_toggle_breakpoint", params, socket) do
    DebugHandlers.handle_debug_toggle_breakpoint(params, socket)
  end

  def handle_event("debug_continue_past_limit", _params, socket) do
    DebugHandlers.handle_debug_continue_past_limit(socket)
  end

  # Collaboration & Preview
  def handle_event("cursor_moved", params, socket) do
    CollaborationEventHandlers.handle_cursor_moved(params, socket)
  end

  def handle_event("start_preview", params, socket) do
    GenericNodeHandlers.handle_start_preview(params, socket)
  end

  def handle_event("request_flow_refresh", _params, socket) do
    EditorInfoHandlers.handle_flow_refresh(socket)
  end

  def handle_event("navigate_to_hub", %{"id" => node_id}, socket) do
    case Integer.parse(node_id) do
      {id, ""} -> {:noreply, push_event(socket, "navigate_to_hub", %{jump_db_id: id})}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("navigate_to_node", %{"id" => node_id}, socket) do
    case Integer.parse(node_id) do
      {id, ""} -> {:noreply, push_event(socket, "navigate_to_node", %{node_db_id: id})}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("navigate_to_jumps", %{"id" => node_id}, socket) do
    case Integer.parse(node_id) do
      {id, ""} -> {:noreply, push_event(socket, "navigate_to_jumps", %{hub_db_id: id})}
      _ -> {:noreply, socket}
    end
  end

  # ===========================================================================
  # Sidebar Tree Event Handlers
  # ===========================================================================

  def handle_event("create_flow", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      handle_create_entity(
        socket,
        %{name: dgettext("flows", "Untitled")},
        &Flows.create_flow/2,
        &flow_path/2,
        dgettext("flows", "Could not create flow."),
        patch: true,
        reload_tree_fn: &reload_flows_tree/1
      )
    end)
  end

  def handle_event("create_child_flow", %{"parent-id" => parent_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      handle_create_child(
        socket,
        parent_id,
        %{name: dgettext("flows", "Untitled")},
        &Flows.create_flow/2,
        &flow_path/2,
        dgettext("flows", "Could not create flow."),
        patch: true,
        reload_tree_fn: &reload_flows_tree/1
      )
    end)
  end

  def handle_event("set_main_flow", %{"id" => flow_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      case Flows.get_flow(socket.assigns.project.id, flow_id) do
        nil ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Flow not found."))}

        flow ->
          do_set_main_flow(socket, flow)
      end
    end)
  end

  def handle_event("create_draft", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      %{flow: flow} = socket.assigns

      DraftHandlers.handle_create_draft(socket, "flow", flow.id, fn s, draft ->
        %{project: project} = s.assigns

        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}/drafts/#{draft.id}"
      end)
    end)
  end

  def handle_event("discard_draft", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      %{project: project} = socket.assigns

      DraftHandlers.handle_discard_draft(
        socket,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
      )
    end)
  end

  def handle_event("load_merge_summary", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      DraftHandlers.handle_load_merge_summary(socket)
    end)
  end

  def handle_event("merge_draft", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      %{draft: draft} = socket.assigns

      DraftHandlers.handle_merge_draft(socket, fn s ->
        %{project: p} = s.assigns

        ~p"/workspaces/#{p.workspace.slug}/projects/#{p.slug}/flows/#{draft.source_entity_id}"
      end)
    end)
  end

  def handle_event("rename_draft_inline", %{"draft-id" => draft_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      DraftHandlers.handle_rename_draft_inline(socket, draft_id)
    end)
  end

  def handle_event("submit_rename_draft", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      DraftHandlers.handle_submit_rename_draft(socket, params)
    end)
  end

  def handle_event("cancel_rename_draft", _params, socket) do
    {:noreply, assign(socket, :renaming_draft, nil)}
  end

  def handle_event("discard_draft_from_list", %{"draft_id" => draft_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      DraftHandlers.handle_discard_draft_from_list(socket, draft_id)
    end)
  end

  def handle_event("set_pending_delete_flow", %{"id" => id}, socket) do
    handle_set_pending_delete(socket, id)
  end

  def handle_event("confirm_delete_flow", _params, socket) do
    handle_confirm_delete(socket, fn socket, id ->
      Authorize.with_authorization(socket, :edit_content, fn _socket ->
        handle_delete_entity(socket, id,
          current_entity_id: socket.assigns.flow.id,
          get_fn: &Flows.get_flow!/2,
          delete_fn: &Flows.delete_flow/1,
          index_path:
            ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows",
          reload_tree_fn: &reload_flows_tree/1,
          success_msg: dgettext("flows", "Flow moved to trash."),
          error_msg: dgettext("flows", "Could not delete flow.")
        )
      end)
    end)
  end

  def handle_event("delete_flow", %{"id" => flow_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      handle_delete_entity(socket, flow_id,
        current_entity_id: socket.assigns.flow.id,
        get_fn: &Flows.get_flow!/2,
        delete_fn: &Flows.delete_flow/1,
        index_path:
          ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows",
        reload_tree_fn: &reload_flows_tree/1,
        success_msg: dgettext("flows", "Flow moved to trash."),
        error_msg: dgettext("flows", "Could not delete flow.")
      )
    end)
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      handle_move_entity(socket, item_id, new_parent_id, position,
        get_fn: &Flows.get_flow!/2,
        move_fn: &Flows.move_flow_to_position/3,
        reload_tree_fn: &reload_flows_tree/1,
        error_msg: dgettext("flows", "Could not move flow.")
      )
    end)
  end

  defp flow_path(socket, flow) do
    ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow.id}"
  end

  defp reload_flows_tree(socket) do
    assign(socket, :flows_tree, Flows.list_flows_tree(socket.assigns.project.id))
  end

  # ===========================================================================
  # Handle Info (thin delegation)
  # ===========================================================================

  @impl true
  def handle_async(:load_flow_data, {:ok, data}, socket) do
    # Replace the brief flow with the fully-preloaded one
    flow = data.flow
    user = socket.assigns.current_scope.user

    unless socket.assigns.is_draft or socket.assigns.compact do
      CollaborationHelpers.setup_collaboration(socket, flow, user)
    end

    {online_users, node_locks} =
      if socket.assigns.is_draft or socket.assigns.compact do
        {[], %{}}
      else
        CollaborationHelpers.get_initial_collab_state(socket, flow)
      end

    # Reuse tree if already loaded (patch navigation)
    flows_tree =
      if socket.assigns.flows_tree != [] do
        socket.assigns.flows_tree
      else
        data.flows_tree
      end

    socket =
      socket
      |> assign(:flow, flow)
      |> assign(:flow_data, data.flow_data)
      |> assign(:flows_tree, flows_tree)
      |> assign(:all_sheets, data.all_sheets)
      |> assign(:gallery_by_sheet, data.gallery_by_sheet)
      |> assign(:flow_hubs, data.flow_hubs)
      |> assign(:project_variables, data.project_variables)
      |> assign(:selected_node, nil)
      |> assign(:node_form, nil)
      |> assign(:node_select_loading, false)
      |> assign(:referencing_jumps, [])
      |> assign(:available_flows, [])
      |> assign(:flow_search_query, "")
      |> assign(:flow_search_offset, 0)
      |> assign(:flow_search_has_more, false)
      |> assign(:flow_search_deep, false)
      |> assign(:subflow_exits, [])
      |> assign(:outcome_tags_suggestions, [])
      |> assign(:referencing_flows, [])
      |> assign(:project_scenes, [])
      |> assign(:editing_mode, nil)
      |> assign(:save_status, :idle)
      |> assign(:preview_show, false)
      |> assign(:preview_node, nil)
      |> assign(:versions_panel_open, false)
      |> then(fn s ->
        if s.assigns.is_draft, do: s, else: assign(s, :collab_scope, {:flow, flow.id})
      end)
      |> assign(:online_users, online_users)
      |> assign(:node_locks, node_locks)
      |> assign(:collab_toast, nil)
      |> assign(:remote_cursors, %{})
      |> assign(:panel_sections, %{})
      |> assign(:debug_state, nil)
      |> assign(:debug_panel_open, false)
      |> assign(:debug_active_tab, "console")
      |> assign(:debug_nodes, %{})
      |> assign(:debug_connections, [])
      |> assign(:debug_speed, 800)
      |> assign(:debug_auto_playing, false)
      |> assign(:debug_editing_var, nil)
      |> assign(:debug_var_filter, "")
      |> assign(:debug_var_changed_only, false)
      |> assign(:debug_auto_timer, nil)
      |> assign(:debug_step_limit_reached, false)
      |> assign(:auto_snapshot_ref, nil)
      |> assign(:auto_snapshot_timer, nil)
      |> assign(:available_scenes, data.available_scenes)
      |> assign(:loading, false)
      |> assign_scene_info(flow)
      |> SocketHelpers.assign_flow_stats(flow, data.flow_data)

    socket =
      socket
      |> maybe_restore_nav_history()
      |> maybe_restore_debug_session()

    {:noreply, socket}
  end

  def handle_async(:load_flow_data, {:exit, _reason}, socket) do
    %{workspace: workspace, project: project} = socket.assigns

    {:noreply,
     socket
     |> put_flash(:error, dgettext("flows", "Could not load flow data."))
     |> redirect(to: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows")}
  end

  # Linked helper processes can terminate normally during flow transitions.
  # Ignore those exits so the editor does not remount while switching flows.
  @impl true
  def handle_info({:EXIT, _pid, :normal}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:project_restoration_started, payload}, socket),
    do:
      RestorationHandlers.handle_restoration_event(
        {:project_restoration_started, payload},
        socket
      )

  @impl true
  def handle_info({:project_restoration_completed, payload}, socket),
    do:
      RestorationHandlers.handle_restoration_event(
        {:project_restoration_completed, payload},
        socket
      )

  @impl true
  def handle_info({:project_restoration_failed, payload}, socket),
    do:
      RestorationHandlers.handle_restoration_event(
        {:project_restoration_failed, payload},
        socket
      )

  @impl true
  def handle_info({:try_auto_snapshot, token}, socket) do
    if token == socket.assigns[:auto_snapshot_ref] do
      %{flow: flow, current_scope: scope} = socket.assigns
      Flows.maybe_create_version(flow, scope.user.id)
      {:noreply, socket |> assign(:auto_snapshot_ref, nil) |> assign(:auto_snapshot_timer, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:reset_save_status, socket) do
    EditorInfoHandlers.handle_reset_save_status(socket)
  end

  # Scheduled by DraftTouchTimer via EditorInfoHandlers.handle_reset_save_status/1
  def handle_info(:touch_draft, socket), do: DraftHandlers.handle_touch_draft(socket)

  def handle_info({:load_node_select_data, node}, socket) do
    socket = NodeTypeRegistry.on_select(node.type, node, socket)
    {:noreply, assign(socket, :node_select_loading, false)}
  end

  # Handle messages from VersionsSection LiveComponent
  def handle_info({:versions_section, :version_created, %{version: _}}, socket) do
    {:noreply, socket}
  end

  def handle_info(
        {:versions_section, :version_restored, %{entity: updated_flow, version: _}},
        socket
      ) do
    # Cancel any pending auto-snapshot (stale after restore)
    socket = StoryarnWeb.Helpers.AutoSnapshot.cancel(socket)

    # Reload full flow data after version restore
    %{project: project} = socket.assigns
    full_flow = Flows.get_flow!(project.id, updated_flow.id)
    project_variables = Sheets.list_project_variables(project.id)
    flow_data = Flows.serialize_for_canvas(full_flow, project_variables: project_variables)

    {:noreply,
     socket
     |> assign(:flow, full_flow)
     |> assign(:flow_data, flow_data)
     |> assign(:flow_hubs, Flows.list_hubs(full_flow.id))
     |> assign(:versions_panel_open, false)
     |> SocketHelpers.assign_flow_stats(full_flow, flow_data)
     |> push_event("flow_updated", flow_data)
     |> push_event("panel-close", %{to: "#flow-versions-panel"})
     |> CollaborationHelpers.broadcast_change(:flow_refresh, %{})}
  end

  def handle_info({:versions_section, :version_deleted, %{version: _}}, socket) do
    {:noreply, socket}
  end

  def handle_info({:versions_section, :compare_version, %{version: version}}, socket) do
    %{workspace: workspace, project: project, flow: flow} = socket.assigns

    compare_url =
      ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{flow.id}/compare/#{version.version_number}"

    {:noreply, push_navigate(socket, to: compare_url)}
  end

  def handle_info({:versions_section, :flash, %{kind: kind, message: message}}, socket) do
    {:noreply, put_flash(socket, kind, message)}
  end

  def handle_info({:node_updated, updated_node}, socket),
    do: EditorInfoHandlers.handle_node_updated(updated_node, socket)

  def handle_info({:close_preview}, socket),
    do: EditorInfoHandlers.handle_close_preview(socket)

  def handle_info({:mention_suggestions, query, component_cid}, socket),
    do: EditorInfoHandlers.handle_mention_suggestions(query, component_cid, socket)

  def handle_info({:variable_suggestions, query, component_cid}, socket),
    do: EditorInfoHandlers.handle_variable_suggestions(query, component_cid, socket)

  def handle_info({:resolve_variable_defaults, refs, component_cid}, socket),
    do: EditorInfoHandlers.handle_resolve_variable_defaults(refs, component_cid, socket)

  def handle_info(:debug_auto_step, socket),
    do: DebugHandlers.handle_debug_auto_step(socket)

  def handle_info(:clear_collab_toast, socket),
    do: CollaborationEventHandlers.handle_clear_collab_toast(socket)

  def handle_info({Storyarn.Collaboration.Presence, {:join, _} = event}, socket),
    do: CollaborationEventHandlers.handle_presence_event(event, socket)

  def handle_info({Storyarn.Collaboration.Presence, {:leave, _} = event}, socket),
    do: CollaborationEventHandlers.handle_presence_event(event, socket)

  def handle_info({:cursor_update, cursor_data}, socket),
    do: CollaborationEventHandlers.handle_cursor_update(cursor_data, socket)

  def handle_info({:cursor_leave, user_id}, socket),
    do: CollaborationEventHandlers.handle_cursor_leave(user_id, socket)

  def handle_info({:lock_change, action, payload}, socket),
    do: CollaborationEventHandlers.handle_lock_change(action, payload, socket)

  def handle_info({:remote_change, action, payload}, socket),
    do: CollaborationEventHandlers.handle_remote_change(action, payload, socket)

  def handle_info({:audio_picker, :selected, asset_id}, socket) do
    case socket.assigns.selected_node do
      nil ->
        {:noreply, socket}

      node ->
        NodeHelpers.persist_node_update(socket, node.id, fn data ->
          Map.put(data, "audio_asset_id", asset_id)
        end)
    end
  end

  def handle_info({:audio_picker, :error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # Lock heartbeat — refresh lock every 10s to prevent expiry during editing
  def handle_info(:refresh_node_lock, socket) do
    if node_id = socket.assigns[:locked_node_id] do
      Collaboration.refresh_lock(
        {:flow, socket.assigns.flow.id},
        node_id,
        socket.assigns.current_scope.user.id
      )

      ref = Process.send_after(self(), :refresh_node_lock, @lock_heartbeat_interval)
      {:noreply, assign(socket, :lock_heartbeat_ref, ref)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:flow] do
      # Cancel heartbeat timer
      if ref = socket.assigns[:lock_heartbeat_ref] do
        Process.cancel_timer(ref)
      end

      # Teardown collaboration (unsubscribe, untrack, release locks)
      if scope = socket.assigns[:collab_scope] do
        user_id = socket.assigns.current_scope.user.id
        Collab.teardown(scope, user_id)
      end
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp flow_canvas_labels do
    %{
      # Root menu
      add_node: dgettext("flows", "Add node"),
      add_note: dgettext("flows", "Add Note"),
      play_preview: dgettext("flows", "Play preview"),
      start_debugging: dgettext("flows", "Start debugging"),
      auto_layout: dgettext("flows", "Auto-layout"),
      # Node types
      dialogue: dgettext("flows", "Dialogue"),
      condition: dgettext("flows", "Condition"),
      instruction: dgettext("flows", "Instruction"),
      hub: dgettext("flows", "Hub"),
      jump: dgettext("flows", "Jump"),
      exit: dgettext("flows", "Exit"),
      subflow: dgettext("flows", "Subflow"),
      slug_line: dgettext("flows", "Slug Line"),
      # Node actions
      open_editor_panel: dgettext("flows", "Open editor panel"),
      preview_from_here: dgettext("flows", "Preview from here"),
      generate_technical_id: dgettext("flows", "Generate technical ID"),
      toggle_switch_mode: dgettext("flows", "Toggle switch mode"),
      locate_referencing_jumps: dgettext("flows", "Locate referencing jumps"),
      locate_target_hub: dgettext("flows", "Locate target hub"),
      open_referenced_flow: dgettext("flows", "Open referenced flow"),
      create_linked_flow: dgettext("flows", "Create linked flow"),
      view_referencing_flows: dgettext("flows", "View referencing flows"),
      duplicate: dgettext("flows", "Duplicate"),
      delete: dgettext("flows", "Delete"),
      # Inline edit
      search: dgettext("flows", "Search…"),
      no_speaker: dgettext("flows", "Dialogue"),
      stage_directions: dgettext("flows", "Stage directions…"),
      dialogue_text: dgettext("flows", "Dialogue text…")
    }
  end

  defp maybe_restore_nav_history(socket) do
    user_id = socket.assigns.current_scope.user.id
    project_id = socket.assigns.project.id
    flow = socket.assigns.flow
    key = {user_id, project_id}

    history = Flows.nav_history_get(key) || NavigationHistory.new(flow.id, flow.name)
    history = NavigationHistory.push(history, flow.id, flow.name)
    Flows.nav_history_put(key, history)

    assign(socket, :nav_history, history)
  end

  defp store_nav_history(socket, history) do
    user_id = socket.assigns.current_scope.user.id
    project_id = socket.assigns.project.id
    Flows.nav_history_put({user_id, project_id}, history)
  end

  defp update_selected_node_data(socket, field, value) do
    case socket.assigns.selected_node do
      nil -> {:noreply, socket}
      node -> NodeHelpers.persist_node_update(socket, node.id, &Map.put(&1, field, value))
    end
  end

  defp do_create_linked_flow(socket, node) do
    case Flows.create_linked_flow(socket.assigns.project, socket.assigns.flow, node) do
      {:ok, %{flow: new_flow}} ->
        {:noreply,
         push_patch(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{new_flow.id}"
         )}

      {:error, :limit_reached, _details} ->
        {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

      {:error, _, _reason, _changes} ->
        {:noreply,
         put_flash(socket, :error, dgettext("flows", "Could not create linked flow."))}
    end
  end

  defp do_set_main_flow(socket, flow) do
    case Flows.set_main_flow(flow) do
      {:ok, _} ->
        {:noreply,
         assign(socket, :flows_tree, Flows.list_flows_tree(socket.assigns.project.id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Could not set main flow."))}
    end
  end

  defp assign_scene_info(socket, flow) do
    resolved_id = Flows.resolve_scene_id(flow)
    is_inherited = resolved_id != nil and resolved_id != flow.scene_id

    scene_name =
      if resolved_id do
        case Scenes.get_scene_brief(socket.assigns.project.id, resolved_id) do
          nil -> nil
          map -> map.name
        end
      end

    socket
    |> assign(:scene_name, scene_name)
    |> assign(:scene_inherited, is_inherited)
  end
end
