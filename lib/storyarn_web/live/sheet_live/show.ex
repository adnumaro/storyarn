defmodule StoryarnWeb.SheetLive.Show do
  @moduledoc """
  V2 Sheet editor — Phase 1: Header only (banner, avatar, title, color).
  Same backend logic as SheetLive.Show, Vue + shadcn UI.
  """

  use StoryarnWeb, :live_view

  import StoryarnWeb.Live.Shared.RestorationHandlers, only: [check_restoration_lock: 2]
  import StoryarnWeb.SheetLive.Helpers.AudioDataHelpers
  import StoryarnWeb.SheetLive.Helpers.FormulaHelpers
  import StoryarnWeb.SheetLive.Helpers.HistoryDataHelpers
  import StoryarnWeb.SheetLive.Helpers.PropsSerializer
  import StoryarnWeb.SheetLive.Helpers.ReferencesDataHelpers

  alias Storyarn.Analytics
  alias Storyarn.Collaboration
  alias Storyarn.Collaboration.Presence
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Sheets
  alias Storyarn.Versioning
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Helpers.UndoRedoStack
  alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: Collab
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers
  alias StoryarnWeb.Live.Shared.RestorationHandlers
  alias StoryarnWeb.SheetLive.Handlers.AudioHandlers
  alias StoryarnWeb.SheetLive.Handlers.BlockHandlers
  alias StoryarnWeb.SheetLive.Handlers.FormulaHandlers
  alias StoryarnWeb.SheetLive.Handlers.GalleryHandlers
  alias StoryarnWeb.SheetLive.Handlers.HeaderHandlers
  alias StoryarnWeb.SheetLive.Handlers.HistoryHandlers
  alias StoryarnWeb.SheetLive.Handlers.LockHandlers
  alias StoryarnWeb.SheetLive.Handlers.ReferenceHandlers
  alias StoryarnWeb.SheetLive.Handlers.SelectOptionHandlers
  alias StoryarnWeb.SheetLive.Handlers.TableHandlers
  alias StoryarnWeb.SheetLive.Handlers.UndoRedoHandlers

  @sheet_tabs ~w(content references audio history)

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
    <StoryarnWeb.Components.ProjectLayout.project
      socket={@socket}
      flash={@flash}
      project={@project}
      workspace={@workspace}
      current_scope={@current_scope}
      current_user={@current_user}
      membership={@membership}
      urls={@urls}
      active_tool={:sheets}
      is_super_admin={@is_super_admin}
      online_users={@online_users}
      restoration_banner={@restoration_banner}
      onboarding={@onboarding}
      onboarding_autostart
      sidebar_module={StoryarnWeb.SheetsSidebarLive}
      sidebar_session={
        %{
          "project_id" => @project.id,
          "workspace_slug" => @workspace.slug,
          "project_slug" => @project.slug,
          "sheet_id" => @sheet && to_string(@sheet.id),
          "can_edit" => @can_edit,
          "active_tool" => "sheets",
          "dashboard_url" => ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets",
          "current_scope" => @current_scope,
          "locale" => @locale
        }
      }
    >
      <.sheet_content
        inject="project-layout"
        sheet={@sheet}
        socket={@socket}
        current_tab={@current_tab}
        can_edit={@can_edit}
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
    </StoryarnWeb.Components.ProjectLayout.project>
    """
  end

  defp render_compact(assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare
      socket={@socket}
      flash={@flash}
      content_class="h-full overflow-y-auto bg-background p-4"
    >
      <.sheet_content
        inject="compare-layout"
        sheet={@sheet}
        socket={@socket}
        current_tab={@current_tab}
        can_edit={@can_edit}
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
    </StoryarnWeb.Components.CompareLayout.compare>
    """
  end

  attr :sheet, :map, default: nil
  attr :socket, :any, required: true
  attr :current_tab, :string, required: true
  attr :can_edit, :boolean, required: true
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
  attr :inject, :string, default: nil

  defp sheet_content(assigns) do
    ~H"""
    <.vue
      v-component="live/sheet/show/SheetSurface"
      v-socket={@socket}
      v-inject={@inject}
      id="sheet-surface"
      class="contents"
      sheet={prepare_sheet_for_vue(@sheet)}
      can-edit={@can_edit}
      source-shortcut={@source_shortcut}
      surface={sheet_surface_props(assigns)}
      panels={sheet_panels_props(assigns)}
    />
    """
  end

  defp sheet_surface_props(assigns) do
    %{
      tabs: %{
        currentTab: assigns.current_tab,
        canEdit: assigns.can_edit,
        compact: assigns.compact
      },
      content: sheet_surface_content_props(assigns)
    }
  end

  defp sheet_surface_content_props(%{current_tab: "content"} = assigns) do
    %{
      blocks:
        prepare_blocks_for_vue(
          assigns.blocks,
          assigns.gallery_data,
          assigns.table_data,
          assigns.project.id,
          assigns.inherited_groups
        ),
      inheritedGroups:
        prepare_inherited_groups_for_vue(
          assigns.inherited_groups,
          assigns.gallery_data,
          assigns.table_data,
          assigns.project.id
        ),
      workspaceSlug: assigns.workspace.slug,
      projectSlug: assigns.project.slug,
      canEdit: assigns.can_edit,
      formulaEditing:
        build_formula_editing_for_vue(
          assigns.formula_editing,
          assigns.formula_search_results,
          assigns.formula_search_has_more
        ),
      blockLocks: serialize_block_locks(assigns.block_locks),
      currentUserId: assigns.current_user_id
    }
  end

  defp sheet_surface_content_props(_assigns), do: nil

  defp sheet_panels_props(assigns) do
    %{
      currentTab: assigns.current_tab,
      compact: assigns.compact,
      references: sheet_references_panel_props(assigns),
      audio: sheet_audio_panel_props(assigns),
      history: sheet_history_panel_props(assigns)
    }
  end

  defp sheet_references_panel_props(%{current_tab: "references"} = assigns) do
    references_data = assigns.references_data || %{}

    %{
      variableUsage: references_data[:variable_usage] || [],
      backlinks: references_data[:backlinks] || [],
      sceneAppearances: references_data[:scene_appearances] || [],
      workspaceSlug: assigns.workspace.slug,
      projectSlug: assigns.project.slug,
      loading: is_nil(assigns.references_data)
    }
  end

  defp sheet_references_panel_props(_assigns), do: nil

  defp sheet_audio_panel_props(%{current_tab: "audio"} = assigns) do
    audio_data = assigns.audio_data || %{}

    %{
      groupedLines: audio_data[:grouped_lines] || [],
      audioAssets: audio_data[:audio_assets] || [],
      workspaceSlug: assigns.workspace.slug,
      projectSlug: assigns.project.slug,
      canEdit: assigns.can_edit,
      loading: is_nil(assigns.audio_data)
    }
  end

  defp sheet_audio_panel_props(_assigns), do: nil

  defp sheet_history_panel_props(%{current_tab: "history", compact: false} = assigns) do
    history_data = assigns.history_data || %{}

    %{
      versions: history_data[:versions] || [],
      namedVersions: history_data[:named_versions] || [],
      autoVersions: history_data[:auto_versions] || [],
      hasMore: history_data[:has_more] || false,
      canNameVersion: history_data[:can_name_version] || false,
      currentVersionId: history_data[:current_version_id],
      canEdit: assigns.can_edit,
      restoreEnabled:
        assigns.can_edit &&
          Versioning.restore_enabled?({:entity_version_restore, "sheet"}),
      loading: is_nil(assigns.history_data)
    }
  end

  defp sheet_history_panel_props(_assigns), do: nil

  # ===========================================================================
  # Mount & Lifecycle
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    %{project: project, can_edit: can_edit} = socket.assigns

    if connected?(socket) do
      Collaboration.subscribe_restoration(project.id)
      Collaboration.subscribe_changes({:project, project.id})

      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        StoryarnWeb.SheetsSidebarLive.shell_topic(project.id)
      )
    end

    {can_edit, restoration_banner} = check_restoration_lock(project.id, can_edit)

    {:ok,
     socket
     |> assign(:can_edit, can_edit)
     |> assign(:restoration_banner, restoration_banner)
     |> assign(:compact, false)
     |> assign(:sheet, nil)
     |> assign(:blocks, [])
     |> assign(:inherited_groups, [])
     |> assign(:gallery_data, %{})
     |> assign(:table_data, %{})
     |> assign(:source_shortcut, nil)
     |> assign(:current_tab, "content")
     |> assign(:references_data, nil)
     |> assign(:audio_data, nil)
     |> assign(:history_data, nil)
     |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))
     |> assign(:collab_scope, nil)
     |> assign(:block_locks, %{})
     |> assign(:pending_delete_id, nil)
     |> assign(:formula_editing, nil)
     |> assign(:formula_search_results, [])
     |> assign(:formula_search_query, "")
     |> assign(:formula_search_offset, 0)
     |> assign(:formula_search_has_more, false)
     |> UndoRedoStack.init()}
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

    socket =
      if sheet_id == current_sheet_id do
        socket
      else
        load_sheet(socket, sheet_id)
      end

    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      StoryarnWeb.SheetsSidebarLive.shell_topic(socket.assigns.project.id),
      {:active_sheet, sheet_id}
    )

    {:noreply, socket}
  end

  defp load_sheet(socket, sheet_id) do
    socket = teardown_sheet_collab(socket)
    %{project: project} = socket.assigns

    case Sheets.get_sheet_full(project.id, sheet_id) do
      nil ->
        socket
        |> put_flash(:error, dgettext("sheets", "Sheet not found."))
        |> push_navigate(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")

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
          if gallery_block_ids == [],
            do: %{},
            else: Sheets.batch_load_gallery_data(gallery_block_ids)

        table_block_ids =
          all_blocks |> Enum.filter(&(&1.type == "table")) |> Enum.map(& &1.id)

        table_data =
          if table_block_ids == [],
            do: %{},
            else:
              table_block_ids
              |> Sheets.batch_load_table_data()
              |> compute_formulas(project.id)

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

  # --- Tabs ---

  @impl true
  def handle_event(event, _params, socket) when event in ~w(main_sidebar_toggle main_sidebar_pin main_sidebar_init) do
    {:noreply, socket}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in @sheet_tabs do
    track_sheet_history_opened(socket, tab)
    {:noreply, maybe_switch_tab(socket, tab)}
  end

  def handle_event("switch_tab", _params, socket), do: {:noreply, socket}

  # --- Header (title, shortcut, color, banner, avatars) ---

  def handle_event("save_name", params, socket), do: HeaderHandlers.handle_save_name(params, socket, header_helpers())

  def handle_event("save_shortcut", params, socket),
    do: HeaderHandlers.handle_save_shortcut(params, socket, header_helpers())

  def handle_event("set_sheet_color", params, socket),
    do: HeaderHandlers.handle_set_color(params, socket, header_helpers())

  def handle_event("clear_sheet_color", params, socket),
    do: HeaderHandlers.handle_clear_color(params, socket, header_helpers())

  def handle_event("remove_banner", params, socket),
    do: HeaderHandlers.handle_remove_banner(params, socket, header_helpers())

  def handle_event("attach_banner", params, socket),
    do: HeaderHandlers.handle_attach_banner(params, socket, header_helpers())

  def handle_event("attach_avatar", params, socket),
    do: HeaderHandlers.handle_attach_avatar(params, socket, header_helpers())

  def handle_event("remove_avatar", params, socket),
    do: HeaderHandlers.handle_remove_avatar(params, socket, header_helpers())

  def handle_event("set_default_avatar", params, socket),
    do: HeaderHandlers.handle_set_default_avatar(params, socket, header_helpers())

  def handle_event("gallery_update_name", params, socket),
    do: HeaderHandlers.handle_gallery_update_name(params, socket, header_helpers())

  def handle_event("gallery_update_notes", params, socket),
    do: HeaderHandlers.handle_gallery_update_notes(params, socket, header_helpers())

  # --- Blocks (CRUD, toolbar, reorder, inheritance) ---

  def handle_event("add_block", params, socket), do: BlockHandlers.handle_add(params, socket, content_helpers())

  def handle_event("update_block_value", params, socket),
    do: BlockHandlers.handle_update_value(params, socket, content_helpers())

  def handle_event("toggle_multi_select", params, socket),
    do: BlockHandlers.handle_toggle_multi_select(params, socket, content_helpers())

  def handle_event("update_block_config", params, socket),
    do: BlockHandlers.handle_update_config(params, socket, content_helpers())

  def handle_event("delete_block", params, socket), do: BlockHandlers.handle_delete(params, socket, content_helpers())

  def handle_event("duplicate_block", params, socket),
    do: BlockHandlers.handle_duplicate(params, socket, content_helpers())

  def handle_event("undo", params, socket), do: BlockHandlers.handle_undo(params, socket, content_helpers())

  def handle_event("redo", params, socket), do: BlockHandlers.handle_redo(params, socket, content_helpers())

  def handle_event("reorder_layout", params, socket),
    do: BlockHandlers.handle_reorder_layout(params, socket, content_helpers())

  def handle_event("toggle_constant", params, socket),
    do: BlockHandlers.handle_toggle_constant(params, socket, content_helpers())

  def handle_event("update_variable_name", params, socket),
    do: BlockHandlers.handle_update_variable_name(params, socket, content_helpers())

  def handle_event("change_block_scope", params, socket),
    do: BlockHandlers.handle_change_scope(params, socket, content_helpers())

  def handle_event("toggle_required", params, socket),
    do: BlockHandlers.handle_toggle_required(params, socket, content_helpers())

  def handle_event("detach_block", params, socket), do: BlockHandlers.handle_detach(params, socket, content_helpers())

  def handle_event("reattach_block", params, socket), do: BlockHandlers.handle_reattach(params, socket, content_helpers())

  # --- Gallery blocks ---

  def handle_event("attach_gallery_image", params, socket),
    do: GalleryHandlers.handle_attach(params, socket, content_helpers())

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

  # --- Select option management (unified: block + column) ---

  def handle_event("add_option", params, socket), do: SelectOptionHandlers.handle_add(params, socket, content_helpers())

  def handle_event("remove_option", params, socket),
    do: SelectOptionHandlers.handle_remove(params, socket, content_helpers())

  def handle_event("update_option", params, socket),
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

  # Tree events (create, delete, move) handled by SheetsSidebarLive — not here.

  # --- Audio tab ---

  def handle_event("select_audio", params, socket), do: AudioHandlers.handle_select(params, socket, content_helpers())

  def handle_event("remove_audio", params, socket), do: AudioHandlers.handle_remove(params, socket, content_helpers())

  def handle_event("upload_audio", params, socket), do: AudioHandlers.handle_upload(params, socket, content_helpers())

  # --- History (versions, restore) ---

  def handle_event("compare_version", params, socket),
    do: HistoryHandlers.handle_compare(params, socket, history_helpers())

  def handle_event("create_version", params, socket), do: HistoryHandlers.handle_create(params, socket, history_helpers())

  def handle_event("promote_version", params, socket),
    do: HistoryHandlers.handle_promote(params, socket, history_helpers())

  def handle_event("delete_version", params, socket), do: HistoryHandlers.handle_delete(params, socket, history_helpers())

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

  def handle_event("acquire_block_lock", params, socket), do: LockHandlers.handle_acquire(params, socket)

  def handle_event("release_block_lock", params, socket), do: LockHandlers.handle_release(params, socket)

  def handle_event("refresh_block_lock", params, socket), do: LockHandlers.handle_refresh(params, socket)

  # ===========================================================================
  # Handle Info
  # ===========================================================================

  @impl true
  def handle_info({:project_restoration_started, payload}, socket),
    do: RestorationHandlers.handle_restoration_event({:project_restoration_started, payload}, socket)

  def handle_info({:project_restoration_completed, payload}, socket),
    do: RestorationHandlers.handle_restoration_event({:project_restoration_completed, payload}, socket)

  def handle_info({:project_restoration_failed, payload}, socket),
    do: RestorationHandlers.handle_restoration_event({:project_restoration_failed, payload}, socket)

  # Shell-topic messages from SheetsSidebarLive:
  def handle_info({:open_sheet, sheet_id}, socket) do
    path =
      ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{sheet_id}"

    {:noreply, push_navigate(socket, to: path)}
  end

  def handle_info({:active_sheet, _sheet_id}, socket), do: {:noreply, socket}
  def handle_info({:active_flow, _flow_id}, socket), do: {:noreply, socket}
  def handle_info({:active_scene, _scene_id}, socket), do: {:noreply, socket}
  def handle_info({:active_locale, _locale}, socket), do: {:noreply, socket}
  def handle_info({:tree_changed, :sheets}, socket), do: {:noreply, socket}

  def handle_info({:entities_deleted, :sheet, ids}, socket) do
    if socket.assigns.sheet.id in ids do
      {:noreply,
       push_navigate(socket,
         to: ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:entities_deleted, _type, _ids}, socket), do: {:noreply, socket}

  def handle_info({:toolbar_event, _event, _params}, socket), do: {:noreply, socket}
  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}

  def handle_info({Presence, {:join, presence}}, socket) do
    Collab.handle_presence_join(socket, presence)
  end

  def handle_info({Presence, {:leave, _} = event}, socket) do
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
      userEmail: payload[:user_email] || dgettext("sheets", "Unknown"),
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
     |> push_event("sheet_updated_remote", %{name: sheet.name, shortcut: sheet.shortcut})
     |> show_collab_toast(:sheet_updated, payload)}
  end

  # Tree shape changes are picked up by SheetsSidebarLive directly (it subscribes
  # to project-level Collaboration changes). Nothing to do here.
  defp handle_remote_change(:tree_changed, _payload, socket), do: {:noreply, socket}

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

  defp maybe_switch_tab(%{assigns: %{compact: true}} = socket, "history"), do: socket

  defp maybe_switch_tab(socket, tab) do
    socket
    |> assign(:current_tab, tab)
    |> maybe_load_tab_data(tab)
  end

  defp track_sheet_history_opened(socket, "history") do
    if !(socket.assigns.current_tab == "history" or socket.assigns.compact) do
      Analytics.track(socket.assigns.current_scope, "version panel opened", %{
        entity_type: "sheet",
        project_id: socket.assigns.project.id
      })
    end
  end

  defp track_sheet_history_opened(_socket, _tab), do: :ok

  defp maybe_load_tab_data(socket, "references") do
    maybe_load_assign(socket, :references_data, &load_references_data/1)
  end

  defp maybe_load_tab_data(socket, "audio") do
    maybe_load_assign(socket, :audio_data, &load_audio_data/1)
  end

  defp maybe_load_tab_data(socket, "history") do
    maybe_load_assign(socket, :history_data, &load_history_data/1)
  end

  defp maybe_load_tab_data(socket, _tab), do: socket

  defp maybe_load_assign(socket, assign_name, loader) do
    if is_nil(socket.assigns[assign_name]), do: loader.(socket), else: socket
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
      broadcast: &broadcast_sheet_change/2,
      broadcast_tree_changed: &broadcast_sheet_tree_changed/1,
      parse_id: &MapUtils.parse_int/1
    }
  end

  defp broadcast_sheet_tree_changed(project_id) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      StoryarnWeb.SheetsSidebarLive.shell_topic(project_id),
      {:tree_changed, :sheets}
    )
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
      if gallery_block_ids == [], do: %{}, else: Sheets.batch_load_gallery_data(gallery_block_ids)

    table_block_ids = all_blocks |> Enum.filter(&(&1.type == "table")) |> Enum.map(& &1.id)

    project_id = socket.assigns.project.id

    table_data =
      if table_block_ids == [],
        do: %{},
        else:
          table_block_ids
          |> Sheets.batch_load_table_data()
          |> compute_formulas(project_id)

    socket
    |> assign(:blocks, own_blocks)
    |> assign(:inherited_groups, inherited_groups)
    |> assign(:gallery_data, gallery_data)
    |> assign(:table_data, table_data)
  end
end
