defmodule StoryarnWeb.SheetLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Components.SheetComponents
  import StoryarnWeb.Components.SaveIndicator
  import StoryarnWeb.Helpers.SaveStatusTimer
  import StoryarnWeb.Live.Shared.TreePanelHandlers

  alias Storyarn.Projects
  alias Storyarn.Sheets
  alias StoryarnWeb.Components.Sidebar.SheetTree
  alias StoryarnWeb.Helpers.UndoRedoStack
  alias StoryarnWeb.SheetLive.Components.AudioTab
  alias StoryarnWeb.SheetLive.Components.Banner
  alias StoryarnWeb.SheetLive.Components.ContentTab
  alias StoryarnWeb.SheetLive.Components.HistoryTab
  alias StoryarnWeb.SheetLive.Components.ReferencesTab
  alias StoryarnWeb.SheetLive.Components.SheetAvatar
  alias StoryarnWeb.SheetLive.Components.SheetTitle
  alias StoryarnWeb.SheetLive.Handlers.UndoRedoHandlers
  alias StoryarnWeb.SheetLive.Helpers.ReferenceHelpers
  alias StoryarnWeb.SheetLive.Helpers.SheetTreeHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:sheets}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      can_edit={@can_edit}
    >
      <:top_bar_extra>
        <.sheet_breadcrumb
          :if={@ancestors != []}
          ancestors={@ancestors}
          workspace={@workspace}
          project={@project}
        />
      </:top_bar_extra>
      <:tree_content>
        <SheetTree.sheets_section
          sheets_tree={@sheets_tree}
          workspace={@workspace}
          project={@project}
          selected_sheet_id={to_string(@sheet.id)}
          can_edit={@can_edit}
        />
      </:tree_content>
      <div
        id="sheet-undo-redo"
        phx-hook="UndoRedo"
        class="w-full max-w-[950px] mx-auto bg-base-200 rounded-[20px] p-5 min-h-full"
      >
        <%!-- Banner --%>
        <.live_component
          module={Banner}
          id="sheet-banner"
          sheet={@sheet}
          project={@project}
          current_user={@current_scope.user}
          can_edit={@can_edit}
        />

        <%!-- Sheet Header --%>
        <div class="relative">
          <div class="flex items-start gap-4 mb-8">
            <%!-- Avatar with edit options --%>
            <.live_component
              module={SheetAvatar}
              id="sheet-avatar"
              sheet={@sheet}
              project={@project}
              current_user={@current_scope.user}
              can_edit={@can_edit}
            />
            <div class="flex-1">
              <.live_component
                module={SheetTitle}
                id="sheet-title"
                sheet={@sheet}
                project={@project}
                current_user_id={@current_scope.user.id}
                can_edit={@can_edit}
              />
            </div>
          </div>
          <%!-- Save indicator (positioned at header level) --%>
          <.save_indicator status={@save_status} variant={:floating} />
        </div>

        <%!-- Loading state while async data loads --%>
        <div :if={!@sheet_data_loaded} class="flex justify-center py-12">
          <span class="loading loading-spinner loading-lg text-base-content/30"></span>
        </div>

        <div :if={@sheet_data_loaded}>
          <%!-- Tabs Navigation --%>
          <div role="tablist" class="tabs tabs-border mb-6">
            <button
              role="tab"
              class={["tab", @current_tab == "content" && "tab-active"]}
              phx-click="switch_tab"
              phx-value-tab="content"
            >
              <.icon name="file-text" class="size-4 mr-2" />
              {dgettext("sheets", "Content")}
            </button>
            <button
              role="tab"
              class={["tab", @current_tab == "references" && "tab-active"]}
              phx-click="switch_tab"
              phx-value-tab="references"
            >
              <.icon name="link" class="size-4 mr-2" />
              {dgettext("sheets", "References")}
            </button>
            <button
              role="tab"
              class={["tab", @current_tab == "audio" && "tab-active"]}
              phx-click="switch_tab"
              phx-value-tab="audio"
            >
              <.icon name="volume-2" class="size-4 mr-2" />
              {dgettext("sheets", "Audio")}
            </button>
            <button
              role="tab"
              class={["tab", @current_tab == "history" && "tab-active"]}
              phx-click="switch_tab"
              phx-value-tab="history"
            >
              <.icon name="clock" class="size-4 mr-2" />
              {dgettext("sheets", "History")}
            </button>
          </div>

          <%!-- Tab Content: Content (LiveComponent) --%>
          <.live_component
            :if={@current_tab == "content"}
            module={ContentTab}
            id="content-tab"
            workspace={@workspace}
            project={@project}
            sheet={@sheet}
            blocks={@blocks}
            children={@children}
            can_edit={@can_edit}
            current_user_id={@current_scope.user.id}
          />

          <%!-- Tab Content: References (LiveComponent) --%>
          <.live_component
            :if={@current_tab == "references"}
            module={ReferencesTab}
            id="references-tab"
            project={@project}
            workspace={@workspace}
            sheet={@sheet}
            blocks={@blocks}
          />

          <%!-- Tab Content: Audio (LiveComponent) --%>
          <.live_component
            :if={@current_tab == "audio"}
            module={AudioTab}
            id="audio-tab"
            project={@project}
            workspace={@workspace}
            sheet={@sheet}
            can_edit={@can_edit}
            current_user={@current_scope.user}
          />

          <%!-- Tab Content: History (LiveComponent) --%>
          <.live_component
            :if={@current_tab == "history"}
            module={HistoryTab}
            id="history-tab"
            project={@project}
            sheet={@sheet}
            can_edit={@can_edit}
            current_user_id={@current_scope.user.id}
          />
        </div>
      </div>
    </Layouts.focus>
    """
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug, "id" => sheet_id},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        mount_with_project(socket, workspace_slug, project_slug, sheet_id, project, membership)

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("sheets", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  defp mount_with_project(socket, workspace_slug, project_slug, sheet_id, project, membership) do
    case Sheets.get_sheet_full(project.id, sheet_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("sheets", "Sheet not found."))
         |> redirect(to: ~p"/workspaces/#{workspace_slug}/projects/#{project_slug}/sheets")}

      sheet ->
        {:ok, setup_sheet_view(socket, project, membership, sheet)}
    end
  end

  defp setup_sheet_view(socket, project, membership, sheet) do
    can_edit = Projects.can?(membership.role, :edit_content)

    socket
    |> assign(focus_layout_defaults())
    |> assign(:project, project)
    |> assign(:workspace, project.workspace)
    |> assign(:membership, membership)
    |> assign(:sheet, sheet)
    |> assign(:can_edit, can_edit)
    |> assign(:save_status, :idle)
    |> assign(:current_tab, "content")
    # Defaults while async loading
    |> assign(:sheets_tree, [])
    |> assign(:ancestors, [])
    |> assign(:children, [])
    |> assign(:blocks, [])
    |> assign(:sheet_data_loaded, false)
    |> start_async(:load_sheet_data, fn ->
      %{
        sheets_tree: Sheets.list_sheets_tree(project.id),
        ancestors:
          case Sheets.get_sheet_with_ancestors(project.id, sheet.id) do
            nil -> []
            list -> List.delete_at(list, -1)
          end,
        children: Sheets.get_children(sheet.id),
        blocks: ReferenceHelpers.load_blocks_with_references(sheet.id, project.id)
      }
    end)
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  # ===========================================================================
  # Async Loading
  # ===========================================================================

  @impl true
  def handle_async(:load_sheet_data, {:ok, data}, socket) do
    {:noreply,
     socket
     |> assign(:sheets_tree, data.sheets_tree)
     |> assign(:ancestors, data.ancestors)
     |> assign(:children, data.children)
     |> assign(:blocks, data.blocks)
     |> assign(:sheet_data_loaded, true)
     |> UndoRedoStack.init()}
  end

  def handle_async(:load_sheet_data, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, dgettext("sheets", "Could not load sheet data."))
     |> assign(:sheet_data_loaded, true)}
  end

  # ===========================================================================
  # Event Handlers: Tabs
  # ===========================================================================

  @impl true
  # Tree panel events (from FocusLayout)
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

  def handle_event("switch_tab", %{"tab" => tab}, socket)
      when tab in ["content", "references", "audio", "history"] do
    {:noreply, assign(socket, :current_tab, tab)}
  end

  # ===========================================================================
  # Event Handlers: Undo/Redo
  # ===========================================================================

  def handle_event("undo", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      UndoRedoHandlers.handle_undo(params, socket)
    end)
  end

  def handle_event("redo", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      UndoRedoHandlers.handle_redo(params, socket)
    end)
  end

  # ===========================================================================
  # Event Handlers: Sheet Tree
  # ===========================================================================

  def handle_event("set_pending_delete_sheet", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event("confirm_delete_sheet", _params, socket) do
    if id = socket.assigns[:pending_delete_id] do
      with_authorization(socket, :edit_content, &SheetTreeHelpers.delete_sheet(&1, id))
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_sheet", %{"id" => sheet_id}, socket) do
    with_authorization(socket, :edit_content, &SheetTreeHelpers.delete_sheet(&1, sheet_id))
  end

  def handle_event(
        "move_sheet",
        %{"sheet_id" => sheet_id, "parent_id" => parent_id, "position" => position},
        socket
      ) do
    with_authorization(
      socket,
      :edit_content,
      &SheetTreeHelpers.move_sheet(&1, sheet_id, parent_id, position)
    )
  end

  def handle_event("create_child_sheet", %{"parent-id" => parent_id}, socket) do
    with_authorization(socket, :edit_content, &SheetTreeHelpers.create_child_sheet(&1, parent_id))
  end

  def handle_event("create_sheet", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      attrs = %{name: dgettext("sheets", "Untitled")}

      case Sheets.create_sheet(socket.assigns.project, attrs) do
        {:ok, new_sheet} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{new_sheet.id}"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create sheet."))}
      end
    end)
  end

  # Sheet color (from ColorPicker hook — pushes to parent LV, not LiveComponent)
  def handle_event("set_sheet_color", %{"color" => color}, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      update_sheet_color(socket, color)
    end)
  end

  def handle_event("clear_sheet_color", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      update_sheet_color(socket, nil)
    end)
  end

  defp update_sheet_color(socket, color) do
    sheet = socket.assigns.sheet
    prev_color = sheet.color

    case Sheets.update_sheet(sheet, %{color: color}) do
      {:ok, _updated_sheet} ->
        updated_sheet =
          Sheets.get_sheet_full!(socket.assigns.project.id, sheet.id)

        {:noreply,
         socket
         |> assign(:sheet, updated_sheet)
         |> UndoRedoStack.push_undo({:update_sheet_color, prev_color, color})
         |> mark_saved()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not update color."))}
    end
  end

  # ===========================================================================
  # Handle Info
  # ===========================================================================

  @impl true
  def handle_info(:reset_save_status, socket) do
    {:noreply, assign(socket, :save_status, :idle)}
  end

  # Handle messages from ContentTab LiveComponent
  def handle_info({:content_tab, :saved}, socket) do
    {:noreply, mark_saved(socket)}
  end

  # Handle messages from VersionsSection LiveComponent
  def handle_info({:versions_section, :saved}, socket) do
    {:noreply, mark_saved(socket)}
  end

  def handle_info({:versions_section, :sheet_updated, sheet}, socket) do
    {:noreply, assign(socket, :sheet, sheet)}
  end

  def handle_info({:versions_section, :version_restored, %{sheet: sheet}}, socket) do
    # Reload blocks and sheets tree after version restore
    blocks = ReferenceHelpers.load_blocks_with_references(sheet.id, socket.assigns.project.id)
    sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(:sheet, sheet)
     |> assign(:blocks, blocks)
     |> assign(:sheets_tree, sheets_tree)
     |> UndoRedoStack.clear()
     |> mark_saved()}
  end

  # Handle messages from Banner LiveComponent
  def handle_info({:banner, :sheet_updated, sheet}, socket) do
    {:noreply,
     socket
     |> assign(:sheet, sheet)
     |> mark_saved()}
  end

  def handle_info({:banner, :error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # Handle messages from AudioTab LiveComponent
  def handle_info({:audio_tab, :error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # Handle messages from SheetAvatar LiveComponent
  def handle_info({:sheet_avatar, :sheet_updated, sheet, sheets_tree}, socket) do
    {:noreply,
     socket
     |> assign(:sheet, sheet)
     |> assign(:sheets_tree, sheets_tree)
     |> mark_saved()}
  end

  def handle_info({:sheet_avatar, :error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # Handle messages from SheetTitle LiveComponent
  def handle_info({:sheet_title, :name_saved, sheet, sheets_tree}, socket) do
    prev_name = socket.assigns.sheet.name

    ancestors =
      case Sheets.get_sheet_with_ancestors(socket.assigns.project.id, sheet.id) do
        nil -> []
        list -> List.delete_at(list, -1)
      end

    {:noreply,
     socket
     |> assign(:sheet, sheet)
     |> assign(:sheets_tree, sheets_tree)
     |> assign(:ancestors, ancestors)
     |> UndoRedoHandlers.push_name_coalesced(prev_name, sheet.name)
     |> mark_saved()}
  end

  def handle_info({:sheet_title, :shortcut_saved, sheet}, socket) do
    prev_shortcut = socket.assigns.sheet.shortcut

    {:noreply,
     socket
     |> assign(:sheet, sheet)
     |> UndoRedoHandlers.push_shortcut_coalesced(prev_shortcut, sheet.shortcut)
     |> mark_saved()}
  end

  def handle_info({:sheet_title, :error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # Handle undo action push from ContentTab LiveComponent
  def handle_info({:content_tab, :push_undo, action}, socket) do
    {:noreply, route_undo_push(socket, action)}
  end

  defp route_undo_push(socket, {:update_block_value, block_id, prev, new}) do
    UndoRedoHandlers.push_block_value_coalesced(socket, block_id, prev, new)
  end

  defp route_undo_push(socket, {:update_table_cell, block_id, row_id, col_slug, prev, new}) do
    UndoRedoHandlers.push_cell_coalesced(socket, block_id, row_id, col_slug, prev, new)
  end

  defp route_undo_push(socket, action) do
    UndoRedoStack.push_undo(socket, action)
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================
end
