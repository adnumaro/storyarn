defmodule StoryarnWeb.ScreenplayLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Projects
  alias Storyarn.Screenplays
  alias Storyarn.Screenplays.TiptapSerialization
  alias Storyarn.Sheets
  alias StoryarnWeb.Components.ConditionBuilder
  alias StoryarnWeb.Components.InstructionBuilder

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
    >
      <:tree_content>
        <ScreenplayTree.screenplays_section
          screenplays_tree={@screenplays_tree}
          workspace={@workspace}
          project={@project}
          selected_screenplay_id={to_string(@screenplay.id)}
          can_edit={@can_edit}
        />
      </:tree_content>
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
          id="screenplay-page"
          class={[
            "screenplay-page",
            @read_mode && "screenplay-read-mode"
          ]}
        >
          <%!-- Unified TipTap editor — always rendered, read mode toggles editable --%>
          <div
            id="screenplay-editor"
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
    </Layouts.focus>
    """
  end

  @impl true
  def mount(
        %{
          "workspace_slug" => workspace_slug,
          "project_slug" => project_slug,
          "id" => screenplay_id
        },
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        screenplay = Screenplays.get_screenplay!(project.id, screenplay_id)
        can_edit = Projects.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(focus_layout_defaults())
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:screenplay, screenplay)
          |> assign(:read_mode, false)
          # Defaults for disconnected render — real data loaded on connect
          |> assign(:screenplays_tree, [])
          |> assign(:sheets_map, %{})
          |> assign(:elements, [])
          |> assign(:editor_doc, TiptapSerialization.elements_to_doc([]))
          |> assign(:project_variables, [])
          |> assign(:link_status, :unlinked)
          |> assign(:linked_flow, nil)
          |> assign(:linked_pages, %{})
          |> assign(:highlight_element_id, nil)

        socket =
          if connected?(socket), do: load_connected_data(socket, screenplay), else: socket

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("screenplays", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :highlight_element_id, parse_int(params["element"]))}
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
      ElementHandlers.do_delete_element(socket, id)
    end)
  end

  # ---------------------------------------------------------------------------
  # Unified editor sync handler
  # ---------------------------------------------------------------------------

  def handle_event("sync_editor_content", %{"elements" => client_elements}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      EditorHandlers.do_sync_editor_content(socket, client_elements)
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
    end)
  end

  def handle_event(
        "update_screenplay_instruction",
        %{"element-id" => id, "assignments" => assignments},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_update_screenplay_instruction(socket, id, assignments)
    end)
  end

  def handle_event("add_response_choice", %{"element-id" => id}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_add_response_choice(socket, id)
    end)
  end

  def handle_event(
        "remove_response_choice",
        %{"element-id" => id, "choice-id" => choice_id},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_remove_response_choice(socket, id, choice_id)
    end)
  end

  def handle_event(
        "update_response_choice_text",
        %{"element-id" => id, "choice-id" => choice_id, "value" => text},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_update_response_choice_text(socket, id, choice_id, text)
    end)
  end

  def handle_event(
        "toggle_choice_condition",
        %{"element-id" => id, "choice-id" => choice_id},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_toggle_choice_condition(socket, id, choice_id)
    end)
  end

  def handle_event(
        "toggle_choice_instruction",
        %{"element-id" => id, "choice-id" => choice_id},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_toggle_choice_instruction(socket, id, choice_id)
    end)
  end

  def handle_event(
        "update_response_choice_condition",
        %{"element-id" => id, "choice-id" => choice_id, "condition" => condition},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.update_choice_field(socket, id, choice_id, fn choice ->
        Map.put(choice, "condition", Storyarn.Flows.Condition.sanitize(condition))
      end)
    end)
  end

  def handle_event(
        "update_response_choice_instruction",
        %{"element-id" => id, "choice-id" => choice_id, "assignments" => assignments},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.update_choice_field(socket, id, choice_id, fn choice ->
        Map.put(choice, "instruction", Storyarn.Flows.Instruction.sanitize(assignments))
      end)
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
    end)
  end

  def handle_event(
        "toggle_dual_parenthetical",
        %{"element-id" => id, "side" => side},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.do_toggle_dual_parenthetical(socket, id, side)
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
    end)
  end

  # ---------------------------------------------------------------------------
  # Import handler
  # ---------------------------------------------------------------------------

  def handle_event("import_fountain", %{"content" => content}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      FountainImportHandlers.do_import_fountain(socket, content)
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
    end)
  end

  def handle_event("generate_all_linked_pages", %{"element-id" => eid}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      LinkedPageHandlers.do_generate_all_linked_pages(socket, eid)
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
      TreeHandlers.handle_save_name(params, socket)
    end)
  end

  def handle_event("create_flow_from_screenplay", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      FlowSyncHandlers.do_create_flow_from_screenplay(socket)
    end)
  end

  def handle_event("sync_to_flow", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      FlowSyncHandlers.do_sync_to_flow(socket)
    end)
  end

  def handle_event("sync_from_flow", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      FlowSyncHandlers.do_sync_from_flow(socket)
    end)
  end

  def handle_event("unlink_flow", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      FlowSyncHandlers.do_unlink_flow(socket)
    end)
  end

  def handle_event("navigate_to_flow", _params, socket) do
    FlowSyncHandlers.do_navigate_to_flow(socket)
  end

  # ---------------------------------------------------------------------------
  # Sidebar event handlers
  # ---------------------------------------------------------------------------

  def handle_event("set_pending_delete_screenplay", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event("confirm_delete_screenplay", _params, socket) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete_screenplay", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_screenplay", %{"id" => screenplay_id}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      TreeHandlers.do_delete_screenplay(socket, screenplay_id)
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
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_connected_data(socket, screenplay) do
    project = socket.assigns.project
    elements = Screenplays.list_elements(screenplay.id)
    project_variables = Sheets.list_project_variables(project.id)
    all_sheets = Sheets.list_all_sheets(project.id)
    sheets_map = Map.new(all_sheets, &{&1.id, &1})
    screenplays_tree = Screenplays.list_screenplays_tree(project.id)
    {link_status, linked_flow} = FlowSyncHandlers.detect_link_status(screenplay)

    socket
    |> assign(:screenplays_tree, screenplays_tree)
    |> assign(:sheets_map, sheets_map)
    |> assign_elements_with_editor_doc(elements)
    |> assign(:project_variables, project_variables)
    |> assign(:link_status, link_status)
    |> assign(:linked_flow, linked_flow)
    |> assign(:linked_pages, LinkedPageHandlers.load_linked_pages(screenplay))
  end

  defp screenplay_translations do
    Map.merge(InstructionBuilder.translations(), ConditionBuilder.translations())
  end
end
