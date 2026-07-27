defmodule StoryarnWeb.SheetLive.Index do
  @moduledoc """
  V2 Sheets dashboard — same logic as SheetLive.Index, Vue + shadcn UI.
  """

  use StoryarnWeb, :live_view
  use StoryarnWeb.Live.Shared.DashboardHandlers

  import StoryarnWeb.Live.Shared.DashboardHelpers,
    only: [
      sort_table: 4,
      pagination: 2,
      handle_sort: 5,
      handle_page: 4,
      default_issue_filters: 0,
      default_issue_filter_options: 0,
      handle_issue_filter: 4,
      handle_issue_page: 3,
      put_issues: 3,
      put_stable_issue_ids: 3,
      fail_overview_load: 1,
      fail_issues_load: 1,
      put_pending_delete_id: 2
    ]

  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Shared.Severity
  alias Storyarn.Sheets
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Live.Shared.DashboardHandlers
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers
  alias StoryarnWeb.Live.TreeSidebarActions
  alias StoryarnWeb.SheetLive.Helpers.HealthHelpers

  require Logger

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
            total: @total_sheets
          }
        }
        issues={@sheet_issues}
        overview-status={to_string(@overview_status)}
        issues-status={to_string(@issues_status)}
        issue-pagination={
          %{
            page: @issue_page,
            totalPages: @issue_total_pages,
            total: @issue_total,
            unfilteredTotal: @unfiltered_issue_total
          }
        }
        issue-filters={@issue_filters}
        issue-filter-options={@issue_filter_options}
        can-edit={@can_edit}
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

    if connected?(socket) do
      Collaboration.subscribe_dashboard(project.id)
      DashboardCache.subscribe_resets()

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

      send(self(), :load_dashboard_data)
    end

    {:ok,
     socket
     |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))
     |> assign(:dashboard_stats, nil)
     |> assign(:overview_status, :loading)
     |> assign(:dashboard_overview_running?, false)
     |> assign(:dashboard_overview_reload_pending?, false)
     |> assign(:all_sheet_table_data, [])
     |> assign(:sheet_table_data, [])
     |> assign(:total_sheets, 0)
     |> assign(:all_sheet_issues, [])
     |> assign(:sheet_issues, [])
     |> assign(:issues_status, :loading)
     |> assign(:dashboard_issues_running?, false)
     |> assign(:dashboard_issues_reload_pending?, false)
     |> assign(:issue_filters, default_issue_filters())
     |> assign(:issue_filter_options, default_issue_filter_options())
     |> assign(:issue_page, 1)
     |> assign(:issue_total_pages, 1)
     |> assign(:issue_total, 0)
     |> assign(:unfiltered_issue_total, 0)
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

  def handle_info({:tree_changed, :sheets}, socket) do
    {:noreply, DashboardHandlers.schedule_reload(socket)}
  end

  def handle_info({:entities_deleted, _type, _ids}, socket), do: {:noreply, socket}
  def handle_info({:toolbar_event, _event, _params}, socket), do: {:noreply, socket}
  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}

  def handle_info(:load_dashboard_data, socket) do
    {:noreply, socket |> start_dashboard_overview() |> start_dashboard_issues()}
  end

  def handle_info(:load_dashboard_overview, socket), do: {:noreply, start_dashboard_overview(socket)}
  def handle_info(:load_dashboard_issues, socket), do: {:noreply, start_dashboard_issues(socket)}

  @impl true
  def handle_async(:load_dashboard_overview, {:ok, data}, socket) do
    sorted_table =
      sort_table(
        data.table_data,
        socket.assigns.sort_by,
        socket.assigns.sort_dir,
        sheet_sort_columns()
      )

    page = pagination(sorted_table, socket.assigns.page)

    socket =
      socket
      |> assign(:dashboard_stats, data.dashboard_stats)
      |> assign(:overview_status, :ready)
      |> assign(:all_sheet_table_data, sorted_table)
      |> assign(:sheet_table_data, page.rows)
      |> assign(:total_sheets, page.total)
      |> assign(:page, page.page)
      |> assign(:total_pages, page.total_pages)
      |> DashboardHandlers.finish_load(:overview, &start_dashboard_overview/1)

    {:noreply, socket}
  end

  def handle_async(:load_dashboard_issues, {:ok, issues}, socket) do
    socket =
      socket
      |> put_issues(issues, issue_assign_opts())
      |> assign(:issues_status, :ready)
      |> DashboardHandlers.finish_load(:issues, &start_dashboard_issues/1)

    {:noreply, socket}
  end

  def handle_async(:load_dashboard_overview, {:exit, reason}, socket) do
    Logger.error("Sheet dashboard overview load failed for project #{socket.assigns.project.id}: #{inspect(reason)}")

    socket =
      socket
      |> assign(:overview_status, fail_overview_load(socket.assigns.overview_status))
      |> DashboardHandlers.finish_failed_load(:overview)

    {:noreply, socket}
  end

  def handle_async(:load_dashboard_issues, {:exit, reason}, socket) do
    Logger.error("Sheet dashboard issues load failed for project #{socket.assigns.project.id}: #{inspect(reason)}")

    socket =
      socket
      |> assign(:issues_status, fail_issues_load(socket.assigns.issues_status))
      |> DashboardHandlers.finish_failed_load(:issues)

    {:noreply, socket}
  end

  defp load_dashboard_overview_async(project_id, workspace, project) do
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
          updated_at: sheet.updated_at,
          href: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        }
      end)

    %{
      dashboard_stats: %{
        sheet_count: length(sheets),
        block_count: table_data |> Enum.map(& &1.block_count) |> Enum.sum(),
        variable_count: total_variable_count,
        variables_in_use: MapSet.size(referenced_ids),
        word_count: table_data |> Enum.map(& &1.word_count) |> Enum.sum()
      },
      table_data: table_data
    }
  end

  defp load_dashboard_issues_async(project_id, workspace, project) do
    referenced_ids =
      DashboardCache.fetch(project_id, :sheet_refs, fn ->
        Sheets.referenced_block_ids_for_project(project_id)
      end)

    project_id
    |> DashboardCache.fetch(:sheet_issues, fn ->
      Sheets.list_dashboard_health_findings(project_id, referenced_ids)
    end)
    |> format_dashboard_health(workspace, project)
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

  def handle_event("filter_sheet_issues", %{"filter" => filter, "value" => value}, socket) do
    {:noreply, handle_issue_filter(socket, filter, value, issue_assign_opts())}
  end

  def handle_event("page_sheet_issues", %{"page" => page}, socket) do
    {:noreply, handle_issue_page(socket, page, issue_assign_opts())}
  end

  def handle_event("retry_dashboard_overview", _params, %{assigns: %{overview_status: status}} = socket)
      when status in [:error, :stale] do
    {:noreply, DashboardHandlers.retry_load(socket, :overview, &start_dashboard_overview/1)}
  end

  def handle_event("retry_dashboard_overview", _params, socket), do: {:noreply, socket}

  def handle_event("retry_dashboard_issues", _params, %{assigns: %{issues_status: status}} = socket)
      when status in [:error, :stale] do
    {:noreply, DashboardHandlers.retry_load(socket, :issues, &start_dashboard_issues/1)}
  end

  def handle_event("retry_dashboard_issues", _params, socket), do: {:noreply, socket}

  def handle_event("set_pending_delete_sheet", %{"id" => id}, socket) do
    {:noreply, put_pending_delete_id(socket, id)}
  end

  def handle_event("confirm_delete_sheet", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, &confirm_delete_sheet/1)
  end

  def handle_event(event, _params, socket) do
    Logger.warning("[sheets dashboard] ignored unknown event #{inspect(event)}")
    {:noreply, socket}
  end

  # Other tree mutation events (create_sheet, create_child_sheet and
  # move_to_parent) live in the separately rendered SheetsSidebarLive.

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp confirm_delete_sheet(socket) do
    TreeSidebarActions.confirm_delete(socket, %{
      get_entity: &Sheets.get_sheet/2,
      delete_entity: &Sheets.delete_sheet_subtree/1,
      broadcast_deleted: &broadcast_entities_deleted/2,
      refresh_tree: &refresh_dashboard_and_tree/1,
      deleted_message: dgettext("sheets", "Sheet moved to trash."),
      delete_error_message: dgettext("sheets", "Could not delete sheet.")
    })
  end

  defp broadcast_entities_deleted(socket, ids) do
    Phoenix.PubSub.broadcast_from(
      Storyarn.PubSub,
      self(),
      StoryarnWeb.SheetsSidebarLive.shell_topic(socket.assigns.project.id),
      {:entities_deleted, :sheet, ids}
    )
  end

  defp refresh_dashboard_and_tree(socket) do
    Phoenix.PubSub.broadcast_from(
      Storyarn.PubSub,
      self(),
      StoryarnWeb.SheetsSidebarLive.shell_topic(socket.assigns.project.id),
      {:tree_changed, :sheets}
    )

    DashboardHandlers.schedule_reload(socket)
  end

  defp start_dashboard_overview(socket) do
    %{project: project, workspace: workspace, locale: locale} = socket.assigns

    DashboardHandlers.start_load(socket, :overview, fn ->
      Gettext.put_locale(Storyarn.Gettext, locale)
      load_dashboard_overview_async(project.id, workspace, project)
    end)
  end

  defp start_dashboard_issues(socket) do
    %{project: project, workspace: workspace, locale: locale} = socket.assigns

    DashboardHandlers.start_load(socket, :issues, fn ->
      Gettext.put_locale(Storyarn.Gettext, locale)
      load_dashboard_issues_async(project.id, workspace, project)
    end)
  end

  defp issue_assign_opts do
    [
      all_key: :all_sheet_issues,
      page_key: :sheet_issues,
      filters_key: :issue_filters,
      options_key: :issue_filter_options,
      page_assign: :issue_page,
      total_pages_assign: :issue_total_pages,
      total_assign: :issue_total,
      unfiltered_total_assign: :unfiltered_issue_total
    ]
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
    findings
    |> Enum.map(fn finding ->
      resource_label = sheet_label(finding)

      %{
        severity: Atom.to_string(finding.severity),
        code: Atom.to_string(finding.code),
        label: dashboard_health_label(finding),
        details: finding.details,
        sheet_id: finding.sheet_id,
        block_id: finding.block_id,
        row_id: finding.row_id,
        column_id: finding.column_id,
        resource_id: finding.sheet_id,
        resource_label: resource_label,
        href: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{finding.sheet_id}"
      }
    end)
    # The list is rendered in the order it arrives, and now that every code reaches
    # it, errors would otherwise sit behind hundreds of info findings.
    |> Enum.sort_by(
      &{
        Severity.rank(&1.severity),
        &1.label,
        &1.code,
        &1.sheet_id,
        &1.block_id || 0,
        &1.row_id || 0,
        &1.column_id || 0,
        :erlang.term_to_binary(&1.details, [:deterministic])
      }
    )
    |> put_stable_issue_ids("sheet", fn issue ->
      {issue.sheet_id, issue.code, issue.block_id, issue.row_id, issue.column_id, issue.details}
    end)
  end

  # Location only — never a rendered sentence. The code carries the meaning and Vue
  # resolves it from `sheets.health.findings.*`, the same catalog the editor popover
  # uses, so the two surfaces cannot word a finding differently.
  defp dashboard_health_label(finding) do
    Enum.join([sheet_label(finding) | block_labels(finding)], " · ")
  end

  defp sheet_label(finding) do
    Map.get(finding.details, :sheet_name) || dgettext("sheets", "Sheet")
  end

  defp block_labels(%{block_id: nil}), do: []

  # The identifiers come from `HealthHelpers`, which the editor popover uses for
  # the same blocks: two spellings of "the block with no label" is two names for
  # one thing, and `String.capitalize/1` over a DB enum cannot be translated at
  # all — Spanish read "Multi select" here and "Selección múltiple" one click away.
  defp block_labels(finding) do
    block =
      Map.get(finding.details, :block_label) ||
        HealthHelpers.block_identifier(finding.block_type, finding.block_id)

    row = Map.get(finding.details, :row_label) || axis_identifier(finding.row_id, &HealthHelpers.row_identifier/1)

    column =
      Map.get(finding.details, :column_label) || axis_identifier(finding.column_id, &HealthHelpers.column_identifier/1)

    Enum.reject([block, row, column], &is_nil/1)
  end

  defp axis_identifier(nil, _identifier), do: nil
  defp axis_identifier(id, identifier), do: identifier.(id)
end
