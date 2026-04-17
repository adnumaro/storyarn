defmodule StoryarnWeb.FlowLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Live.Shared.DashboardHandlers

  import StoryarnWeb.Components.DashboardComponents,
    only: [
      sort_table: 4,
      paginate: 2,
      handle_sort: 5,
      handle_page: 4,
      reload_dashboard: 6
    ]

  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Flows
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

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
      active_tool={:flows}
      is_super_admin={@is_super_admin}
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
        v-component="modules/flows/FlowDashboard"
        v-socket={@socket}
        id="flow-dashboard"
        stats={@dashboard_stats}
        table-data={@flow_table_data}
        pagination={
          %{
            sortBy: @sort_by,
            sortDir: to_string(@sort_dir),
            page: @page,
            totalPages: @total_pages,
            total: length(@all_flow_table_data)
          }
        }
        issues={@flow_issues}
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
    %{project: project, current_scope: current_scope} = socket.assigns
    flows = Flows.list_flows(project.id)

    # Leaving the flow editor — clear navigation history for this user/project
    Flows.nav_history_clear({current_scope.user.id, project.id})

    if connected?(socket) do
      Collaboration.subscribe_dashboard(project.id)

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

      if flows != [], do: send(self(), :load_dashboard_data)
    end

    {:ok,
     socket
     |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))
     |> assign(:flows, flows)
     |> assign(:dashboard_stats, nil)
     |> assign(:all_flow_table_data, [])
     |> assign(:flow_table_data, [])
     |> assign(:flow_issues, [])
     |> assign(:sort_by, "name")
     |> assign(:sort_dir, :asc)
     |> assign(:page, 1)
     |> assign(:total_pages, 1)
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
  def handle_info({:tree_changed, :flows}, socket), do: {:noreply, reload_flows(socket)}
  def handle_info({:toolbar_event, _event, _params}, socket), do: {:noreply, socket}
  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}

  # ===========================================================================
  # Dashboard loading (async)
  # ===========================================================================

  def handle_info(:load_dashboard_data, socket) do
    %{project: project, workspace: workspace, sort_by: sort_by, sort_dir: sort_dir} =
      socket.assigns

    {:noreply,
     start_async(socket, :load_dashboard_data, fn ->
       load_dashboard_data_async(project.id, workspace, project, sort_by, sort_dir)
     end)}
  end

  def handle_info({StoryarnWeb.FlowLive.Form, {:saved, _flow}}, socket), do: {:noreply, socket}
  def handle_info({:EXIT, _pid, :normal}, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:load_dashboard_data, {:ok, data}, socket) do
    {:noreply,
     socket
     |> assign(:dashboard_stats, data.dashboard_stats)
     |> assign(:all_flow_table_data, data.sorted_table)
     |> assign(:flow_table_data, data.page_rows)
     |> assign(:page, 1)
     |> assign(:total_pages, data.total_pages)
     |> assign(:flow_issues, data.formatted_issues)}
  end

  def handle_async(:load_dashboard_data, {:exit, _reason}, socket), do: {:noreply, socket}

  defp load_dashboard_data_async(project_id, workspace, project, sort_by, sort_dir) do
    flows = Flows.list_flows(project_id)

    stats =
      DashboardCache.fetch(project_id, :flow_stats, fn ->
        Flows.flow_stats_for_project(project_id)
      end)

    word_counts =
      DashboardCache.fetch(project_id, :flow_words, fn ->
        Flows.flow_word_counts(project_id)
      end)

    issues =
      DashboardCache.fetch(project_id, :flow_issues, fn ->
        Flows.detect_flow_issues(project_id)
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
          updated_at: flow.updated_at
        }
      end)

    sorted_table = sort_table(table_data, sort_by, sort_dir, flow_sort_columns())
    {page_rows, total_pages} = paginate(sorted_table, 1)

    %{
      dashboard_stats: %{
        flow_count: length(flows),
        node_count: table_data |> Enum.map(& &1.node_count) |> Enum.sum(),
        dialogue_count: table_data |> Enum.map(& &1.dialogue_count) |> Enum.sum(),
        word_count: table_data |> Enum.map(& &1.word_count) |> Enum.sum()
      },
      sorted_table: sorted_table,
      page_rows: page_rows,
      total_pages: total_pages,
      formatted_issues: format_flow_issues(issues, workspace, project)
    }
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: ProjectChromeHelpers.forward_tree_panel(socket, event, params)

  def handle_event("sort_flows", %{"column" => column}, socket) do
    {:noreply, handle_sort(socket, column, :all_flow_table_data, :flow_table_data, flow_sort_columns())}
  end

  def handle_event("page_flows", %{"page" => page}, socket) do
    {:noreply, handle_page(socket, page, :all_flow_table_data, :flow_table_data)}
  end

  # Dashboard table row actions (long form routes here; short form comes from
  # FlowDashboard.vue which uses `set_pending_delete` / `confirm_delete` / `set_main`)
  def handle_event(event, %{"id" => id}, socket) when event in ~w(set_pending_delete set_pending_delete_flow) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event(event, _params, socket) when event in ~w(confirm_delete confirm_delete_flow) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event(event, %{"id" => flow_id}, socket) when event in ~w(delete delete_flow) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with %{} = flow <- Flows.get_flow(socket.assigns.project.id, flow_id),
           {:ok, _} <- Flows.delete_flow(flow) do
        broadcast_tree_changed(socket)

        {:noreply,
         socket
         |> put_flash(:info, dgettext("flows", "Flow moved to trash."))
         |> reload_flows()}
      else
        nil ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Flow not found."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not delete flow."))}
      end
    end)
  end

  def handle_event(event, %{"id" => flow_id}, socket) when event in ~w(set_main set_main_flow) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
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
    end)
  end

  # Tree mutations (create_flow, create_child_flow, move_to_parent) now live in
  # FlowSidebarLive — they never reach this LV because the tree is rendered by
  # FlowSidebarLive which is a separate nested LV.

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp broadcast_tree_changed(socket) do
    Phoenix.PubSub.broadcast_from(
      Storyarn.PubSub,
      self(),
      StoryarnWeb.FlowSidebarLive.shell_topic(socket.assigns.project.id),
      {:tree_changed, :flows}
    )
  end

  defp reload_flows(socket) do
    project_id = socket.assigns.project.id

    reload_dashboard(socket, :flows, :all_flow_table_data, :flow_table_data, :flow_issues, fn s ->
      assign(s, :flows, Flows.list_flows(project_id))
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

  defp format_flow_issues(issues, workspace, project) do
    Enum.map(issues, fn issue ->
      {severity, message} =
        case issue.issue_type do
          :no_entry ->
            {:error, dgettext("flows", "Flow \"%{name}\" has no entry node", name: issue.flow_name)}

          :disconnected_nodes ->
            {:warning,
             dgettext("flows", "Flow \"%{name}\" has %{count} disconnected node(s)",
               name: issue.flow_name,
               count: issue.count
             )}

          _ ->
            {:info, gettext("Issue detected")}
        end

      %{
        severity: severity,
        message: message,
        href: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{issue.flow_id}"
      }
    end)
  end
end
