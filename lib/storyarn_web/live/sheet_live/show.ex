defmodule StoryarnWeb.SheetLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize
  use StoryarnWeb.Live.Shared.RestorationHandlers

  import StoryarnWeb.Components.SheetComponents
  import StoryarnWeb.Components.SaveIndicator
  import StoryarnWeb.Helpers.SaveStatusTimer
  import StoryarnWeb.Live.Shared.TreePanelHandlers

  alias StoryarnWeb.Components.DraftComponents
  alias StoryarnWeb.Live.Shared.DraftHandlers

  alias Storyarn.Collaboration
  alias Storyarn.Drafts
  alias Storyarn.Projects
  alias Storyarn.Sheets
  alias StoryarnWeb.Components.Sidebar.SheetTree
  alias StoryarnWeb.Helpers.UndoRedoStack
  alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: Collab
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
      online_users={@online_users}
      restoration_banner={@restoration_banner}
    >
      <:top_bar_extra>
        <DraftComponents.draft_banner is_draft={@is_draft} />
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
          selected_sheet_id={@sheet && to_string(@sheet.id)}
          can_edit={@can_edit}
        />
      </:tree_content>
      <SheetTree.delete_modal :if={@can_edit} />
      <DraftComponents.discard_draft_modal is_draft={@is_draft} />
      <DraftComponents.merge_review_modal is_draft={@is_draft} merge_summary={@merge_summary} />
      <%= if @sheet do %>
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
            <%!-- Save indicator + draft button (positioned at header level) --%>
            <div class="absolute top-0 right-0 flex items-center gap-2">
              <button
                :if={@can_edit && !@is_draft}
                type="button"
                phx-click="create_draft"
                class="btn btn-ghost btn-xs gap-1.5 text-base-content/60"
                title={dgettext("drafts", "Create a private draft copy")}
              >
                <.icon name="git-branch" class="size-3.5" />
                <span>{dgettext("drafts", "Draft")}</span>
              </button>
              <.save_indicator status={@save_status} variant={:floating} />
            </div>
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
              current_scope={@current_scope}
              project_variables={@project_variables}
              block_locks={@block_locks}
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
              workspace_id={@workspace.id}
            />
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
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        can_edit = Projects.can?(membership.role, :edit_content)

        if connected?(socket), do: Collaboration.subscribe_restoration(project.id)

        {can_edit, restoration_banner} = check_restoration_lock(project.id, can_edit)

        {:ok,
         socket
         |> assign(focus_layout_defaults())
         |> assign(:project, project)
         |> assign(:workspace, project.workspace)
         |> assign(:membership, membership)
         |> assign(:can_edit, can_edit)
         |> assign(:restoration_banner, restoration_banner)
         |> assign(:save_status, :idle)
         |> assign(:current_tab, "content")
         |> assign(:pending_delete_id, nil)
         |> assign(:online_users, [])
         |> assign(:collab_scope, nil)
         |> assign(:block_locks, %{})
         |> assign(:collab_toast, nil)
         # Defaults — sheet loaded in handle_params
         |> assign(:sheet, nil)
         |> assign(:ancestors, [])
         |> assign(:sheets_tree, Sheets.list_sheets_tree(project.id))
         |> assign(:children, [])
         |> assign(:blocks, [])
         |> assign(:sheet_data_loaded, false)
         |> assign(:is_draft, false)
         |> assign(:draft, nil)
         |> assign(:merge_summary, nil)}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("sheets", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(%{"id" => _sheet_id, "draft_id" => draft_id}, _url, socket) do
    {:noreply, load_draft_sheet(socket, draft_id)}
  end

  def handle_params(%{"id" => sheet_id}, _url, socket) do
    current_sheet_id =
      case socket.assigns.sheet do
        %{id: id} -> to_string(id)
        _ -> nil
      end

    if sheet_id == current_sheet_id do
      {:noreply, socket}
    else
      {:noreply, load_sheet(socket, sheet_id)}
    end
  end

  defp load_draft_sheet(socket, draft_id) do
    %{project: project, current_scope: scope} = socket.assigns

    with draft when not is_nil(draft) <- Drafts.get_my_draft(draft_id, scope.user.id),
         true <- draft.entity_type == "sheet" and draft.status == "active",
         entity when not is_nil(entity) <- Drafts.get_draft_entity(draft) do
      # Skip collaboration for drafts
      has_tree = socket.assigns.sheets_tree != []

      socket
      |> assign(:sheet, entity)
      |> assign(:ancestors, [])
      |> assign(:current_tab, "content")
      |> assign(:save_status, :idle)
      |> assign(:children, [])
      |> assign(:blocks, [])
      |> assign(:project_variables, [])
      |> assign(:sheet_data_loaded, false)
      |> assign(:is_draft, true)
      |> assign(:draft, draft)
      |> start_async(:load_sheet_data, fn ->
        load_sheet_async_data(entity, project, has_tree)
      end)
    else
      _ ->
        socket
        |> put_flash(:error, dgettext("sheets", "Draft not found."))
        |> push_navigate(
          to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets"
        )
    end
  end

  defp load_sheet(socket, sheet_id) do
    %{project: project} = socket.assigns

    # Teardown previous sheet collaboration
    socket = teardown_sheet_collab(socket)

    case Sheets.get_sheet_full(project.id, sheet_id) do
      nil ->
        socket
        |> put_flash(:error, dgettext("sheets", "Sheet not found."))
        |> push_navigate(
          to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets"
        )

      sheet ->
        # Load ancestors synchronously so the breadcrumb is present on the first
        # render and does not flash in after the async bundle completes.
        ancestors =
          case Sheets.get_sheet_with_ancestors(project.id, sheet.id) do
            nil -> []
            list -> List.delete_at(list, -1)
          end

        has_tree = socket.assigns.sheets_tree != []

        # Setup collaboration for new sheet
        scope = {:sheet, sheet.id}
        user = socket.assigns.current_scope.user

        Collab.setup(socket, scope, user, cursors: false, locks: true, changes: true)
        {online_users, block_locks} = Collab.get_initial_state(socket, scope)

        socket
        |> assign(:sheet, sheet)
        |> assign(:ancestors, ancestors)
        |> assign(:current_tab, "content")
        |> assign(:save_status, :idle)
        |> assign(:children, [])
        |> assign(:blocks, [])
        |> assign(:project_variables, [])
        |> assign(:sheet_data_loaded, false)
        |> assign(:collab_scope, scope)
        |> assign(:online_users, online_users)
        |> assign(:block_locks, block_locks)
        |> start_async(:load_sheet_data, fn ->
          load_sheet_async_data(sheet, project, has_tree)
        end)
    end
  end

  defp load_sheet_async_data(sheet, project, has_tree) do
    data = %{
      children: Sheets.get_children(sheet.id),
      blocks: ReferenceHelpers.load_blocks_with_references(sheet.id, project.id),
      project_variables: Sheets.list_project_variables(project.id)
    }

    if has_tree, do: data, else: Map.put(data, :sheets_tree, Sheets.list_sheets_tree(project.id))
  end

  # ===========================================================================
  # Async Loading
  # ===========================================================================

  @impl true
  def handle_async(:load_sheet_data, {:ok, data}, socket) do
    socket =
      socket
      |> assign(:children, data.children)
      |> assign(:blocks, data.blocks)
      |> assign(:project_variables, data.project_variables)
      |> assign(:sheet_data_loaded, true)
      |> UndoRedoStack.init()

    # Only update tree if included (first load)
    socket =
      if data[:sheets_tree], do: assign(socket, :sheets_tree, data.sheets_tree), else: socket

    {:noreply, socket}
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

  def handle_event("create_draft", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      %{sheet: sheet} = socket.assigns

      DraftHandlers.handle_create_draft(socket, "sheet", sheet.id, fn s, draft ->
        %{project: project} = s.assigns

        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}/drafts/#{draft.id}"
      end)
    end)
  end

  def handle_event("discard_draft", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      %{project: project} = socket.assigns

      DraftHandlers.handle_discard_draft(
        socket,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets"
      )
    end)
  end

  def handle_event("load_merge_summary", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      DraftHandlers.handle_load_merge_summary(socket)
    end)
  end

  def handle_event("merge_draft", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      %{draft: draft} = socket.assigns

      DraftHandlers.handle_merge_draft(socket, fn s ->
        %{project: p} = s.assigns

        ~p"/workspaces/#{p.workspace.slug}/projects/#{p.slug}/sheets/#{draft.source_entity_id}"
      end)
    end)
  end

  def handle_event("set_pending_delete_sheet", %{"id" => id}, socket) do
    handle_set_pending_delete(socket, id)
  end

  def handle_event("confirm_delete_sheet", _params, socket) do
    handle_confirm_delete(socket, fn socket, id ->
      with_authorization(socket, :edit_content, &SheetTreeHelpers.delete_sheet(&1, id))
    end)
  end

  def handle_event("delete_sheet", %{"id" => sheet_id}, socket) do
    with_authorization(socket, :edit_content, &SheetTreeHelpers.delete_sheet(&1, sheet_id))
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => sheet_id, "new_parent_id" => parent_id, "position" => position},
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
    with_authorization(socket, :edit_content, fn _socket ->
      handle_create_entity(
        socket,
        %{name: dgettext("sheets", "Untitled")},
        &Sheets.create_sheet/2,
        &sheet_path/2,
        dgettext("sheets", "Could not create sheet."),
        patch: true,
        reload_tree_fn: &reload_sheets_tree/1
      )
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

        broadcast_sheet_change(socket, :sheet_updated)

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
    # Broadcast generic block change to other users
    if scope = socket.assigns[:collab_scope] do
      Collab.broadcast_change(socket, scope, :block_updated, %{})
    end

    {:noreply, mark_saved(socket)}
  end

  # Handle messages from VersionsSection LiveComponent
  def handle_info({:versions_section, :version_created, %{version: _version}}, socket) do
    {:noreply, mark_saved(socket)}
  end

  def handle_info({:versions_section, :version_restored, %{entity: sheet, version: _}}, socket) do
    sheet = Sheets.get_sheet_full!(socket.assigns.project.id, sheet.id)

    broadcast_sheet_change(socket, :sheet_restored)

    {:noreply,
     socket
     |> reload_sheet_state(sheet)
     |> UndoRedoStack.clear()
     |> push_event("restore_sheet_content", %{
       name: sheet.name,
       shortcut: sheet.shortcut || ""
     })
     |> mark_saved()}
  end

  def handle_info({:versions_section, :version_deleted, %{version: _}}, socket) do
    {:noreply, mark_saved(socket)}
  end

  # Handle messages from Banner LiveComponent
  def handle_info({:banner, :sheet_updated, sheet}, socket) do
    broadcast_sheet_change(socket, :sheet_updated)

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
    broadcast_sheet_change(socket, :sheet_updated)

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
    broadcast_sheet_change(socket, :sheet_updated)

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
    broadcast_sheet_change(socket, :sheet_updated)

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

  # ===========================================================================
  # Handle Info: Collaboration
  # ===========================================================================

  def handle_info({Storyarn.Collaboration.Presence, {:join, presence}}, socket) do
    Collab.handle_presence_join(socket, presence)
  end

  def handle_info({Storyarn.Collaboration.Presence, {:leave, _} = event}, socket) do
    Collab.handle_presence_leave(socket, elem(event, 1))
  end

  def handle_info({:lock_change, _action, _payload}, socket) do
    block_locks = Collaboration.list_locks(socket.assigns.collab_scope)
    {:noreply, assign(socket, :block_locks, block_locks)}
  end

  def handle_info({:remote_change, action, payload}, socket) do
    handle_sheet_remote_change(action, payload, socket)
  end

  def handle_info(:clear_collab_toast, socket) do
    {:noreply, assign(socket, :collab_toast, nil)}
  end

  # Ignore EXIT messages from linked processes (e.g. PubSub subscriptions)
  def handle_info({:EXIT, _pid, _reason}, socket) do
    {:noreply, socket}
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

  @impl true
  def terminate(_reason, socket) do
    teardown_sheet_collab(socket)
  end

  # ===========================================================================
  # Private Functions: Collaboration
  # ===========================================================================

  defp teardown_sheet_collab(socket) do
    if scope = socket.assigns[:collab_scope] do
      user_id = socket.assigns.current_scope.user.id
      Collab.teardown(scope, user_id)
    end

    socket
  end

  defp handle_sheet_remote_change(:block_updated, _payload, socket) do
    blocks =
      ReferenceHelpers.load_blocks_with_references(
        socket.assigns.sheet.id,
        socket.assigns.project.id
      )

    {:noreply, assign(socket, :blocks, blocks)}
  end

  defp handle_sheet_remote_change(:block_created, _payload, socket) do
    blocks =
      ReferenceHelpers.load_blocks_with_references(
        socket.assigns.sheet.id,
        socket.assigns.project.id
      )

    {:noreply, assign(socket, :blocks, blocks)}
  end

  defp handle_sheet_remote_change(:block_deleted, %{block_id: block_id}, socket) do
    blocks = Enum.reject(socket.assigns.blocks, &(&1.id == block_id))
    {:noreply, assign(socket, :blocks, blocks)}
  end

  defp handle_sheet_remote_change(:block_reordered, _payload, socket) do
    blocks =
      ReferenceHelpers.load_blocks_with_references(
        socket.assigns.sheet.id,
        socket.assigns.project.id
      )

    {:noreply, assign(socket, :blocks, blocks)}
  end

  defp handle_sheet_remote_change(:block_type_changed, _payload, socket) do
    blocks =
      ReferenceHelpers.load_blocks_with_references(
        socket.assigns.sheet.id,
        socket.assigns.project.id
      )

    {:noreply, assign(socket, :blocks, blocks)}
  end

  defp handle_sheet_remote_change(:sheet_updated, _payload, socket) do
    sheet = Sheets.get_sheet_full!(socket.assigns.project.id, socket.assigns.sheet.id)

    # Push name/shortcut to JS hooks (contenteditable has phx-update="ignore")
    socket =
      socket
      |> assign(:sheet, sheet)
      |> push_event("restore_page_content", %{
        name: sheet.name,
        shortcut: sheet.shortcut
      })

    {:noreply, socket}
  end

  defp handle_sheet_remote_change(:sheet_restored, _payload, socket) do
    sheet = Sheets.get_sheet_full!(socket.assigns.project.id, socket.assigns.sheet.id)

    {:noreply,
     socket
     |> reload_sheet_state(sheet)
     |> push_event("restore_sheet_content", %{
       name: sheet.name,
       shortcut: sheet.shortcut || ""
     })}
  end

  defp handle_sheet_remote_change(:entity_merged, _payload, socket) do
    sheet = Sheets.get_sheet_full!(socket.assigns.project.id, socket.assigns.sheet.id)

    {:noreply,
     socket
     |> reload_sheet_state(sheet)
     |> push_event("restore_sheet_content", %{
       name: sheet.name,
       shortcut: sheet.shortcut || ""
     })}
  end

  defp handle_sheet_remote_change(_action, _payload, socket) do
    {:noreply, socket}
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp broadcast_sheet_change(socket, action) do
    if scope = socket.assigns[:collab_scope] do
      Collab.broadcast_change(socket, scope, action, %{})
    end
  end

  defp sheet_path(socket, sheet) do
    ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{sheet.id}"
  end

  defp reload_sheet_state(socket, sheet) do
    blocks = ReferenceHelpers.load_blocks_with_references(sheet.id, socket.assigns.project.id)
    sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)

    socket
    |> assign(:sheet, sheet)
    |> assign(:blocks, blocks)
    |> assign(:sheets_tree, sheets_tree)
  end

  defp reload_sheets_tree(socket) do
    assign(socket, :sheets_tree, Sheets.list_sheets_tree(socket.assigns.project.id))
  end
end
