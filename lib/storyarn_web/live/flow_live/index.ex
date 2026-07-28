defmodule StoryarnWeb.FlowLive.Index do
  @moduledoc false

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
      parse_entity_id: 1,
      put_pending_delete_id: 2
    ]

  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Flows
  alias Storyarn.Shared.Severity
  alias StoryarnWeb.FlowLive.NodeTypeRegistry
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Live.Shared.DashboardHandlers
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

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
      active_tool={:flows}
      online_users={@online_users}
      sidebar_module={StoryarnWeb.FlowSidebarLive}
      sidebar_session={
        %{
          "project_id" => @project.id,
          "workspace_slug" => @workspace.slug,
          "project_slug" => @project.slug,
          "flow_id" => nil,
          "can_edit" => @can_edit,
          "active_tool" => "flows",
          "dashboard_url" => ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows",
          "current_scope" => @current_scope,
          "locale" => @locale
        }
      }
    >
      <.vue
        v-component="live/flow/dashboard/FlowDashboard"
        v-socket={@socket}
        v-inject="project-layout"
        id="flow-dashboard"
        class="contents"
        stats={@dashboard_stats}
        table-data={@flow_table_data}
        pagination={
          %{
            sortBy: @sort_by,
            sortDir: to_string(@sort_dir),
            page: @page,
            totalPages: @total_pages,
            total: @total_flows
          }
        }
        issues={@flow_issues}
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
    %{project: project, current_scope: current_scope} = socket.assigns

    # Leaving the flow editor — clear navigation history for this user/project
    Flows.nav_history_clear({current_scope.user.id, project.id})

    if connected?(socket) do
      Collaboration.subscribe_dashboard(project.id)
      DashboardCache.subscribe_resets()

      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        StoryarnWeb.FlowSidebarLive.shell_topic(project.id)
      )

      # Index is the flows "dashboard" — clear any flow highlight the sticky
      # sidebar may have carried over from a previous Show visit so the
      # dashboard link looks active instead.
      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        StoryarnWeb.FlowSidebarLive.shell_topic(project.id),
        {:active_flow, nil}
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
     |> assign(:all_flow_table_data, [])
     |> assign(:flow_table_data, [])
     |> assign(:all_flow_issues, [])
     |> assign(:flow_issues, [])
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
     |> assign(:total_flows, 0)
     |> assign(:pending_delete_id, nil)}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # ===========================================================================
  # Shell topic messages
  # ===========================================================================

  def handle_info({:open_flow, flow_id}, socket) do
    path =
      ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow_id}"

    {:noreply, push_navigate(socket, to: path)}
  end

  def handle_info({:active_flow, _flow_id}, socket), do: {:noreply, socket}
  def handle_info({:active_sheet, _sheet_id}, socket), do: {:noreply, socket}
  def handle_info({:active_scene, _scene_id}, socket), do: {:noreply, socket}
  def handle_info({:active_locale, _locale}, socket), do: {:noreply, socket}

  def handle_info({:tree_changed, :flows}, socket) do
    {:noreply, DashboardHandlers.schedule_reload(socket)}
  end

  def handle_info({:entities_deleted, _type, _ids}, socket), do: {:noreply, socket}
  def handle_info({:toolbar_event, _event, _params}, socket), do: {:noreply, socket}
  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}

  # ===========================================================================
  # Dashboard loading (async)
  # ===========================================================================

  def handle_info(:load_dashboard_data, socket) do
    {:noreply, socket |> start_dashboard_overview() |> start_dashboard_issues()}
  end

  def handle_info(:load_dashboard_overview, socket), do: {:noreply, start_dashboard_overview(socket)}
  def handle_info(:load_dashboard_issues, socket), do: {:noreply, start_dashboard_issues(socket)}

  def handle_info({StoryarnWeb.FlowLive.Form, {:saved, _flow}}, socket), do: {:noreply, socket}
  def handle_info({:EXIT, _pid, :normal}, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:load_dashboard_overview, {:ok, data}, socket) do
    sorted_table =
      sort_table(
        data.table_data,
        socket.assigns.sort_by,
        socket.assigns.sort_dir,
        flow_sort_columns()
      )

    page = pagination(sorted_table, socket.assigns.page)

    socket =
      socket
      |> assign(:dashboard_stats, data.dashboard_stats)
      |> assign(:overview_status, :ready)
      |> assign(:all_flow_table_data, sorted_table)
      |> assign(:flow_table_data, page.rows)
      |> assign(:page, page.page)
      |> assign(:total_pages, page.total_pages)
      |> assign(:total_flows, page.total)
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
    Logger.error("Flow dashboard overview load failed for project #{socket.assigns.project.id}: #{inspect(reason)}")

    socket =
      socket
      |> assign(:overview_status, fail_overview_load(socket.assigns.overview_status))
      |> DashboardHandlers.finish_failed_load(:overview)

    {:noreply, socket}
  end

  def handle_async(:load_dashboard_issues, {:exit, reason}, socket) do
    Logger.error("Flow dashboard issues load failed for project #{socket.assigns.project.id}: #{inspect(reason)}")

    socket =
      socket
      |> assign(:issues_status, fail_issues_load(socket.assigns.issues_status))
      |> DashboardHandlers.finish_failed_load(:issues)

    {:noreply, socket}
  end

  defp load_dashboard_overview_async(project_id, workspace, project) do
    flows = Flows.list_flows(project_id)

    stats =
      DashboardCache.fetch(project_id, :flow_stats, fn ->
        Flows.flow_stats_for_project(project_id)
      end)

    word_counts =
      DashboardCache.fetch(project_id, :flow_words, fn ->
        Flows.flow_word_counts(project_id)
      end)

    table_data =
      Enum.map(flows, fn flow ->
        flow_stats =
          Map.get(stats, flow.id, %{node_count: 0, dialogue_count: 0, condition_count: 0})

        %{
          id: flow.id,
          name: flow.name,
          is_main: flow.is_main,
          node_count: flow_stats.node_count,
          dialogue_count: flow_stats.dialogue_count,
          condition_count: flow_stats.condition_count,
          word_count: Map.get(word_counts, flow.id, 0),
          updated_at: flow.updated_at,
          href: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        }
      end)

    %{
      dashboard_stats: %{
        flow_count: length(flows),
        node_count: table_data |> Enum.map(& &1.node_count) |> Enum.sum(),
        dialogue_count: table_data |> Enum.map(& &1.dialogue_count) |> Enum.sum(),
        word_count: table_data |> Enum.map(& &1.word_count) |> Enum.sum()
      },
      table_data: table_data
    }
  end

  defp load_dashboard_issues_async(project_id, workspace, project) do
    project_id
    |> DashboardCache.fetch(:flow_issues, fn ->
      Flows.list_dashboard_health_findings(project_id)
    end)
    |> format_flow_issues(workspace, project)
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  def handle_event("sort_flows", %{"column" => column}, socket) do
    {:noreply, handle_sort(socket, column, :all_flow_table_data, :flow_table_data, flow_sort_columns())}
  end

  def handle_event("page_flows", %{"page" => page}, socket) do
    {:noreply, handle_page(socket, page, :all_flow_table_data, :flow_table_data)}
  end

  def handle_event("filter_flow_issues", %{"filter" => filter, "value" => value}, socket) do
    {:noreply, handle_issue_filter(socket, filter, value, issue_assign_opts())}
  end

  def handle_event("page_flow_issues", %{"page" => page}, socket) do
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

  # Dashboard table row actions (long form routes here; short form comes from
  # FlowDashboard.vue which uses `set_pending_delete` / `confirm_delete` / `set_main`)
  def handle_event(event, %{"id" => id}, socket) when event in ~w(set_pending_delete set_pending_delete_flow) do
    {:noreply, put_pending_delete_id(socket, id)}
  end

  def handle_event(event, _params, socket) when event in ~w(confirm_delete confirm_delete_flow) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event(event, %{"id" => flow_id}, socket) when event in ~w(delete delete_flow) do
    case parse_entity_id(flow_id) do
      flow_id when is_integer(flow_id) ->
        Authorize.with_authorization(
          socket,
          :edit_content,
          &delete_authorized_flow(&1, flow_id)
        )

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event(event, %{"id" => flow_id}, socket) when event in ~w(set_main set_main_flow) do
    case parse_entity_id(flow_id) do
      flow_id when is_integer(flow_id) ->
        Authorize.with_authorization(socket, :edit_content, &set_authorized_main_flow(&1, flow_id))

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event(event, _params, socket) do
    Logger.warning("[flows dashboard] ignored unknown event #{inspect(event)}")
    {:noreply, socket}
  end

  # Tree mutations (create_flow, create_child_flow, move_to_parent) now live in
  # FlowSidebarLive — they never reach this LV because the tree is rendered by
  # FlowSidebarLive which is a separate nested LV.

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp delete_authorized_flow(socket, flow_id) do
    with %{} = flow <- Flows.get_flow(socket.assigns.project.id, flow_id),
         {:ok, _} <- Flows.delete_flow(flow) do
      broadcast_tree_changed(socket)

      {:noreply,
       socket
       |> assign(:pending_delete_id, nil)
       |> put_flash(:info, dgettext("flows", "Flow moved to trash."))
       |> reload_flows()}
    else
      nil ->
        {:noreply,
         socket
         |> assign(:pending_delete_id, nil)
         |> put_flash(:error, dgettext("flows", "Flow not found."))}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:pending_delete_id, nil)
         |> put_flash(:error, dgettext("flows", "Could not delete flow."))}
    end
  end

  defp set_authorized_main_flow(socket, flow_id) do
    with %{} = flow <- Flows.get_flow(socket.assigns.project.id, flow_id),
         {:ok, _} <- Flows.set_main_flow(flow) do
      broadcast_tree_changed(socket)

      {:noreply,
       socket
       |> put_flash(:info, dgettext("flows", "Flow set as main."))
       |> reload_flows()}
    else
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Flow not found."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Could not set main flow."))}
    end
  end

  defp broadcast_tree_changed(socket) do
    Phoenix.PubSub.broadcast_from(
      Storyarn.PubSub,
      self(),
      StoryarnWeb.FlowSidebarLive.shell_topic(socket.assigns.project.id),
      {:tree_changed, :flows}
    )
  end

  defp reload_flows(socket) do
    DashboardHandlers.schedule_reload(socket)
  end

  defp issue_assign_opts do
    [
      all_key: :all_flow_issues,
      page_key: :flow_issues,
      filters_key: :issue_filters,
      options_key: :issue_filter_options,
      page_assign: :issue_page,
      total_pages_assign: :issue_total_pages,
      total_assign: :issue_total,
      unfiltered_total_assign: :unfiltered_issue_total
    ]
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

  defp flow_sort_columns do
    %{
      "name" => &String.downcase(&1.name),
      "node_count" => & &1.node_count,
      "dialogue_count" => & &1.dialogue_count,
      "condition_count" => & &1.condition_count,
      "word_count" => & &1.word_count,
      "updated_at" => &(&1.updated_at || ~U[1970-01-01 00:00:00Z])
    }
  end

  # One row per finding, with the CODE — never a rendered sentence. Vue resolves
  # it against `flows.health.findings.*`, the same catalog the editor popover
  # uses, exactly as `SheetDashboard.vue` does. That is what makes the dashboard
  # and the editor incapable of wording the same finding differently, and it is
  # why this needs no server-side copy at all.
  defp format_flow_issues(findings, workspace, project) do
    findings
    |> Enum.map(fn finding ->
      resource_label = Map.get(finding.details, :flow_name, dgettext("flows", "Flow"))

      %{
        severity: Atom.to_string(finding.severity),
        code: to_string(finding.code),
        label: issue_label(finding),
        details: finding.details,
        flow_id: finding.flow_id,
        entity_type: finding.entity_type,
        entity_id: finding.entity_id,
        resource_id: finding.flow_id,
        resource_label: resource_label,
        href: issue_href(finding, workspace, project)
      }
    end)
    # The list is rendered in the order it arrives, and now that every code reaches
    # it, errors would otherwise sit behind hundreds of info findings.
    |> Enum.sort_by(
      &{
        Severity.rank(&1.severity),
        &1.label,
        &1.code,
        &1.flow_id,
        &1.entity_type,
        &1.entity_id || 0,
        :erlang.term_to_binary(&1.details, [:deterministic])
      }
    )
    |> put_stable_issue_ids("flow", fn issue ->
      {issue.flow_id, issue.code, issue.entity_type, issue.entity_id, issue.details}
    end)
  end

  # A finding on a node opens the flow AND focuses that node, exactly as the
  # scenes dashboard does with `?highlight=<type>:<id>` — the row is otherwise a
  # link to a canvas the reader still has to search by hand.
  defp issue_href(finding, workspace, project) do
    base = ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{finding.flow_id}"

    if finding.entity_type != "flow" and not is_nil(finding.entity_id) do
      "#{base}?highlight=node:#{finding.entity_id}"
    else
      base
    end
  end

  # Location only, like sheets' "Ancient Tome · type": the flow, plus the node
  # when the finding belongs to one.
  defp issue_label(%{entity_type: "flow", details: details}) do
    Map.get(details, :flow_name, dgettext("flows", "Flow"))
  end

  defp issue_label(%{entity_type: type, entity_id: id, details: details}) do
    flow_name = Map.get(details, :flow_name, dgettext("flows", "Flow"))
    "#{flow_name} · #{NodeTypeRegistry.label(type)} ##{id}"
  end
end
