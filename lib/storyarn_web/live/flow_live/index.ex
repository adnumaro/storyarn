defmodule StoryarnWeb.FlowLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Live.Shared.TreePanelHandlers
  import StoryarnWeb.Components.DashboardComponents

  use StoryarnWeb.Live.Shared.DashboardHandlers

  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache, as: DashboardCache
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
      on_dashboard={true}
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
              icon="text-cursor-input"
              label={dgettext("flows", "Words")}
              value={@dashboard_stats.word_count}
              tooltip={
                dgettext(
                  "flows",
                  "Counts dialogue text, menu text, stage directions, response text, and slug line descriptions"
                )
              }
            />
          </div>

          <%!-- Flow table --%>
          <.dashboard_section title={dgettext("flows", "All Flows")}>
            <.dashboard_table_wrapper>
              <.flow_table
                rows={@flow_table_data}
                sort_by={@sort_by}
                sort_dir={@sort_dir}
                workspace={@workspace}
                project={@project}
                can_edit={@can_edit}
              />
            </.dashboard_table_wrapper>
            <.pagination
              page={@page}
              total_pages={@total_pages}
              total={length(@all_flow_table_data)}
              event="page_flows"
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
    <table class="table table-sm w-full">
      <thead class="sticky top-0 bg-base-100 z-10">
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
              navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{row.id}"}
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
            <div phx-hook="TableRowMenu" id={"flow-menu-#{row.id}"}>
              <button type="button" data-role="trigger" class="btn btn-ghost btn-xs btn-square">
                <.icon name="more-horizontal" class="size-4" />
              </button>
              <template data-role="popover-template">
                <ul class="menu menu-sm">
                  <li :if={!row.is_main}>
                    <button
                      type="button"
                      data-event="set_main"
                      data-params={Jason.encode!(%{id: row.id})}
                    >
                      <.icon name="star" class="size-4" />
                      {dgettext("flows", "Set as main")}
                    </button>
                  </li>
                  <li>
                    <button
                      type="button"
                      class="text-error"
                      data-event="set_pending_delete"
                      data-params={Jason.encode!(%{id: row.id})}
                      data-modal-id="delete-flow-confirm"
                    >
                      <.icon name="trash-2" class="size-4" />
                      {dgettext("flows", "Delete")}
                    </button>
                  </li>
                </ul>
              </template>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
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
    project_id = socket.assigns.project.id
    flows = Flows.list_flows(project_id)

    # Run independent queries in parallel with caching
    tasks = [
      Task.async(fn ->
        {DashboardCache.fetch(project_id, :flow_stats, fn ->
           Flows.flow_stats_for_project(project_id)
         end),
         DashboardCache.fetch(project_id, :flow_words, fn ->
           Flows.flow_word_counts(project_id)
         end)}
      end),
      Task.async(fn ->
        DashboardCache.fetch(project_id, :flow_issues, fn ->
          Flows.detect_flow_issues(project_id)
        end)
      end)
    ]

    [{stats, word_counts}, issues] = Task.await_many(tasks, 15_000)

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

    sorted_table =
      sort_table(table_data, socket.assigns.sort_by, socket.assigns.sort_dir, flow_sort_columns())

    {page_rows, total_pages} = paginate(sorted_table, 1)

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
     |> assign(:all_flow_table_data, sorted_table)
     |> assign(:flow_table_data, page_rows)
     |> assign(:page, 1)
     |> assign(:total_pages, total_pages)
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

  # Ignore EXIT messages from linked processes (e.g. Task.async in dashboard loading)
  def handle_info({:EXIT, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  # Tree panel events (from FocusLayout)
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

  def handle_event("sort_flows", %{"column" => column}, socket) do
    {:noreply,
     handle_sort(socket, column, :all_flow_table_data, :flow_table_data, flow_sort_columns())}
  end

  def handle_event("page_flows", %{"page" => page}, socket) do
    {:noreply, handle_page(socket, page, :all_flow_table_data, :flow_table_data)}
  end

  def handle_event(event, %{"id" => id}, socket)
      when event in ~w(set_pending_delete set_pending_delete_flow) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event(event, _params, socket)
      when event in ~w(confirm_delete confirm_delete_flow) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event(event, %{"id" => flow_id}, socket)
      when event in ~w(delete delete_flow) do
    with_authorization(socket, :edit_content, fn socket ->
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

  def handle_event(event, %{"id" => flow_id}, socket)
      when event in ~w(set_main set_main_flow) do
    with_authorization(socket, :edit_content, fn socket ->
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
            {:error,
             dgettext("flows", "Flow \"%{name}\" has no entry node", name: issue.flow_name)}

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
