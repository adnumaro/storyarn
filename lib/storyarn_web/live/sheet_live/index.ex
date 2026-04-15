defmodule StoryarnWeb.SheetLive.Index do
  @moduledoc """
  V2 Sheets dashboard — same logic as SheetLive.Index, Vue + shadcn UI.
  """

  use StoryarnWeb, :live_view

  import StoryarnWeb.Components.DashboardComponents,
    only: [
      sort_table: 4,
      paginate: 2,
      handle_sort: 5,
      handle_page: 4,
      reload_dashboard: 6
    ]

  use StoryarnWeb.Live.Shared.DashboardHandlers

  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Sheets

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.ProjectShell.project_shell
      socket={@socket}
      project={@project}
      workspace={@workspace}
      current_scope={@current_scope}
      current_user={@current_user}
      urls={@urls}
      sheet_id={nil}
      active_tool={:sheets}
      can_edit={@can_edit}
      is_super_admin={@is_super_admin}
      dashboard_url={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets"}
    >
      <.vue
        v-component="modules/sheets/SheetDashboard"
        v-socket={@socket}
        id="sheet-dashboard"
        stats={@dashboard_stats}
        table-data={@sheet_table_data}
        pagination={
          %{
            sortBy: @sort_by,
            sortDir: to_string(@sort_dir),
            page: @page,
            totalPages: @total_pages,
            total: length(@all_sheet_table_data)
          }
        }
        issues={@sheet_issues}
        can-edit={@can_edit}
        workspace-slug={@workspace.slug}
        project-slug={@project.slug}
      />
    </StoryarnWeb.Components.ProjectShell.project_shell>
    """
  end

  # ===========================================================================
  # Mount & Lifecycle
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    %{project: project} = socket.assigns
    sheets_tree = Sheets.list_sheets_tree(project.id)
    sheets = Sheets.list_all_sheets(project.id)

    if connected?(socket) do
      Collaboration.subscribe_dashboard(project.id)

      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        StoryarnWeb.SidebarLive.shell_topic(project.id)
      )

      if sheets != [], do: send(self(), :load_dashboard_data)
    end

    {:ok,
     socket
     |> assign(:online_users, [])
     |> assign(:sheets_tree, prepare_tree(sheets_tree))
     |> assign(:sheets, sheets)
     |> assign(:dashboard_stats, nil)
     |> assign(:all_sheet_table_data, [])
     |> assign(:sheet_table_data, [])
     |> assign(:sheet_issues, [])
     |> assign(:sort_by, "name")
     |> assign(:sort_dir, :asc)
     |> assign(:page, 1)
     |> assign(:total_pages, 1)
     |> assign(:pending_delete_id, nil)}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # ===========================================================================
  # Dashboard loading (async)
  # ===========================================================================

  # Shell-topic messages from SidebarLive:
  def handle_info({:open_sheet, sheet_id}, socket) do
    path =
      ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{sheet_id}"

    {:noreply, push_navigate(socket, to: path)}
  end

  def handle_info({:active_sheet, _sheet_id}, socket), do: {:noreply, socket}
  def handle_info({:tree_changed, :sheets}, socket), do: {:noreply, reload_sheets(socket)}
  def handle_info({:toolbar_event, _event, _params}, socket), do: {:noreply, socket}

  def handle_info(:load_dashboard_data, socket) do
    %{project: project, workspace: workspace, sort_by: sort_by, sort_dir: sort_dir} =
      socket.assigns

    {:noreply,
     start_async(socket, :load_dashboard_data, fn ->
       load_dashboard_data_async(project.id, workspace, project, sort_by, sort_dir)
     end)}
  end

  @impl true
  def handle_async(:load_dashboard_data, {:ok, data}, socket) do
    {:noreply,
     socket
     |> assign(:dashboard_stats, data.dashboard_stats)
     |> assign(:all_sheet_table_data, data.sorted_table)
     |> assign(:sheet_table_data, data.page_rows)
     |> assign(:page, 1)
     |> assign(:total_pages, data.total_pages)
     |> assign(:sheet_issues, data.formatted_issues)}
  end

  def handle_async(:load_dashboard_data, {:exit, _reason}, socket), do: {:noreply, socket}

  defp load_dashboard_data_async(project_id, workspace, project, sort_by, sort_dir) do
    sheets = Sheets.list_all_sheets(project_id)

    stats =
      DashboardCache.fetch(project_id, :sheet_stats, fn ->
        Sheets.sheet_stats_for_project(project_id)
      end)

    word_counts =
      DashboardCache.fetch(project_id, :sheet_words, fn ->
        Sheets.sheet_word_counts(project_id)
      end)

    referenced_ids =
      DashboardCache.fetch(project_id, :sheet_refs, fn ->
        Sheets.referenced_block_ids_for_project(project_id)
      end)

    issues =
      DashboardCache.fetch(project_id, :sheet_issues, fn ->
        Sheets.detect_sheet_issues(project_id, referenced_ids)
      end)

    total_variable_count =
      DashboardCache.fetch(project_id, :sheet_total_vars, fn ->
        Sheets.list_project_variables(project_id) |> length()
      end)

    table_data =
      Enum.map(sheets, fn sheet ->
        sheet_stats = Map.get(stats, sheet.id, %{block_count: 0, variable_count: 0})

        %{
          id: sheet.id,
          name: sheet.name,
          block_count: sheet_stats.block_count,
          variable_count: sheet_stats.variable_count,
          word_count: Map.get(word_counts, sheet.id, 0),
          updated_at: sheet.updated_at
        }
      end)

    sorted_table = sort_table(table_data, sort_by, sort_dir, sheet_sort_columns())
    {page_rows, total_pages} = paginate(sorted_table, 1)

    %{
      dashboard_stats: %{
        sheet_count: length(sheets),
        block_count: table_data |> Enum.map(& &1.block_count) |> Enum.sum(),
        variable_count: total_variable_count,
        variables_in_use: MapSet.size(referenced_ids),
        word_count: table_data |> Enum.map(& &1.word_count) |> Enum.sum()
      },
      sorted_table: sorted_table,
      page_rows: page_rows,
      total_pages: total_pages,
      formatted_issues: format_sheet_issues(issues, workspace, project)
    }
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  # tree_panel_* events are handled by SidebarLive — they never reach here.

  def handle_event("sort_sheets", %{"column" => column}, socket) do
    {:noreply,
     handle_sort(socket, column, :all_sheet_table_data, :sheet_table_data, sheet_sort_columns())}
  end

  def handle_event("page_sheets", %{"page" => page}, socket) do
    {:noreply, handle_page(socket, page, :all_sheet_table_data, :sheet_table_data)}
  end

  # Tree mutation events (create_sheet, create_child_sheet, move_to_parent,
  # set_pending_delete, confirm_delete, delete) now live in SidebarLive —
  # they never reach this LV because the tree is rendered by SidebarLive
  # which is a separate nested LV.

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp reload_sheets(socket) do
    project_id = socket.assigns.project.id

    reload_dashboard(
      socket,
      :sheets,
      :all_sheet_table_data,
      :sheet_table_data,
      :sheet_issues,
      fn s ->
        s
        |> assign(:sheets_tree, prepare_tree(Sheets.list_sheets_tree(project_id)))
        |> assign(:sheets, Sheets.list_all_sheets(project_id))
      end
    )
  end

  # Transforms the Ecto tree into plain maps with avatar_url for Vue serialization
  defp prepare_tree(nodes) do
    Enum.map(nodes, fn node ->
      %{
        id: node.id,
        name: node.name,
        avatar_url: extract_avatar_url(node),
        children: prepare_tree(Map.get(node, :children, []))
      }
    end)
  end

  defp extract_avatar_url(%{avatars: avatars}) when is_list(avatars) do
    case Enum.find(avatars, & &1.is_default) || List.first(avatars) do
      %{asset: %{url: url}} when is_binary(url) -> url
      _ -> nil
    end
  end

  defp extract_avatar_url(_), do: nil

  defp sheet_sort_columns do
    %{
      "name" => &String.downcase(&1.name),
      "block_count" => & &1.block_count,
      "variable_count" => & &1.variable_count,
      "word_count" => & &1.word_count,
      "updated_at" => &(&1.updated_at || ~U[1970-01-01 00:00:00Z])
    }
  end

  defp format_sheet_issues(issues, workspace, project) do
    Enum.map(issues, fn issue ->
      {severity, message} =
        case issue.issue_type do
          :empty_sheet ->
            {:info, dgettext("sheets", "Sheet \"%{name}\" has no blocks", name: issue.sheet_name)}

          :unused_variable ->
            {:warning,
             dgettext("sheets", "Variable \"%{sheet}.%{variable}\" is never used",
               sheet: issue.sheet_shortcut,
               variable: issue.variable_name
             )}

          :missing_shortcut ->
            {:warning,
             dgettext("sheets", "Sheet \"%{name}\" has no shortcut", name: issue.sheet_name)}

          _ ->
            {:info, gettext("Issue detected")}
        end

      %{
        severity: to_string(severity),
        message: message,
        href: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{issue.sheet_id}"
      }
    end)
  end
end
