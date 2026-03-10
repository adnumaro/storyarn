defmodule StoryarnWeb.SheetLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Live.Shared.TreePanelHandlers
  import StoryarnWeb.Components.DashboardComponents

  use StoryarnWeb.Live.Shared.DashboardHandlers

  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Projects
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Sheets
  alias StoryarnWeb.Components.Sidebar.SheetTree

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:sheets}
      on_dashboard={true}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      show_pin={false}
      can_edit={@can_edit}
    >
      <:tree_content>
        <SheetTree.sheets_section
          sheets_tree={@sheets_tree}
          workspace={@workspace}
          project={@project}
          can_edit={@can_edit}
        />
      </:tree_content>
      <SheetTree.delete_modal :if={@can_edit} />
      <div class="max-w-5xl mx-auto px-4 sm:px-6 py-8 space-y-6">
        <.header>
          {dgettext("sheets", "Sheets")}
          <:subtitle>
            {dgettext("sheets", "Create and organize your project's content")}
          </:subtitle>
        </.header>

        <.empty_state :if={@sheets == []} icon="file-text">
          {dgettext("sheets", "No sheets yet. Create your first sheet to get started.")}
        </.empty_state>

        <div :if={@sheets != [] and is_nil(@dashboard_stats)} class="flex justify-center py-12">
          <span class="loading loading-spinner loading-md text-base-content/40"></span>
        </div>

        <div :if={@dashboard_stats} class="space-y-6">
          <%!-- Stats row --%>
          <div class="grid grid-cols-2 sm:grid-cols-5 gap-3">
            <.stat_card
              icon="file-text"
              label={dgettext("sheets", "Sheets")}
              value={@dashboard_stats.sheet_count}
            />
            <.stat_card
              icon="layers"
              label={dgettext("sheets", "Blocks")}
              value={@dashboard_stats.block_count}
            />
            <.stat_card
              icon="variable"
              label={dgettext("sheets", "Variables")}
              value={@dashboard_stats.variable_count}
            />
            <.stat_card
              icon="link"
              label={dgettext("sheets", "In Use")}
              value={@dashboard_stats.variables_in_use}
            />
            <.stat_card
              icon="type"
              label={dgettext("sheets", "Words")}
              value={@dashboard_stats.word_count}
            />
          </div>

          <%!-- Sheet table --%>
          <.dashboard_section title={dgettext("sheets", "All Sheets")}>
            <.dashboard_table_wrapper>
              <.sheet_table
                rows={@sheet_table_data}
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
              total={length(@all_sheet_table_data)}
              event="page_sheets"
            />
          </.dashboard_section>

          <%!-- Issues --%>
          <.dashboard_section :if={@sheet_issues != []} title={dgettext("sheets", "Issues")}>
            <.issue_list issues={@sheet_issues} />
          </.dashboard_section>
        </div>

        <.confirm_modal
          :if={@can_edit}
          id="delete-sheet-confirm"
          title={dgettext("sheets", "Delete sheet?")}
          message={dgettext("sheets", "Are you sure you want to delete this sheet?")}
          confirm_text={dgettext("sheets", "Delete")}
          confirm_variant="error"
          icon="alert-triangle"
          on_confirm={JS.push("confirm_delete")}
        />
      </div>
    </Layouts.focus>
    """
  end

  # ===========================================================================
  # Sheet Table
  # ===========================================================================

  attr :rows, :list, required: true
  attr :sort_by, :string, required: true
  attr :sort_dir, :atom, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, default: false

  defp sheet_table(assigns) do
    ~H"""
    <table class="table table-sm w-full">
      <thead class="sticky top-0 bg-base-100 z-10">
        <tr class="text-xs text-base-content/50 uppercase">
          <th class="font-medium">
            <button
              type="button"
              phx-click="sort_sheets"
              phx-value-column="name"
              class="flex items-center gap-1 hover:text-base-content"
            >
              {dgettext("sheets", "Name")}
              <.sort_indicator column="name" sort_by={@sort_by} sort_dir={@sort_dir} />
            </button>
          </th>
          <th class="font-medium text-right">
            <button
              type="button"
              phx-click="sort_sheets"
              phx-value-column="block_count"
              class="flex items-center gap-1 ml-auto hover:text-base-content"
            >
              {dgettext("sheets", "Blocks")}
              <.sort_indicator column="block_count" sort_by={@sort_by} sort_dir={@sort_dir} />
            </button>
          </th>
          <th class="font-medium text-right hidden sm:table-cell">
            <button
              type="button"
              phx-click="sort_sheets"
              phx-value-column="variable_count"
              class="flex items-center gap-1 ml-auto hover:text-base-content"
            >
              {dgettext("sheets", "Variables")}
              <.sort_indicator column="variable_count" sort_by={@sort_by} sort_dir={@sort_dir} />
            </button>
          </th>
          <th class="font-medium text-right hidden md:table-cell">
            <button
              type="button"
              phx-click="sort_sheets"
              phx-value-column="word_count"
              class="flex items-center gap-1 ml-auto hover:text-base-content"
            >
              {dgettext("sheets", "Words")}
              <.sort_indicator column="word_count" sort_by={@sort_by} sort_dir={@sort_dir} />
            </button>
          </th>
          <th class="font-medium text-right hidden md:table-cell">
            <button
              type="button"
              phx-click="sort_sheets"
              phx-value-column="updated_at"
              class="flex items-center gap-1 ml-auto hover:text-base-content"
            >
              {dgettext("sheets", "Modified")}
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
              navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{row.id}"}
              class="font-medium hover:underline"
            >
              {row.name}
            </.link>
          </td>
          <td class="text-right tabular-nums">{row.block_count}</td>
          <td class="text-right tabular-nums hidden sm:table-cell">{row.variable_count}</td>
          <td class="text-right tabular-nums hidden md:table-cell">{row.word_count}</td>
          <td class="text-right text-base-content/50 text-xs hidden md:table-cell">
            {format_relative_time(row.updated_at)}
          </td>
          <td :if={@can_edit} class="text-right">
            <div phx-hook="TableRowMenu" id={"sheet-menu-#{row.id}"}>
              <button type="button" data-role="trigger" class="btn btn-ghost btn-xs btn-square">
                <.icon name="more-horizontal" class="size-4" />
              </button>
              <template data-role="popover-template">
                <ul class="menu menu-sm">
                  <li>
                    <button
                      type="button"
                      class="text-error"
                      data-event="set_pending_delete"
                      data-params={Jason.encode!(%{id: row.id})}
                      data-modal-id="delete-sheet-confirm"
                    >
                      <.icon name="trash-2" class="size-4" />
                      {dgettext("sheets", "Delete")}
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
        sheets_tree = Sheets.list_sheets_tree(project.id)
        sheets = Sheets.list_all_sheets(project.id)
        can_edit = Projects.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(focus_layout_defaults())
          |> assign(:tree_panel_open, true)
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:sheets_tree, sheets_tree)
          |> assign(:sheets, sheets)
          |> assign(:dashboard_stats, nil)
          |> assign(:all_sheet_table_data, [])
          |> assign(:sheet_table_data, [])
          |> assign(:sheet_issues, [])
          |> assign(:sort_by, "name")
          |> assign(:sort_dir, :asc)
          |> assign(:page, 1)
          |> assign(:total_pages, 1)
          |> assign(:pending_delete_id, nil)

        if connected?(socket), do: Collaboration.subscribe_dashboard(project.id)
        if connected?(socket) and sheets != [], do: send(self(), :load_dashboard_data)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("sheets", "You don't have access to this project."))
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

  def handle_info(:load_dashboard_data, socket) do
    project_id = socket.assigns.project.id
    sheets = Sheets.list_all_sheets(project_id)

    # Run independent queries in parallel with caching
    tasks = [
      Task.async(fn ->
        {DashboardCache.fetch(project_id, :sheet_stats, fn ->
           Sheets.sheet_stats_for_project(project_id)
         end),
         DashboardCache.fetch(project_id, :sheet_words, fn ->
           Sheets.sheet_word_counts(project_id)
         end)}
      end),
      Task.async(fn ->
        referenced_ids =
          DashboardCache.fetch(project_id, :sheet_refs, fn ->
            Sheets.referenced_block_ids_for_project(project_id)
          end)

        issues =
          DashboardCache.fetch(project_id, :sheet_issues, fn ->
            Sheets.detect_sheet_issues(project_id, referenced_ids)
          end)

        {referenced_ids, issues}
      end),
      Task.async(fn ->
        DashboardCache.fetch(project_id, :sheet_total_vars, fn ->
          Sheets.list_project_variables(project_id) |> length()
        end)
      end)
    ]

    [{stats, word_counts}, {referenced_ids, issues}, total_variable_count] =
      Task.await_many(tasks, 15_000)

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

    sorted_table =
      sort_table(
        table_data,
        socket.assigns.sort_by,
        socket.assigns.sort_dir,
        sheet_sort_columns()
      )

    {page_rows, total_pages} = paginate(sorted_table, 1)

    dashboard_stats = %{
      sheet_count: length(sheets),
      block_count: table_data |> Enum.map(& &1.block_count) |> Enum.sum(),
      variable_count: total_variable_count,
      variables_in_use: MapSet.size(referenced_ids),
      word_count: table_data |> Enum.map(& &1.word_count) |> Enum.sum()
    }

    formatted_issues =
      format_sheet_issues(issues, socket.assigns.workspace, socket.assigns.project)

    {:noreply,
     socket
     |> assign(:dashboard_stats, dashboard_stats)
     |> assign(:all_sheet_table_data, sorted_table)
     |> assign(:sheet_table_data, page_rows)
     |> assign(:page, 1)
     |> assign(:total_pages, total_pages)
     |> assign(:sheet_issues, formatted_issues)}
  end

  # ===========================================================================
  # Events
  # Ignore EXIT messages from linked processes (e.g. Task.async in dashboard loading)
  def handle_info({:EXIT, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  # ===========================================================================

  @impl true
  # Tree panel events (from FocusLayout)
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

  def handle_event("sort_sheets", %{"column" => column}, socket) do
    {:noreply,
     handle_sort(socket, column, :all_sheet_table_data, :sheet_table_data, sheet_sort_columns())}
  end

  def handle_event("page_sheets", %{"page" => page}, socket) do
    {:noreply, handle_page(socket, page, :all_sheet_table_data, :sheet_table_data)}
  end

  def handle_event(event, %{"id" => id}, socket)
      when event in ~w(set_pending_delete set_pending_delete_sheet) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event(event, _params, socket)
      when event in ~w(confirm_delete confirm_delete_sheet) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event(event, %{"id" => sheet_id}, socket)
      when event in ~w(delete delete_sheet) do
    with_authorization(socket, :edit_content, fn socket ->
      with %{} = sheet <- Sheets.get_sheet(socket.assigns.project.id, sheet_id),
           {:ok, _} <- Sheets.delete_sheet(sheet) do
        {:noreply,
         socket
         |> put_flash(:info, dgettext("sheets", "Sheet moved to trash."))
         |> reload_sheets()}
      else
        nil -> {:noreply, put_flash(socket, :error, dgettext("sheets", "Sheet not found."))}
        {:error, _} -> {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not delete sheet."))}
      end
    end)
  end

  def handle_event("create_sheet", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      attrs = %{name: dgettext("sheets", "Untitled")}

      case Sheets.create_sheet(socket.assigns.project, attrs) do
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

  def handle_event("create_child_sheet", %{"parent-id" => parent_id}, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      attrs = %{name: dgettext("sheets", "New Sheet"), parent_id: parent_id}

      case Sheets.create_sheet(socket.assigns.project, attrs) do
        {:ok, new_sheet} ->
          {:noreply,
           socket
           |> reload_sheets()
           |> push_navigate(
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

  def handle_event(
        "move_to_parent",
        %{"item_id" => sheet_id, "new_parent_id" => parent_id, "position" => position},
        socket
      ) do
    with_authorization(socket, :edit_content, fn socket ->
      with %{} = sheet <- Sheets.get_sheet(socket.assigns.project.id, sheet_id),
           parent_id = MapUtils.parse_int(parent_id),
           position = MapUtils.parse_int(position) || 0,
           {:ok, _sheet} <- Sheets.move_sheet_to_position(sheet, parent_id, position) do
        {:noreply, reload_sheets(socket)}
      else
        nil ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Sheet not found."))}

        {:error, :would_create_cycle} ->
          {:noreply,
           put_flash(socket, :error, dgettext("sheets", "Cannot move a sheet into its own children."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not move sheet."))}
      end
    end)
  end

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
        |> assign(:sheets_tree, Sheets.list_sheets_tree(project_id))
        |> assign(:sheets, Sheets.list_all_sheets(project_id))
      end
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
        severity: severity,
        message: message,
        href: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{issue.sheet_id}"
      }
    end)
  end
end
