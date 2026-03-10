defmodule StoryarnWeb.FlowLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Live.Shared.TreePanelHandlers
  import StoryarnWeb.Components.DashboardComponents

  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Sheets
  alias StoryarnWeb.Components.Sidebar.FlowTree

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:flows}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      show_pin={false}
      can_edit={@can_edit}
    >
      <:tree_content>
        <FlowTree.flows_section
          flows_tree={@flows_tree}
          workspace={@workspace}
          project={@project}
          can_edit={@can_edit}
        />
      </:tree_content>
      <FlowTree.delete_modal :if={@can_edit} />
      <div class="max-w-5xl mx-auto px-4 sm:px-6 py-8 space-y-6">
        <.header>
          {dgettext("flows", "Flows")}
          <:subtitle>
            {dgettext("flows", "Create visual narrative flows and dialogue trees")}
          </:subtitle>
        </.header>

        <.empty_state :if={@flows == []} icon="git-branch">
          {dgettext("flows", "No flows yet. Create your first flow to get started.")}
        </.empty_state>

        <div :if={@flows != [] and is_nil(@dashboard_stats)} class="flex justify-center py-12">
          <span class="loading loading-spinner loading-md text-base-content/40"></span>
        </div>

        <div :if={@dashboard_stats} class="space-y-6">
          <%!-- Stats row --%>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <.stat_card
              icon="git-branch"
              label={dgettext("flows", "Flows")}
              value={@dashboard_stats.flow_count}
            />
            <.stat_card
              icon="box"
              label={dgettext("flows", "Nodes")}
              value={@dashboard_stats.node_count}
            />
            <.stat_card
              icon="message-square"
              label={dgettext("flows", "Dialogue")}
              value={@dashboard_stats.dialogue_count}
            />
            <.stat_card
              icon="type"
              label={dgettext("flows", "Words")}
              value={@dashboard_stats.word_count}
            />
          </div>

          <%!-- Flow table --%>
          <.dashboard_section title={dgettext("flows", "All Flows")}>
            <.flow_table
              rows={@flow_table_data}
              sort_by={@sort_by}
              sort_dir={@sort_dir}
              workspace={@workspace}
              project={@project}
              can_edit={@can_edit}
            />
          </.dashboard_section>

          <%!-- Issues --%>
          <.dashboard_section :if={@flow_issues != []} title={dgettext("flows", "Issues")}>
            <.issue_list issues={@flow_issues} />
          </.dashboard_section>
        </div>

        <.modal
          :if={@live_action == :new and @can_edit}
          id="new-flow-modal"
          show
          on_cancel={JS.patch(~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows")}
        >
          <.live_component
            module={StoryarnWeb.FlowLive.Form}
            id="new-flow-form"
            project={@project}
            title={dgettext("flows", "New Flow")}
            navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows"}
          />
        </.modal>

        <.confirm_modal
          :if={@can_edit}
          id="delete-flow-confirm"
          title={dgettext("flows", "Delete flow?")}
          message={dgettext("flows", "Are you sure you want to delete this flow?")}
          confirm_text={dgettext("flows", "Delete")}
          confirm_variant="error"
          icon="alert-triangle"
          on_confirm={JS.push("confirm_delete")}
        />
      </div>
    </Layouts.focus>
    """
  end

  # ===========================================================================
  # Flow Table
  # ===========================================================================

  attr :rows, :list, required: true
  attr :sort_by, :string, required: true
  attr :sort_dir, :atom, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, default: false

  defp flow_table(assigns) do
    ~H"""
    <div class="overflow-x-auto -mx-5">
      <table class="table table-sm w-full">
        <thead>
          <tr class="text-xs text-base-content/50 uppercase">
            <th class="font-medium">
              <button
                type="button"
                phx-click="sort_flows"
                phx-value-column="name"
                class="flex items-center gap-1 hover:text-base-content"
              >
                {dgettext("flows", "Name")}
                <.sort_indicator column="name" sort_by={@sort_by} sort_dir={@sort_dir} />
              </button>
            </th>
            <th class="font-medium text-right">
              <button
                type="button"
                phx-click="sort_flows"
                phx-value-column="node_count"
                class="flex items-center gap-1 ml-auto hover:text-base-content"
              >
                {dgettext("flows", "Nodes")}
                <.sort_indicator column="node_count" sort_by={@sort_by} sort_dir={@sort_dir} />
              </button>
            </th>
            <th class="font-medium text-right hidden sm:table-cell">
              <button
                type="button"
                phx-click="sort_flows"
                phx-value-column="dialogue_count"
                class="flex items-center gap-1 ml-auto hover:text-base-content"
              >
                {dgettext("flows", "Dialogue")}
                <.sort_indicator column="dialogue_count" sort_by={@sort_by} sort_dir={@sort_dir} />
              </button>
            </th>
            <th class="font-medium text-right hidden sm:table-cell">
              <button
                type="button"
                phx-click="sort_flows"
                phx-value-column="condition_count"
                class="flex items-center gap-1 ml-auto hover:text-base-content"
              >
                {dgettext("flows", "Conditions")}
                <.sort_indicator column="condition_count" sort_by={@sort_by} sort_dir={@sort_dir} />
              </button>
            </th>
            <th class="font-medium text-right hidden md:table-cell">
              <button
                type="button"
                phx-click="sort_flows"
                phx-value-column="word_count"
                class="flex items-center gap-1 ml-auto hover:text-base-content"
              >
                {dgettext("flows", "Words")}
                <.sort_indicator column="word_count" sort_by={@sort_by} sort_dir={@sort_dir} />
              </button>
            </th>
            <th class="font-medium text-right hidden md:table-cell">
              <button
                type="button"
                phx-click="sort_flows"
                phx-value-column="updated_at"
                class="flex items-center gap-1 ml-auto hover:text-base-content"
              >
                {dgettext("flows", "Modified")}
                <.sort_indicator column="updated_at" sort_by={@sort_by} sort_dir={@sort_dir} />
              </button>
            </th>
            <th :if={@can_edit} class="w-10"></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} class="hover:bg-base-200/50">
            <td>
              <.link
                navigate={
                  ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{row.id}"
                }
                class="flex items-center gap-2 font-medium hover:underline"
              >
                {row.name}
                <span
                  :if={row.is_main}
                  class="badge badge-primary badge-xs"
                  title={dgettext("flows", "Main flow")}
                >
                  {dgettext("flows", "Main")}
                </span>
              </.link>
            </td>
            <td class="text-right tabular-nums">{row.node_count}</td>
            <td class="text-right tabular-nums hidden sm:table-cell">{row.dialogue_count}</td>
            <td class="text-right tabular-nums hidden sm:table-cell">{row.condition_count}</td>
            <td class="text-right tabular-nums hidden md:table-cell">{row.word_count}</td>
            <td class="text-right text-base-content/50 text-xs hidden md:table-cell">
              {format_relative_time(row.updated_at)}
            </td>
            <td :if={@can_edit} class="text-right">
              <div class="dropdown dropdown-end">
                <button type="button" tabindex="0" class="btn btn-ghost btn-xs btn-square">
                  <.icon name="more-horizontal" class="size-4" />
                </button>
                <ul
                  tabindex="0"
                  class="dropdown-content menu menu-sm bg-base-100 rounded-box shadow-lg border border-base-300 w-40 z-50"
                >
                  <li :if={!row.is_main}>
                    <button type="button" phx-click="set_main" phx-value-id={row.id}>
                      <.icon name="star" class="size-4" />
                      {dgettext("flows", "Set as main")}
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      class="text-error"
                      phx-click={
                        JS.push("set_pending_delete", value: %{id: row.id})
                        |> show_modal("delete-flow-confirm")
                      }
                    >
                      <.icon name="trash-2" class="size-4" />
                      {dgettext("flows", "Delete")}
                    </button>
                  </li>
                </ul>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :column, :string, required: true
  attr :sort_by, :string, required: true
  attr :sort_dir, :atom, required: true

  defp sort_indicator(assigns) do
    ~H"""
    <.icon
      :if={@sort_by == @column}
      name={if @sort_dir == :asc, do: "chevron-up", else: "chevron-down"}
      class="size-3"
    />
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
          |> assign(:flow_table_data, [])
          |> assign(:flow_issues, [])
          |> assign(:sort_by, "name")
          |> assign(:sort_dir, :asc)

        if connected?(socket) and flows != [] do
          send(self(), :load_dashboard_data)
        end

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
    project_id = socket.assigns.project.id
    flows = socket.assigns.flows

    stats = Flows.flow_stats_for_project(project_id)
    word_counts = Flows.flow_word_counts(project_id)
    issues = Flows.detect_flow_issues(project_id)

    # Build table data by merging flow list with stats
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

    sorted_table = sort_flow_table(table_data, socket.assigns.sort_by, socket.assigns.sort_dir)

    # Aggregate stats
    dashboard_stats = %{
      flow_count: length(flows),
      node_count: table_data |> Enum.map(& &1.node_count) |> Enum.sum(),
      dialogue_count: table_data |> Enum.map(& &1.dialogue_count) |> Enum.sum(),
      word_count: table_data |> Enum.map(& &1.word_count) |> Enum.sum()
    }

    # Format issues with hrefs
    formatted_issues =
      format_flow_issues(issues, socket.assigns.workspace, socket.assigns.project)

    {:noreply,
     socket
     |> assign(:dashboard_stats, dashboard_stats)
     |> assign(:flow_table_data, sorted_table)
     |> assign(:flow_issues, formatted_issues)}
  end

  @impl true
  def handle_info({StoryarnWeb.FlowLive.Form, {:saved, flow}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, dgettext("flows", "Flow created successfully."))
     |> push_navigate(
       to:
         ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow.id}"
     )}
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  # Tree panel events (from FocusLayout)
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

  def handle_event("sort_flows", %{"column" => column}, socket) do
    {sort_by, sort_dir} = toggle_sort(column, socket.assigns.sort_by, socket.assigns.sort_dir)
    sorted = sort_flow_table(socket.assigns.flow_table_data, sort_by, sort_dir)

    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:sort_dir, sort_dir)
     |> assign(:flow_table_data, sorted)}
  end

  def handle_event("set_pending_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event("set_pending_delete_flow", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event("confirm_delete", _params, socket) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("confirm_delete_flow", _params, socket) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => flow_id}, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      flow = Flows.get_flow!(socket.assigns.project.id, flow_id)

      case Flows.delete_flow(flow) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("flows", "Flow moved to trash."))
           |> reload_flows()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not delete flow."))}
      end
    end)
  end

  def handle_event("delete_flow", %{"id" => flow_id}, socket) do
    handle_event("delete", %{"id" => flow_id}, socket)
  end

  def handle_event("set_main", %{"id" => flow_id}, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      flow = Flows.get_flow!(socket.assigns.project.id, flow_id)

      case Flows.set_main_flow(flow) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("flows", "Flow set as main."))
           |> reload_flows()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not set main flow."))}
      end
    end)
  end

  def handle_event("set_main_flow", %{"id" => flow_id}, socket) do
    handle_event("set_main", %{"id" => flow_id}, socket)
  end

  def handle_event("create_flow", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
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
    with_authorization(socket, :edit_content, fn socket ->
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
    with_authorization(socket, :edit_content, fn socket ->
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
    with_authorization(socket, :edit_content, fn socket ->
      case Sheets.create_sheet(socket.assigns.project, %{name: dgettext("flows", "Untitled")}) do
        {:ok, new_sheet} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{new_sheet.id}"
           )}

        {:error, :limit_reached, _details} ->
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not create sheet."))}
      end
    end)
  end

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp reload_flows(socket) do
    project_id = socket.assigns.project.id

    socket
    |> assign(:flows, Flows.list_flows(project_id))
    |> assign(:flows_tree, Flows.list_flows_tree(project_id))
    |> assign(:dashboard_stats, nil)
    |> assign(:flow_table_data, [])
    |> assign(:flow_issues, [])
    |> then(fn socket ->
      if socket.assigns.flows != [] do
        send(self(), :load_dashboard_data)
      end

      socket
    end)
  end

  defp sort_flow_table(data, sort_by, sort_dir) do
    sorter =
      case sort_by do
        "name" -> &String.downcase(&1.name)
        "node_count" -> & &1.node_count
        "dialogue_count" -> & &1.dialogue_count
        "condition_count" -> & &1.condition_count
        "word_count" -> & &1.word_count
        "updated_at" -> & &1.updated_at
        _ -> &String.downcase(&1.name)
      end

    Enum.sort_by(data, sorter, sort_dir)
  end

  defp toggle_sort(column, current_by, current_dir) do
    if column == current_by do
      {column, if(current_dir == :asc, do: :desc, else: :asc)}
    else
      {column, :asc}
    end
  end

  defp format_flow_issues(issues, workspace, project) do
    Enum.map(issues, fn issue ->
      {severity, message} =
        case issue.issue_type do
          :no_entry ->
            {:error,
             dgettext("flows", "Flow \"%{name}\" has no entry node", name: issue.flow_name)}

          :disconnected_nodes ->
            {:warning,
             dgettext("flows", "Flow \"%{name}\" has %{count} disconnected node(s)",
               name: issue.flow_name,
               count: issue.count
             )}
        end

      %{
        severity: severity,
        message: message,
        href: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{issue.flow_id}"
      }
    end)
  end

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> dgettext("flows", "just now")
      diff < 3600 -> dgettext("flows", "%{count}m ago", count: div(diff, 60))
      diff < 86_400 -> dgettext("flows", "%{count}h ago", count: div(diff, 3600))
      diff < 604_800 -> dgettext("flows", "%{count}d ago", count: div(diff, 86_400))
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end
