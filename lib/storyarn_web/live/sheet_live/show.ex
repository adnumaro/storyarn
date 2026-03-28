defmodule StoryarnWeb.SheetLive.Show do
  @moduledoc """
  V2 Sheet editor — Phase 1: Header only (banner, avatar, title, color).
  Same backend logic as SheetLive.Show, Vue + shadcn UI.
  """

  use StoryarnWeb, :live_view
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Helpers.UndoRedoStack
  alias StoryarnWeb.SheetLive.Handlers.{
    AudioHandlers,
    BlockHandlers,
    FormulaHandlers,
    GalleryHandlers,
    HeaderHandlers,
    HistoryHandlers,
    LockHandlers,
    ReferenceHandlers,
    SelectOptionHandlers,
    TableHandlers,
    TreeHandlers,
    UndoRedoHandlers
  }

  alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: Collab
  alias StoryarnWeb.Live.Shared.RestorationHandlers

  import StoryarnWeb.Live.Shared.RestorationHandlers, only: [check_restoration_lock: 2]
  import StoryarnWeb.Live.Shared.TreePanelHandlers
  import StoryarnWeb.SheetLive.Helpers.AudioDataHelpers
  import StoryarnWeb.SheetLive.Helpers.FormulaHelpers
  import StoryarnWeb.SheetLive.Helpers.HistoryDataHelpers
  import StoryarnWeb.SheetLive.Helpers.PropsSerializer
  import StoryarnWeb.SheetLive.Helpers.ReferencesDataHelpers

  alias Storyarn.Collaboration
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Projects
  alias Storyarn.Sheets

  @impl true
  def render(assigns) do
    if assigns.compact do
      render_compact(assigns)
    else
      render_full(assigns)
    end
  end

  defp render_full(assigns) do
    ~H"""
    <Layouts.focus_v2
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:sheets}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      can_edit={@can_edit}
      restoration_banner={@restoration_banner}
      online_users={@online_users}
      tree_props={
        %{
          sheetsTree: @sheets_tree,
          canEdit: @can_edit,
          workspaceSlug: @workspace.slug,
          projectSlug: @project.slug,
          selectedSheetId: @sheet && @sheet.id
        }
      }
    >
      <.sheet_content
        sheet={@sheet}
        socket={@socket}
        current_tab={@current_tab}
        can_edit={@can_edit}
        is_draft={@is_draft}
        source_shortcut={@source_shortcut}
        blocks={@blocks}
        gallery_data={@gallery_data}
        table_data={@table_data}
        inherited_groups={@inherited_groups}
        project={@project}
        workspace={@workspace}
        references_data={@references_data}
        audio_data={@audio_data}
        history_data={@history_data}
        formula_editing={@formula_editing}
        formula_search_results={@formula_search_results}
        formula_search_has_more={@formula_search_has_more}
        block_locks={@block_locks}
        current_user_id={@current_scope.user.id}
        compact={false}
      />
    </Layouts.focus_v2>
    """
  end

  defp render_compact(assigns) do
    ~H"""
    <div class="h-screen overflow-y-auto bg-background p-4">
      <.sheet_content
        sheet={@sheet}
        socket={@socket}
        current_tab={@current_tab}
        can_edit={@can_edit}
        is_draft={@is_draft}
        source_shortcut={@source_shortcut}
        blocks={@blocks}
        gallery_data={@gallery_data}
        table_data={@table_data}
        inherited_groups={@inherited_groups}
        project={@project}
        workspace={@workspace}
        references_data={@references_data}
        audio_data={@audio_data}
        history_data={@history_data}
        formula_editing={@formula_editing}
        formula_search_results={@formula_search_results}
        formula_search_has_more={@formula_search_has_more}
        block_locks={@block_locks}
        current_user_id={@current_scope.user.id}
        compact={true}
      />
    </div>
    """
  end

  attr :sheet, :map, default: nil
  attr :socket, :any, required: true
  attr :current_tab, :string, required: true
  attr :can_edit, :boolean, required: true
  attr :is_draft, :boolean, default: false
  attr :source_shortcut, :string, default: nil
  attr :blocks, :list, default: []
  attr :gallery_data, :map, default: %{}
  attr :table_data, :map, default: %{}
  attr :inherited_groups, :list, default: []
  attr :project, :map, required: true
  attr :workspace, :map, required: true
  attr :references_data, :map, default: nil
  attr :audio_data, :map, default: nil
  attr :history_data, :map, default: nil
  attr :formula_editing, :map, default: nil
  attr :formula_search_results, :list, default: []
  attr :formula_search_has_more, :boolean, default: false
  attr :block_locks, :map, default: %{}
  attr :current_user_id, :integer, default: nil
  attr :compact, :boolean, default: false

  defp sheet_content(assigns) do
    ~H"""
    <div
      :if={@sheet}
      class="max-w-4xl mx-auto bg-surface border border-border rounded-2xl p-6 mb-8 shadow-sm"
    >
      <.vue
        v-component="sheets/SheetHeader"
        v-socket={@socket}
        id="sheet-header"
        sheet={prepare_sheet_for_vue(@sheet)}
        can-edit={@can_edit}
        is-draft={@is_draft}
        source-shortcut={@source_shortcut}
      />
      <div class="px-4 pb-6">
        <.vue
          v-component="sheets/SheetTabs"
          v-socket={@socket}
          id="sheet-tabs"
          current-tab={@current_tab}
          can-edit={@can_edit}
          compact={@compact}
        />
        <.vue
          :if={@current_tab == "content"}
          v-component="sheets/BlockList"
          v-socket={@socket}
          id="block-list"
          blocks={prepare_blocks_for_vue(@blocks, @gallery_data, @table_data, @project.id, @inherited_groups)}
          inherited-groups={prepare_inherited_groups_for_vue(@inherited_groups, @gallery_data, @table_data, @project.id)}
          workspace-slug={@workspace.slug}
          project-slug={@project.slug}
          can-edit={@can_edit}
          formula-editing={build_formula_editing_for_vue(@formula_editing, @formula_search_results, @formula_search_has_more)}
          block-locks={serialize_block_locks(@block_locks)}
          current-user-id={@current_user_id}
        />
        <.vue
          :if={@current_tab == "references"}
          v-component="sheets/ReferencesTab"
          v-socket={@socket}
          id="references-tab"
          variable-usage={@references_data[:variable_usage] || []}
          backlinks={@references_data[:backlinks] || []}
          scene-appearances={@references_data[:scene_appearances] || []}
          workspace-slug={@workspace.slug}
          project-slug={@project.slug}
          loading={is_nil(@references_data)}
        />
        <.vue
          :if={@current_tab == "audio"}
          v-component="sheets/AudioTab"
          v-socket={@socket}
          id="audio-tab"
          grouped-lines={@audio_data[:grouped_lines] || []}
          audio-assets={@audio_data[:audio_assets] || []}
          workspace-slug={@workspace.slug}
          project-slug={@project.slug}
          can-edit={@can_edit}
          loading={is_nil(@audio_data)}
        />
        <.vue
          v-component="sheets/CollabToast"
          v-socket={@socket}
          id="collab-toast"
        />
        <.vue
          :if={@current_tab == "history" && !@compact}
          v-component="sheets/HistoryTab"
          v-socket={@socket}
          id="history-tab"
          versions={@history_data[:versions] || []}
          named-versions={@history_data[:named_versions] || []}
          auto-versions={@history_data[:auto_versions] || []}
          has-more={@history_data[:has_more] || false}
          can-name-version={@history_data[:can_name_version] || false}
          current-version-id={@history_data[:current_version_id]}
          can-edit={@can_edit}
          loading={is_nil(@history_data)}
        />
      </div>
    </div>

    <div :if={!@sheet} class="flex justify-center py-20">
      <div class="size-6 border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin" />
    </div>
    """
  end

  # ===========================================================================
  # Mount & Lifecycle
  # ===========================================================================

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

        if connected?(socket) do
          Collaboration.subscribe_restoration(project.id)
          Collaboration.subscribe_changes({:project, project.id})
        end

        {can_edit, restoration_banner} =
          check_restoration_lock(project.id, can_edit)

        {:ok,
         socket
         |> assign(focus_layout_defaults())
         |> assign(:project, project)
         |> assign(:workspace, project.workspace)
         |> assign(:membership, membership)
         |> assign(:can_edit, can_edit)
         |> assign(:restoration_banner, restoration_banner)
         |> assign(:compact, false)
         |> assign(:sheet, nil)
         |> assign(:blocks, [])
         |> assign(:inherited_groups, [])
         |> assign(:gallery_data, %{})
         |> assign(:table_data, %{})
         |> assign(:sheets_tree, prepare_tree(Sheets.list_sheets_tree(project.id)))
         |> assign(:is_draft, false)
         |> assign(:source_shortcut, nil)
         |> assign(:current_tab, "content")
         |> assign(:references_data, nil)
         |> assign(:audio_data, nil)
         |> assign(:history_data, nil)
         |> assign(:online_users, [])
         |> assign(:collab_scope, nil)
         |> assign(:block_locks, %{})
         |> assign(:pending_delete_id, nil)
         |> assign(:formula_editing, nil)
         |> assign(:formula_search_results, [])
         |> assign(:formula_search_query, "")
         |> assign(:formula_search_offset, 0)
         |> assign(:formula_search_has_more, false)
         |> UndoRedoStack.init()}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("sheets", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(%{"id" => sheet_id} = params, _url, socket) do
    compact = params["layout"] == "compact"

    current_sheet_id =
      case socket.assigns.sheet do
        %{id: id} -> to_string(id)
        _ -> nil
      end

    socket = assign(socket, :compact, compact)

    if sheet_id == current_sheet_id do
      {:noreply, socket}
    else
      {:noreply, load_sheet(socket, sheet_id)}
    end
  end

  defp load_sheet(socket, sheet_id) do
    socket = teardown_sheet_collab(socket)
    %{project: project} = socket.assigns

    case Sheets.get_sheet_full(project.id, sheet_id) do
      nil ->
        socket
        |> put_flash(:error, dgettext("sheets", "Sheet not found."))
        |> push_navigate(
          to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets"
        )

      sheet ->
        # Setup collaboration
        scope = {:sheet, sheet.id}
        user = socket.assigns.current_scope.user

        if connected?(socket) do
          Collab.setup(socket, scope, user, cursors: false, locks: true, changes: true)
        end

        {online_users, block_locks} =
          if connected?(socket),
            do: Collab.get_initial_state(socket, scope),
            else: {[], %{}}

        {inherited_groups, own_blocks} = Sheets.get_sheet_blocks_grouped(sheet.id)
        all_blocks = Enum.flat_map(inherited_groups, & &1.blocks) ++ own_blocks

        gallery_block_ids =
          all_blocks |> Enum.filter(&(&1.type == "gallery")) |> Enum.map(& &1.id)

        gallery_data =
          if gallery_block_ids != [],
            do: Sheets.batch_load_gallery_data(gallery_block_ids),
            else: %{}

        table_block_ids =
          all_blocks |> Enum.filter(&(&1.type == "table")) |> Enum.map(& &1.id)

        table_data =
          if table_block_ids != [],
            do:
              Sheets.batch_load_table_data(table_block_ids)
              |> compute_formulas(project.id),
            else: %{}

        socket
        |> assign(:sheet, sheet)
        |> assign(:collab_scope, scope)
        |> assign(:online_users, online_users)
        |> assign(:block_locks, block_locks)
        |> assign(:blocks, own_blocks)
        |> assign(:inherited_groups, inherited_groups)
        |> assign(:gallery_data, gallery_data)
        |> assign(:table_data, table_data)
        |> assign(:current_tab, "content")
        |> assign(:references_data, nil)
        |> assign(:audio_data, nil)
        |> assign(:history_data, nil)
    end
  end

  # ===========================================================================
  # Event Handlers: Header
  # ===========================================================================

  @impl true
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

  # --- Tabs ---

  def handle_event("switch_tab", %{"tab" => tab}, socket)
      when tab in ~w(content references audio history) do
    if tab == "history" and socket.assigns.compact do
      {:noreply, socket}
    else
      socket = assign(socket, :current_tab, tab)

      socket =
        cond do
          tab == "references" && is_nil(socket.assigns.references_data) ->
            load_references_data(socket)

          tab == "audio" && is_nil(socket.assigns.audio_data) ->
            load_audio_data(socket)

          tab == "history" && is_nil(socket.assigns.history_data) ->
            load_history_data(socket)

          true ->
            socket
        end

      {:noreply, socket}
    end
  end

  def handle_event("switch_tab", _params, socket), do: {:noreply, socket}

  # --- Header (title, shortcut, color, banner, avatars) ---

  def handle_event("save_name", params, socket),
    do: HeaderHandlers.handle_save_name(params, socket, header_helpers())

  def handle_event("save_shortcut", params, socket),
    do: HeaderHandlers.handle_save_shortcut(params, socket, header_helpers())

  def handle_event("set_sheet_color", params, socket),
    do: HeaderHandlers.handle_set_color(params, socket, header_helpers())

  def handle_event("clear_sheet_color", params, socket),
    do: HeaderHandlers.handle_clear_color(params, socket, header_helpers())

  def handle_event("remove_banner", params, socket),
    do: HeaderHandlers.handle_remove_banner(params, socket, header_helpers())

  def handle_event("upload_banner", params, socket),
    do: HeaderHandlers.handle_upload_banner(params, socket, header_helpers())

  def handle_event("upload_avatar", params, socket),
    do: HeaderHandlers.handle_upload_avatar(params, socket, header_helpers())

  def handle_event("remove_avatar", params, socket),
    do: HeaderHandlers.handle_remove_avatar(params, socket, header_helpers())

  def handle_event("set_default_avatar", params, socket),
    do: HeaderHandlers.handle_set_default_avatar(params, socket, header_helpers())

  def handle_event("gallery_update_name", params, socket),
    do: HeaderHandlers.handle_gallery_update_name(params, socket, header_helpers())

  def handle_event("gallery_update_notes", params, socket),
    do: HeaderHandlers.handle_gallery_update_notes(params, socket, header_helpers())

  # --- Blocks (CRUD, toolbar, reorder, inheritance) ---

  def handle_event("add_block", params, socket),
    do: BlockHandlers.handle_add(params, socket, content_helpers())

  def handle_event("update_block_value", params, socket),
    do: BlockHandlers.handle_update_value(params, socket, content_helpers())

  def handle_event("toggle_multi_select", params, socket),
    do: BlockHandlers.handle_toggle_multi_select(params, socket, content_helpers())

  def handle_event("update_block_config", params, socket),
    do: BlockHandlers.handle_update_config(params, socket, content_helpers())

  def handle_event("delete_block", params, socket),
    do: BlockHandlers.handle_delete(params, socket, content_helpers())

  def handle_event("duplicate_block", params, socket),
    do: BlockHandlers.handle_duplicate(params, socket, content_helpers())

  def handle_event("undo", params, socket),
    do: BlockHandlers.handle_undo(params, socket, content_helpers())

  def handle_event("redo", params, socket),
    do: BlockHandlers.handle_redo(params, socket, content_helpers())

  def handle_event("reorder_column_group", params, socket),
    do: BlockHandlers.handle_reorder_column_group(params, socket, content_helpers())

  def handle_event("reorder_with_columns", params, socket),
    do: BlockHandlers.handle_reorder_with_columns(params, socket, content_helpers())

  def handle_event("toggle_constant", params, socket),
    do: BlockHandlers.handle_toggle_constant(params, socket, content_helpers())

  def handle_event("update_variable_name", params, socket),
    do: BlockHandlers.handle_update_variable_name(params, socket, content_helpers())

  def handle_event("change_block_scope", params, socket),
    do: BlockHandlers.handle_change_scope(params, socket, content_helpers())

  def handle_event("toggle_required", params, socket),
    do: BlockHandlers.handle_toggle_required(params, socket, content_helpers())

  def handle_event("reorder_blocks", params, socket),
    do: BlockHandlers.handle_reorder(params, socket, content_helpers())

  def handle_event("detach_block", params, socket),
    do: BlockHandlers.handle_detach(params, socket, content_helpers())

  def handle_event("reattach_block", params, socket),
    do: BlockHandlers.handle_reattach(params, socket, content_helpers())

  # --- Gallery blocks ---

  def handle_event("upload_gallery_image", params, socket),
    do: GalleryHandlers.handle_upload(params, socket, content_helpers())

  def handle_event("update_gallery_image", params, socket),
    do: GalleryHandlers.handle_update(params, socket, content_helpers())

  def handle_event("remove_gallery_image", params, socket),
    do: GalleryHandlers.handle_remove(params, socket, content_helpers())

  def handle_event("reorder_gallery_images", params, socket),
    do: GalleryHandlers.handle_reorder(params, socket, content_helpers())

  # --- Table blocks ---

  def handle_event("add_table_column", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_add_column(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("add_table_row", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_add_row(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("update_table_cell", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_update_cell(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("toggle_table_cell_boolean", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_toggle_cell_boolean(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("select_table_cell", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_select_table_cell(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("toggle_table_collapse", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_toggle_collapse(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("rename_table_column", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_rename_column(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("rename_table_row", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_rename_row(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("delete_table_column", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_delete_column(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("delete_table_row", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_delete_row(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("reorder_table_rows", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_reorder_rows(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("resize_table_column", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      TableHandlers.handle_resize_column(params, socket)
    end)
  end

  def handle_event("change_table_column_type", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_change_column_type(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("toggle_table_column_constant", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_toggle_column_constant(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("toggle_table_column_required", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_toggle_column_required(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("toggle_reference_multiple", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_toggle_reference_multiple(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("update_number_constraint", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_update_number_constraint(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("toggle_table_cell_multi_select", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_toggle_table_cell_multi_select(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("add_table_cell_option", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_add_table_cell_option(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("add_table_column_option", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_add_column_option(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("remove_table_column_option", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_remove_column_option(params, socket, table_helpers(socket))
      end)
    end)
  end

  def handle_event("update_table_column_option", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_table_broadcast(socket, fn ->
        TableHandlers.handle_update_column_option(params, socket, table_helpers(socket))
      end)
    end)
  end

  # --- Select option management ---

  def handle_event("add_select_option", params, socket),
    do: SelectOptionHandlers.handle_add(params, socket, content_helpers())

  def handle_event("remove_select_option", params, socket),
    do: SelectOptionHandlers.handle_remove(params, socket, content_helpers())

  def handle_event("update_select_option", params, socket),
    do: SelectOptionHandlers.handle_update(params, socket, content_helpers())

  # --- Reference blocks ---

  def handle_event("search_references", params, socket),
    do: ReferenceHandlers.handle_search(params, socket, content_helpers())

  def handle_event("select_reference", params, socket),
    do: ReferenceHandlers.handle_select(params, socket, content_helpers())

  def handle_event("clear_reference", params, socket),
    do: ReferenceHandlers.handle_clear(params, socket, content_helpers())

  # --- Formula sidebar ---

  def handle_event("open_formula_sidebar", params, socket),
    do: FormulaHandlers.handle_open(params, socket, formula_handler_helpers())

  def handle_event("close_formula_sidebar", params, socket),
    do: FormulaHandlers.handle_close(params, socket, formula_handler_helpers())

  def handle_event("save_formula_expression", params, socket),
    do: FormulaHandlers.handle_save_expression(params, socket, formula_handler_helpers())

  def handle_event("save_formula_binding", params, socket),
    do: FormulaHandlers.handle_save_binding(params, socket, formula_handler_helpers())

  def handle_event("search_formula_bindings", params, socket),
    do: FormulaHandlers.handle_search(params, socket, formula_handler_helpers())

  def handle_event("load_more_formula_bindings", params, socket),
    do: FormulaHandlers.handle_load_more(params, socket, formula_handler_helpers())

  # --- Tree (create, delete, move) ---

  def handle_event("create_sheet", params, socket),
    do: TreeHandlers.handle_create(params, socket, tree_helpers())

  def handle_event("create_child_sheet", params, socket),
    do: TreeHandlers.handle_create_child(params, socket, tree_helpers())

  def handle_event("set_pending_delete_sheet", params, socket),
    do: TreeHandlers.handle_set_pending_delete(params, socket, tree_helpers())

  def handle_event("confirm_delete_sheet", params, socket),
    do: TreeHandlers.handle_confirm_delete(params, socket, tree_helpers())

  def handle_event("move_to_parent", params, socket),
    do: TreeHandlers.handle_move(params, socket, tree_helpers())

  # --- Audio tab ---

  def handle_event("select_audio", params, socket),
    do: AudioHandlers.handle_select(params, socket, content_helpers())

  def handle_event("remove_audio", params, socket),
    do: AudioHandlers.handle_remove(params, socket, content_helpers())

  def handle_event("upload_audio", params, socket),
    do: AudioHandlers.handle_upload(params, socket, content_helpers())

  # --- History (versions, restore) ---

  def handle_event("compare_version", params, socket),
    do: HistoryHandlers.handle_compare(params, socket, history_helpers())

  def handle_event("create_version", params, socket),
    do: HistoryHandlers.handle_create(params, socket, history_helpers())

  def handle_event("promote_version", params, socket),
    do: HistoryHandlers.handle_promote(params, socket, history_helpers())

  def handle_event("delete_version", params, socket),
    do: HistoryHandlers.handle_delete(params, socket, history_helpers())

  def handle_event("load_more_versions", params, socket),
    do: HistoryHandlers.handle_load_more(params, socket, history_helpers())

  def handle_event("preview_restore", params, socket),
    do: HistoryHandlers.handle_preview_restore(params, socket, history_helpers())

  def handle_event("save_and_restore", params, socket),
    do: HistoryHandlers.handle_save_and_restore(params, socket, history_helpers())

  def handle_event("discard_and_restore", params, socket),
    do: HistoryHandlers.handle_discard_and_restore(params, socket, history_helpers())

  def handle_event("confirm_restore", params, socket),
    do: HistoryHandlers.handle_confirm_restore(params, socket, history_helpers())

  # --- Block locking ---

  def handle_event("acquire_block_lock", params, socket),
    do: LockHandlers.handle_acquire(params, socket)

  def handle_event("release_block_lock", params, socket),
    do: LockHandlers.handle_release(params, socket)

  def handle_event("refresh_block_lock", params, socket),
    do: LockHandlers.handle_refresh(params, socket)

  # ===========================================================================
  # Handle Info
  # ===========================================================================

  @impl true
  def handle_info({:project_restoration_started, payload}, socket),
    do: RestorationHandlers.handle_restoration_event({:project_restoration_started, payload}, socket)

  def handle_info({:project_restoration_completed, payload}, socket),
    do:
      RestorationHandlers.handle_restoration_event(
        {:project_restoration_completed, payload},
        socket
      )

  def handle_info({:project_restoration_failed, payload}, socket),
    do:
      RestorationHandlers.handle_restoration_event(
        {:project_restoration_failed, payload},
        socket
      )

  def handle_info({Storyarn.Collaboration.Presence, {:join, presence}}, socket) do
    Collab.handle_presence_join(socket, presence)
  end

  def handle_info({Storyarn.Collaboration.Presence, {:leave, _} = event}, socket) do
    Collab.handle_presence_leave(socket, elem(event, 1))
  end

  def handle_info({:lock_change, _action, _payload}, socket) do
    if scope = socket.assigns[:collab_scope] do
      block_locks = Collaboration.list_locks(scope)
      {:noreply, assign(socket, :block_locks, block_locks)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:remote_change, action, payload}, socket) do
    handle_remote_change(action, payload, socket)
  end

  def handle_info({:table_push_undo, action}, socket) do
    {:noreply, UndoRedoStack.push_undo(socket, action)}
  end

  # ===========================================================================
  # Terminate
  # ===========================================================================

  @impl true
  def terminate(_reason, socket) do
    teardown_sheet_collab(socket)
  end

  # ===========================================================================
  # Collaboration Helpers
  # ===========================================================================

  defp teardown_sheet_collab(socket) do
    if scope = socket.assigns[:collab_scope] do
      user_id = socket.assigns.current_scope.user.id
      Collab.teardown(scope, user_id)
    end

    socket
    |> assign(:collab_scope, nil)
    |> assign(:online_users, [])
    |> assign(:block_locks, %{})
  end

  defp broadcast_sheet_change(socket, action, extra_payload \\ %{}) do
    if scope = socket.assigns[:collab_scope] do
      Collab.broadcast_change(socket, scope, action, extra_payload)
    end

    socket
  end

  defp broadcast_project_change(socket, action, extra_payload \\ %{}) do
    project_scope = {:project, socket.assigns.project.id}
    Collab.broadcast_change(socket, project_scope, action, extra_payload)
    socket
  end

  defp with_table_broadcast(_socket, fun) do
    case fun.() do
      {:noreply, updated_socket} ->
        {:noreply, broadcast_sheet_change(updated_socket, :block_updated)}

      other ->
        other
    end
  end

  defp show_collab_toast(socket, action, payload) do
    push_event(socket, "collab_toast", %{
      action: to_string(action),
      userEmail: payload[:user_email] || "Unknown",
      userColor: payload[:user_color] || "#666"
    })
  end

  defp handle_remote_change(:block_updated, payload, socket) do
    {:noreply,
     socket
     |> reload_blocks()
     |> show_collab_toast(:block_updated, payload)}
  end

  defp handle_remote_change(:block_created, payload, socket) do
    {:noreply,
     socket
     |> reload_blocks()
     |> show_collab_toast(:block_created, payload)}
  end

  defp handle_remote_change(:block_deleted, payload, socket) do
    {:noreply,
     socket
     |> reload_blocks()
     |> show_collab_toast(:block_deleted, payload)}
  end

  defp handle_remote_change(:block_reordered, _payload, socket) do
    {:noreply, reload_blocks(socket)}
  end

  defp handle_remote_change(:block_type_changed, payload, socket) do
    {:noreply,
     socket
     |> reload_blocks()
     |> show_collab_toast(:block_type_changed, payload)}
  end

  defp handle_remote_change(:sheet_updated, payload, socket) do
    sheet = Sheets.get_sheet_full!(socket.assigns.project.id, socket.assigns.sheet.id)

    {:noreply,
     socket
     |> assign(:sheet, sheet)
     |> assign(:sheets_tree, prepare_tree(Sheets.list_sheets_tree(socket.assigns.project.id)))
     |> push_event("sheet_updated_remote", %{name: sheet.name, shortcut: sheet.shortcut})
     |> show_collab_toast(:sheet_updated, payload)}
  end

  defp handle_remote_change(:tree_changed, _payload, socket) do
    {:noreply,
     assign(socket, :sheets_tree, prepare_tree(Sheets.list_sheets_tree(socket.assigns.project.id)))}
  end

  defp handle_remote_change(:sheet_restored, payload, socket) do
    sheet = Sheets.get_sheet_full!(socket.assigns.project.id, socket.assigns.sheet.id)

    socket =
      socket
      |> assign(:sheet, sheet)
      |> reload_blocks()
      |> UndoRedoStack.clear()
      |> assign(:history_data, nil)

    socket =
      if socket.assigns.current_tab == "history",
        do: load_history_data(socket),
        else: socket

    {:noreply, show_collab_toast(socket, :sheet_restored, payload)}
  end

  defp handle_remote_change(_action, _payload, socket) do
    {:noreply, socket}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp tree_helpers do
    %{
      reload_blocks: &reload_blocks/1,
      broadcast_project: &broadcast_project_change/2
    }
  end

  defp formula_handler_helpers do
    %{
      handle_formula_cell: &TableHandlers.handle_update_formula_cell/3,
      table_helpers: &table_helpers/1,
      broadcast: &broadcast_sheet_change/2
    }
  end

  defp history_helpers do
    %{
      reload_blocks: &reload_blocks/1,
      broadcast: &broadcast_sheet_change/2,
      clear_undo: &UndoRedoStack.clear/1
    }
  end

  defp content_helpers do
    %{
      reload_blocks: &reload_blocks/1,
      broadcast: &broadcast_sheet_change/2,
      broadcast_with_payload: &broadcast_sheet_change/3,
      parse_id: &MapUtils.parse_int/1,
      push_undo: fn socket, action -> UndoRedoStack.push_undo(socket, action) end,
      block_to_snapshot: &UndoRedoHandlers.block_to_snapshot/1,
      push_block_value_coalesced: &UndoRedoHandlers.push_block_value_coalesced/4,
      handle_undo: &UndoRedoHandlers.handle_undo/2,
      handle_redo: &UndoRedoHandlers.handle_redo/2
    }
  end

  defp header_helpers do
    %{
      reload_sheet: &reload_sheet/1,
      reload_sheet_and_tree: &reload_sheet_and_tree/1,
      broadcast: &broadcast_sheet_change/2,
      parse_id: &MapUtils.parse_int/1,
      prepare_tree: fn project_id ->
        prepare_tree(Sheets.list_sheets_tree(project_id))
      end
    }
  end

  defp table_helpers(_socket) do
    pid = self()

    %{
      reload_blocks: &reload_blocks/1,
      maybe_create_version: fn _socket -> :ok end,
      notify_parent: fn _socket, _status -> :ok end,
      push_undo: fn action -> send(pid, {:table_push_undo, action}) end
    }
  end

  defp reload_sheet(socket) do
    sheet = Sheets.get_sheet_full!(socket.assigns.project.id, socket.assigns.sheet.id)
    assign(socket, :sheet, sheet)
  end

  defp reload_blocks(socket) do
    sheet_id = socket.assigns.sheet.id
    {inherited_groups, own_blocks} = Sheets.get_sheet_blocks_grouped(sheet_id)
    all_blocks = Enum.flat_map(inherited_groups, & &1.blocks) ++ own_blocks

    gallery_block_ids = all_blocks |> Enum.filter(&(&1.type == "gallery")) |> Enum.map(& &1.id)

    gallery_data =
      if gallery_block_ids != [], do: Sheets.batch_load_gallery_data(gallery_block_ids), else: %{}

    table_block_ids = all_blocks |> Enum.filter(&(&1.type == "table")) |> Enum.map(& &1.id)

    project_id = socket.assigns.project.id

    table_data =
      if table_block_ids != [],
        do:
          Sheets.batch_load_table_data(table_block_ids)
          |> compute_formulas(project_id),
        else: %{}

    socket
    |> assign(:blocks, own_blocks)
    |> assign(:inherited_groups, inherited_groups)
    |> assign(:gallery_data, gallery_data)
    |> assign(:table_data, table_data)
  end

  defp reload_sheet_and_tree(socket) do
    socket
    |> reload_sheet()
    |> assign(:sheets_tree, prepare_tree(Sheets.list_sheets_tree(socket.assigns.project.id)))
  end
end
