defmodule StoryarnWeb.ScreenplayLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Projects
  alias Storyarn.Screenplays
  alias Storyarn.Sheets
  alias StoryarnWeb.Components.ConditionBuilder
  alias StoryarnWeb.Components.InstructionBuilder
  alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: Collab

  import StoryarnWeb.Live.Shared.TreePanelHandlers
  import StoryarnWeb.ScreenplayLive.Helpers.SocketHelpers
  import StoryarnWeb.ScreenplayLive.Components.ScreenplayToolbar

  alias StoryarnWeb.Components.Sidebar.ScreenplayTree
  alias StoryarnWeb.ScreenplayLive.Handlers.EditorHandlers
  alias StoryarnWeb.ScreenplayLive.Handlers.ElementHandlers
  alias StoryarnWeb.ScreenplayLive.Handlers.FlowSyncHandlers
  alias StoryarnWeb.ScreenplayLive.Handlers.FountainImportHandlers
  alias StoryarnWeb.ScreenplayLive.Handlers.LinkedPageHandlers
  alias StoryarnWeb.ScreenplayLive.Handlers.TreeHandlers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:screenplays}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      can_edit={@can_edit}
      online_users={@online_users}
    >
      <:tree_content>
        <ScreenplayTree.screenplays_section
          screenplays_tree={@screenplays_tree}
          workspace={@workspace}
          project={@project}
          selected_screenplay_id={@screenplay && to_string(@screenplay.id)}
          can_edit={@can_edit}
        />
      </:tree_content>
      <ScreenplayTree.delete_modal :if={@can_edit} />
      <%= if @screenplay do %>
        <div class="screenplay-container">
          <.screenplay_toolbar
            screenplay={@screenplay}
            elements={@elements}
            workspace={@workspace}
            project={@project}
            read_mode={@read_mode}
            can_edit={@can_edit}
            link_status={@link_status}
            linked_flow={@linked_flow}
          />
          <div
            id={"screenplay-page-#{@screenplay.id}"}
            class={[
              "screenplay-page",
              @read_mode && "screenplay-read-mode"
            ]}
          >
            <%!-- Unified TipTap editor — ID includes screenplay to force hook remount on patch --%>
            <div
              id={"screenplay-editor-#{@screenplay.id}"}
              phx-hook="ScreenplayEditor"
              data-content={Jason.encode!(@editor_doc)}
              data-can-edit={to_string(@can_edit)}
              data-read-mode={to_string(@read_mode)}
              data-variables={Jason.encode!(@project_variables)}
              data-linked-pages={Jason.encode!(@linked_pages)}
              data-translations={Jason.encode!(screenplay_translations())}
              data-highlight-element={@highlight_element_id}
              phx-update="ignore"
            >
            </div>
          </div>
        </div>
      <% else %>
        <div class="flex justify-center py-12">
          <span class="loading loading-spinner loading-lg text-base-content/30"></span>
        </div>
      <% end %>
    </Layouts.focus>
    """
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug},
        _session,
        socket
      ) do
    if socket.assigns.current_scope.user.is_super_admin do
      mount_screenplay(workspace_slug, project_slug, socket)
    else
      {:ok, socket |> put_flash(:error, gettext("Not found")) |> redirect(to: "/")}
    end
  end

  defp mount_screenplay(workspace_slug, project_slug, socket) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        can_edit = Projects.can?(membership.role, :edit_content)

        {:ok,
         socket
         |> assign(focus_layout_defaults())
         |> assign(:project, project)
         |> assign(:workspace, project.workspace)
         |> assign(:membership, membership)
         |> assign(:can_edit, can_edit)
         |> assign(:read_mode, false)
         |> assign(:pending_delete_id, nil)
         # Defaults — screenplay loaded in handle_params
         |> assign(:screenplay, nil)
         |> assign(:screenplays_tree, [])
         |> assign(:sheets_map, %{})
         |> assign(:elements, [])
         |> assign(:editor_doc, Screenplays.elements_to_doc([]))
         |> assign(:project_variables, [])
         |> assign(:link_status, :unlinked)
         |> assign(:linked_flow, nil)
         |> assign(:linked_pages, %{})
         |> assign(:highlight_element_id, nil)
         |> assign(:online_users, [])
         |> assign(:collab_scope, nil)}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("screenplays", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(%{"id" => screenplay_id} = params, _uri, socket) do
    current_id =
      case socket.assigns.screenplay do
        %{id: id} -> to_string(id)
        _ -> nil
      end

    socket =
      if screenplay_id == current_id do
        socket
      else
        load_screenplay(socket, screenplay_id)
      end

    {:noreply, assign(socket, :highlight_element_id, parse_int(params["element"]))}
  end

  defp load_screenplay(socket, screenplay_id) do
    %{project: project} = socket.assigns
    screenplay = Screenplays.get_screenplay!(project.id, screenplay_id)

    # Teardown previous collaboration scope if switching screenplays
    socket = teardown_screenplay_collab(socket)

    socket =
      socket
      |> assign(:screenplay, screenplay)
      |> assign(:read_mode, false)
      |> assign(:elements, [])
      |> assign(:editor_doc, Screenplays.elements_to_doc([]))
      |> assign(:link_status, :unlinked)
      |> assign(:linked_flow, nil)
      |> assign(:linked_pages, %{})

    if connected?(socket), do: load_connected_data(socket, screenplay), else: socket
  end

  # ---------------------------------------------------------------------------
  # Read mode
  # ---------------------------------------------------------------------------

  @impl true
  # Tree panel events (from FocusLayout)
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

  def handle_event("toggle_read_mode", _params, socket) do
    new_mode = !socket.assigns.read_mode

    {:noreply,
     socket
     |> assign(:read_mode, new_mode)
     |> push_event("set_read_mode", %{read_mode: new_mode})}
  end

  # ---------------------------------------------------------------------------
  # Element editing handlers
  # ---------------------------------------------------------------------------

  def handle_event("delete_element", %{"id" => id}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_delete_element(socket, id) |> broadcast_screenplay_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Unified editor sync handler
  # ---------------------------------------------------------------------------

  def handle_event("sync_editor_content", %{"elements" => client_elements}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      EditorHandlers.do_sync_editor_content(socket, client_elements) |> broadcast_screenplay_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Interactive block handlers
  # ---------------------------------------------------------------------------

  def handle_event(
        "update_screenplay_condition",
        %{"element-id" => id, "condition" => condition},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_update_screenplay_condition(socket, id, condition)
      |> broadcast_screenplay_change()
    end)
  end

  def handle_event(
        "update_screenplay_instruction",
        %{"element-id" => id, "assignments" => assignments},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_update_screenplay_instruction(socket, id, assignments)
      |> broadcast_screenplay_change()
    end)
  end

  def handle_event("add_response_choice", %{"element-id" => id}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_add_response_choice(socket, id) |> broadcast_screenplay_change()
    end)
  end

  def handle_event(
        "remove_response_choice",
        %{"element-id" => id, "choice-id" => choice_id},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_remove_response_choice(socket, id, choice_id)
      |> broadcast_screenplay_change()
    end)
  end

  def handle_event(
        "update_response_choice_text",
        %{"element-id" => id, "choice-id" => choice_id, "value" => text},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_update_response_choice_text(socket, id, choice_id, text)
      |> broadcast_screenplay_change()
    end)
  end

  def handle_event(
        "toggle_choice_condition",
        %{"element-id" => id, "choice-id" => choice_id},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_toggle_choice_condition(socket, id, choice_id)
      |> broadcast_screenplay_change()
    end)
  end

  def handle_event(
        "toggle_choice_instruction",
        %{"element-id" => id, "choice-id" => choice_id},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_toggle_choice_instruction(socket, id, choice_id)
      |> broadcast_screenplay_change()
    end)
  end

  def handle_event(
        "update_response_choice_condition",
        %{"element-id" => id, "choice-id" => choice_id, "condition" => condition},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.update_choice_field(socket, id, choice_id, fn choice ->
        Map.put(choice, "condition", Storyarn.Flows.condition_sanitize(condition))
      end)
      |> broadcast_screenplay_change()
    end)
  end

  def handle_event(
        "update_response_choice_instruction",
        %{"element-id" => id, "choice-id" => choice_id, "assignments" => assignments},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.update_choice_field(socket, id, choice_id, fn choice ->
        Map.put(choice, "instruction", Storyarn.Flows.instruction_sanitize(assignments))
      end)
      |> broadcast_screenplay_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Dual dialogue handlers
  # ---------------------------------------------------------------------------

  def handle_event(
        "update_dual_dialogue",
        %{"element-id" => id, "side" => side, "field" => field, "value" => value},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_update_dual_dialogue(socket, id, side, field, value)
      |> broadcast_screenplay_change()
    end)
  end

  def handle_event(
        "toggle_dual_parenthetical",
        %{"element-id" => id, "side" => side},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_toggle_dual_parenthetical(socket, id, side)
      |> broadcast_screenplay_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Title page handlers
  # ---------------------------------------------------------------------------

  def handle_event(
        "update_title_page",
        %{"element-id" => id, "field" => field, "value" => value},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_update_title_page(socket, id, field, value)
      |> broadcast_screenplay_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Import handler
  # ---------------------------------------------------------------------------

  def handle_event("import_fountain", %{"content" => content}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      FountainImportHandlers.do_import_fountain(socket, content)
      |> broadcast_screenplay_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Linked page handlers
  # ---------------------------------------------------------------------------

  def handle_event(
        "create_linked_page",
        %{"element-id" => eid, "choice-id" => cid},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      LinkedPageHandlers.do_create_linked_page(socket, eid, cid)
      |> broadcast_screenplay_change()
    end)
  end

  def handle_event(
        "navigate_to_linked_page",
        %{"element-id" => eid, "choice-id" => cid},
        socket
      ) do
    LinkedPageHandlers.do_navigate_to_linked_page(socket, eid, cid)
  end

  def handle_event(
        "unlink_choice_screenplay",
        %{"element-id" => eid, "choice-id" => cid},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      LinkedPageHandlers.do_unlink_choice_screenplay(socket, eid, cid)
      |> broadcast_screenplay_change()
    end)
  end

  def handle_event("generate_all_linked_pages", %{"element-id" => eid}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      LinkedPageHandlers.do_generate_all_linked_pages(socket, eid)
      |> broadcast_screenplay_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Character sheet reference handlers
  # ---------------------------------------------------------------------------

  def handle_event("search_character_sheets", params, socket) do
    ElementHandlers.handle_search_character_sheets(params, socket)
  end

  def handle_event("set_character_sheet", %{"id" => id, "sheet_id" => sheet_id}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_set_character_sheet(socket, id, parse_int(sheet_id))
      |> broadcast_screenplay_change()
    end)
  end

  def handle_event("mention_suggestions", params, socket) do
    ElementHandlers.handle_mention_suggestions(params, socket)
  end

  def handle_event("navigate_to_sheet", params, socket) do
    ElementHandlers.handle_navigate_to_sheet(params, socket)
  end

  # ---------------------------------------------------------------------------
  # Toolbar handlers
  # ---------------------------------------------------------------------------

  def handle_event("save_name", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      TreeHandlers.handle_save_name(params, socket) |> broadcast_screenplay_change()
    end)
  end

  def handle_event("create_flow_from_screenplay", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      FlowSyncHandlers.do_create_flow_from_screenplay(socket) |> broadcast_screenplay_change()
    end)
  end

  def handle_event("sync_to_flow", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      FlowSyncHandlers.do_sync_to_flow(socket) |> broadcast_screenplay_change()
    end)
  end

  def handle_event("sync_from_flow", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      FlowSyncHandlers.do_sync_from_flow(socket) |> broadcast_screenplay_change()
    end)
  end

  def handle_event("unlink_flow", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      FlowSyncHandlers.do_unlink_flow(socket) |> broadcast_screenplay_change()
    end)
  end

  def handle_event("navigate_to_flow", _params, socket) do
    FlowSyncHandlers.do_navigate_to_flow(socket)
  end

  # ---------------------------------------------------------------------------
  # Sidebar event handlers
  # ---------------------------------------------------------------------------

  def handle_event("set_pending_delete_screenplay", %{"id" => id}, socket) do
    handle_set_pending_delete(socket, id)
  end

  def handle_event("confirm_delete_screenplay", _params, socket) do
    handle_confirm_delete(socket, fn socket, id ->
      with_authorization(socket, :edit_content, fn _socket ->
        TreeHandlers.do_delete_screenplay(socket, id) |> broadcast_screenplay_change()
      end)
    end)
  end

  def handle_event("delete_screenplay", %{"id" => screenplay_id}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      TreeHandlers.do_delete_screenplay(socket, screenplay_id) |> broadcast_screenplay_change()
    end)
  end

  def handle_event("create_screenplay", _params, socket) do
    TreeHandlers.do_create_screenplay(socket, %{})
  end

  def handle_event("create_child_screenplay", %{"parent-id" => parent_id}, socket) do
    TreeHandlers.do_create_screenplay(socket, %{parent_id: parent_id})
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      TreeHandlers.do_move_to_parent(socket, item_id, new_parent_id, position)
      |> broadcast_screenplay_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Handle Info: Collaboration
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({Storyarn.Collaboration.Presence, {:join, presence}}, socket) do
    Collab.handle_presence_join(socket, presence)
  end

  def handle_info({Storyarn.Collaboration.Presence, {:leave, _} = event}, socket) do
    Collab.handle_presence_leave(socket, elem(event, 1))
  end

  def handle_info({:remote_change, :screenplay_refreshed, _payload}, socket) do
    if socket.assigns.screenplay do
      elements = Screenplays.list_elements(socket.assigns.screenplay.id)

      {:noreply,
       socket
       |> assign_elements_with_editor_doc(elements)
       |> push_event("content_updated", %{doc: Screenplays.elements_to_doc(elements)})}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:remote_change, _action, _payload}, socket) do
    {:noreply, socket}
  end

  def handle_info({:lock_change, _action, _payload}, socket) do
    # Lock tracking available but not used for UI yet
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    teardown_screenplay_collab(socket)
  end

  # ---------------------------------------------------------------------------
  # Private helpers: Collaboration
  # ---------------------------------------------------------------------------

  defp teardown_screenplay_collab(socket) do
    if scope = socket.assigns[:collab_scope] do
      user_id = socket.assigns.current_scope.user.id
      Collab.teardown(scope, user_id)
    end

    socket
  end

  defp broadcast_screenplay_change({:noreply, socket} = result) do
    if scope = socket.assigns[:collab_scope] do
      Collab.broadcast_change(socket, scope, :screenplay_refreshed, %{})
    end

    result
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_connected_data(socket, screenplay) do
    project = socket.assigns.project
    elements = Screenplays.list_elements(screenplay.id)
    {link_status, linked_flow} = FlowSyncHandlers.detect_link_status(screenplay)

    # Setup collaboration
    user = socket.assigns.current_scope.user
    scope = {:screenplay, screenplay.id}
    Collab.setup(socket, scope, user, cursors: false, locks: true, changes: true)
    {online_users, _locks} = Collab.get_initial_state(socket, scope)

    has_tree = socket.assigns.screenplays_tree != []

    socket =
      socket
      |> assign(:collab_scope, scope)
      |> assign(:online_users, online_users)
      |> assign_elements_with_editor_doc(elements)
      |> assign(:link_status, link_status)
      |> assign(:linked_flow, linked_flow)
      |> assign(:linked_pages, LinkedPageHandlers.load_linked_pages(screenplay))

    # Only load shared project data on first mount, reuse on subsequent patches
    if has_tree do
      socket
    else
      project_variables = Sheets.list_project_variables(project.id)
      all_sheets = Sheets.list_all_sheets(project.id)
      sheets_map = Map.new(all_sheets, &{&1.id, &1})
      screenplays_tree = Screenplays.list_screenplays_tree(project.id)

      socket
      |> assign(:screenplays_tree, screenplays_tree)
      |> assign(:sheets_map, sheets_map)
      |> assign(:project_variables, project_variables)
    end
  end

  defp screenplay_translations do
    Map.merge(InstructionBuilder.translations(), ConditionBuilder.translations())
  end
end
