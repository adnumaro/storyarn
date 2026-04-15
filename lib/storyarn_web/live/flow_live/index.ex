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

  import StoryarnWeb.Live.Shared.TreePanelHandlers

  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Sheets
  alias StoryarnWeb.Helpers.Authorize

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:flows}
      on_dashboard={true}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      show_pin={false}
      can_edit={@can_edit}
      tree_props={
        %{
          flowsTree: @flows_tree,
          canEdit: @can_edit,
          workspaceSlug: @workspace.slug,
          projectSlug: @project.slug,
          selectedFlowId: nil
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
    </Layouts.app>
    """
  end

  # ===========================================================================
  # Mount & Lifecycle
  # ===========================================================================

  @impl true
  def mount(%{"workspace_slug" => workspace_slug, "project_slug" => project_slug}, _session, socket) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        flows = Flows.list_flows(project.id)
        flows_tree = Flows.list_flows_tree(project.id)
        can_edit = Projects.can?(membership.role, :edit_content)

        # Leaving the flow editor — clear navigation history for this user/project
        user_id = socket.assigns.current_scope.user.id
        Flows.nav_history_clear({user_id, project.id})

        socket =
          socket
          |> assign(focus_layout_defaults())
          |> assign(:tree_panel_open, true)
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:flows, flows)
          |> assign(:flows_tree, flows_tree)
          |> assign(:dashboard_stats, nil)
          |> assign(:all_flow_table_data, [])
          |> assign(:flow_table_data, [])
          |> assign(:flow_issues, [])
          |> assign(:sort_by, "name")
          |> assign(:sort_dir, :asc)
          |> assign(:page, 1)
          |> assign(:total_pages, 1)
          |> assign(:pending_delete_id, nil)

        if connected?(socket), do: Collaboration.subscribe_dashboard(project.id)
        if connected?(socket) and flows != [], do: send(self(), :load_dashboard_data)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("flows", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  # ===========================================================================
  # Dashboard loading
  # ===========================================================================

  @impl true
  def handle_info(:load_dashboard_data, socket) do
    %{project: project, workspace: workspace, sort_by: sort_by, sort_dir: sort_dir} =
      socket.assigns

    {:noreply,
     start_async(socket, :load_dashboard_data, fn ->
       load_dashboard_data_async(project.id, workspace, project, sort_by, sort_dir)
     end)}
  end

  @impl true
  def handle_info({StoryarnWeb.FlowLive.Form, {:saved, _flow}}, socket) do
    {:noreply, socket}
  end

  @impl true
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

  def handle_async(:load_dashboard_data, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

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
  # Tree panel events (from AppLayout)
  def handle_event("tree_panel_" <> _ = event, params, socket), do: handle_tree_panel_event(event, params, socket)

  def handle_event("sort_flows", %{"column" => column}, socket) do
    {:noreply, handle_sort(socket, column, :all_flow_table_data, :flow_table_data, flow_sort_columns())}
  end

  def handle_event("page_flows", %{"page" => page}, socket) do
    {:noreply, handle_page(socket, page, :all_flow_table_data, :flow_table_data)}
  end

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

  def handle_event("create_flow", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Flows.create_flow(socket.assigns.project, %{name: dgettext("flows", "Untitled")}) do
        {:ok, new_flow} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{new_flow.id}"
           )}

        {:error, :limit_reached, _details} ->
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not create flow."))}
      end
    end)
  end

  def handle_event("create_child_flow", %{"parent-id" => parent_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      attrs = %{name: dgettext("flows", "Untitled"), parent_id: parent_id}

      case Flows.create_flow(socket.assigns.project, attrs) do
        {:ok, new_flow} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{new_flow.id}"
           )}

        {:error, :limit_reached, _details} ->
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not create flow."))}
      end
    end)
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      flow = Flows.get_flow!(socket.assigns.project.id, item_id)
      new_parent_id = MapUtils.parse_int(new_parent_id)
      position = MapUtils.parse_int(position) || 0

      case Flows.move_flow_to_position(flow, new_parent_id, position) do
        {:ok, _} ->
          {:noreply, reload_flows(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not move flow."))}
      end
    end)
  end

  def handle_event("create_sheet", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Sheets.create_sheet(socket.assigns.project, %{name: dgettext("sheets", "Untitled")}) do
        {:ok, new_sheet} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{new_sheet.id}"
           )}

        {:error, :limit_reached, _details} ->
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create sheet."))}
      end
    end)
  end

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp reload_flows(socket) do
    project_id = socket.assigns.project.id

    reload_dashboard(socket, :flows, :all_flow_table_data, :flow_table_data, :flow_issues, fn s ->
      s
      |> assign(:flows, Flows.list_flows(project_id))
      |> assign(:flows_tree, Flows.list_flows_tree(project_id))
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
