defmodule StoryarnWeb.SheetLive.Index do
  @moduledoc """
  V2 Sheets dashboard — same logic as SheetLive.Index, Vue + shadcn UI.
  """

  use StoryarnWeb, :live_view
  use StoryarnWeb.Live.Shared.DashboardHandlers

  import StoryarnWeb.Live.Shared.DashboardHelpers,
    only: [
      sort_table: 4,
      paginate: 2,
      handle_sort: 5,
      handle_page: 4,
      reload_dashboard: 6
    ]

  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Sheets
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

  @impl true
  def render(assigns) do
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
      sidebar_module={StoryarnWeb.SheetsSidebarLive}
      sidebar_session={
        %{
          "project_id" => @project.id,
          "workspace_slug" => @workspace.slug,
          "project_slug" => @project.slug,
          "sheet_id" => nil,
          "can_edit" => @can_edit,
          "active_tool" => "sheets",
          "dashboard_url" => ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets",
          "current_scope" => @current_scope,
          "locale" => @locale
        }
      }
    >
      <.vue
        v-component="live/sheet/dashboard/SheetDashboard"
        v-socket={@socket}
        v-inject="project-layout"
        id="sheet-dashboard"
        class="contents"
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
    </StoryarnWeb.Components.ProjectLayout.project>
    """
  end

  # ===========================================================================
  # Mount & Lifecycle
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    %{project: project} = socket.assigns
    sheets = Sheets.list_all_sheets(project.id)

    if connected?(socket) do
      Collaboration.subscribe_dashboard(project.id)

      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        StoryarnWeb.SheetsSidebarLive.shell_topic(project.id)
      )

      # Index is the sheets "dashboard" — clear any sheet highlight the
      # sticky sidebar may have carried over from a previous Show visit so
      # the dashboard link looks active instead.
      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        StoryarnWeb.SheetsSidebarLive.shell_topic(project.id),
        {:active_sheet, nil}
      )

      if sheets != [], do: send(self(), :load_dashboard_data)
    end

    {:ok,
     socket
     |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))
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

  # Shell-topic messages from SheetsSidebarLive:
  def handle_info({:EXIT, _pid, :normal}, socket), do: {:noreply, socket}

  def handle_info({:open_sheet, sheet_id}, socket) do
    path =
      ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{sheet_id}"

    {:noreply, push_navigate(socket, to: path)}
  end

  def handle_info({:active_sheet, _sheet_id}, socket), do: {:noreply, socket}
  def handle_info({:active_flow, _flow_id}, socket), do: {:noreply, socket}
  def handle_info({:active_scene, _scene_id}, socket), do: {:noreply, socket}
  def handle_info({:active_locale, _locale}, socket), do: {:noreply, socket}
  def handle_info({:tree_changed, :sheets}, socket), do: {:noreply, reload_sheets(socket)}
  def handle_info({:entities_deleted, _type, _ids}, socket), do: {:noreply, socket}
  def handle_info({:toolbar_event, _event, _params}, socket), do: {:noreply, socket}
  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}

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
        Sheets.list_dashboard_health_findings(project_id, referenced_ids)
      end)

    total_variable_count =
      DashboardCache.fetch(project_id, :sheet_total_vars, fn ->
        project_id |> Sheets.list_project_variables() |> length()
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
      formatted_issues: format_dashboard_health(issues, workspace, project)
    }
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  def handle_event("sort_sheets", %{"column" => column}, socket) do
    {:noreply, handle_sort(socket, column, :all_sheet_table_data, :sheet_table_data, sheet_sort_columns())}
  end

  def handle_event("page_sheets", %{"page" => page}, socket) do
    {:noreply, handle_page(socket, page, :all_sheet_table_data, :sheet_table_data)}
  end

  # Tree mutation events (create_sheet, create_child_sheet, move_to_parent,
  # set_pending_delete, confirm_delete, delete) now live in SheetsSidebarLive —
  # they never reach this LV because the tree is rendered by SheetsSidebarLive
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
      fn s -> assign(s, :sheets, Sheets.list_all_sheets(project_id)) end
    )
  end

  defp sheet_sort_columns do
    %{
      "name" => &String.downcase(&1.name),
      "block_count" => & &1.block_count,
      "variable_count" => & &1.variable_count,
      "word_count" => & &1.word_count,
      "updated_at" => &(&1.updated_at || ~U[1970-01-01 00:00:00Z])
    }
  end

  defp format_dashboard_health(findings, workspace, project) do
    Enum.map(findings, fn finding ->
      %{
        severity: Atom.to_string(finding.severity),
        code: Atom.to_string(finding.code),
        label: dashboard_health_label(finding),
        details: finding.details,
        href: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{finding.sheet_id}"
      }
    end)
  end

  defp dashboard_health_label(finding) do
    sheet_name = Map.get(finding.details, :sheet_name, "Sheet")

    case Map.get(finding.details, :variable_name) do
      variable_name when is_binary(variable_name) and variable_name != "" ->
        "#{sheet_name} · #{variable_name}"

      _other ->
        sheet_name
    end
  end
end
