defmodule StoryarnWeb.SceneLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  alias StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Components.UIComponents, only: [empty_state: 1]
  import StoryarnWeb.Live.Shared.TreePanelHandlers
  import StoryarnWeb.Components.DashboardComponents

  use StoryarnWeb.Live.Shared.DashboardHandlers

  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Shared.MapUtils
  alias StoryarnWeb.Components.Sidebar.SceneTree

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:scenes}
      on_dashboard={true}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      show_pin={false}
      can_edit={@can_edit}
    >
      <:tree_content>
        <div role="tablist" class="tabs tabs-border tabs-sm mb-6">
          <button
            role="tab"
            class={["tab", @tree_panel_tab == "scenes" && "tab-active"]}
            phx-click="switch_tree_tab"
            phx-value-tab="scenes"
          >
            <.icon name="map" class="size-3.5 mr-1" />{dgettext("scenes", "Scenes")}
          </button>
          <button
            role="tab"
            class={["tab", @tree_panel_tab == "layers" && "tab-active"]}
            phx-click="switch_tree_tab"
            phx-value-tab="layers"
          >
            <.icon name="layers" class="size-3.5 mr-1" />{dgettext("scenes", "Layers")}
          </button>
        </div>
        <div :if={@tree_panel_tab == "scenes"}>
          <SceneTree.scenes_section
            scenes_tree={@scenes_tree}
            workspace={@workspace}
            project={@project}
            can_edit={@can_edit}
          />
        </div>
        <div :if={@tree_panel_tab == "layers"} class="px-3 py-6">
          <.empty_state icon="layers">
            {dgettext("scenes", "Select a scene to manage layers.")}
          </.empty_state>
        </div>
      </:tree_content>
      <SceneTree.delete_modal :if={@can_edit} />
      <div class="max-w-5xl mx-auto px-4 sm:px-6 py-8 space-y-6">
        <.header>
          {dgettext("scenes", "Scenes")}
          <:subtitle>
            {dgettext("scenes", "Create scenes to visualize your world")}
          </:subtitle>
        </.header>

        <.empty_state :if={@scenes == []} icon="map">
          {dgettext("scenes", "No scenes yet. Create your first scene to get started.")}
        </.empty_state>

        <div :if={@scenes != [] and is_nil(@dashboard_stats)} class="flex justify-center py-12">
          <span class="loading loading-spinner loading-md text-base-content/40"></span>
        </div>

        <div :if={@dashboard_stats} class="space-y-6">
          <%!-- Stats row --%>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <.stat_card
              icon="map"
              label={dgettext("scenes", "Scenes")}
              value={@dashboard_stats.scene_count}
            />
            <.stat_card
              icon="pentagon"
              label={dgettext("scenes", "Zones")}
              value={@dashboard_stats.zone_count}
            />
            <.stat_card
              icon="map-pin"
              label={dgettext("scenes", "Pins")}
              value={@dashboard_stats.pin_count}
            />
            <.stat_card
              icon="image"
              label={dgettext("scenes", "Backgrounds")}
              value={@dashboard_stats.background_count}
            />
          </div>

          <%!-- Scene table --%>
          <.dashboard_section title={dgettext("scenes", "All Scenes")}>
            <.dashboard_table_wrapper>
              <.scene_table
                rows={@scene_table_data}
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
              total={length(@all_scene_table_data)}
              event="page_scenes"
            />
          </.dashboard_section>

          <%!-- Issues --%>
          <.dashboard_section :if={@scene_issues != []} title={dgettext("scenes", "Issues")}>
            <.issue_list issues={@scene_issues} />
          </.dashboard_section>
        </div>

        <.modal
          :if={@live_action == :new and @can_edit}
          id="new-scene-modal"
          show
          on_cancel={JS.patch(~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/scenes")}
        >
          <.live_component
            module={StoryarnWeb.SceneLive.Form}
            id="new-scene-form"
            project={@project}
            title={dgettext("scenes", "New Scene")}
            navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/scenes"}
          />
        </.modal>

        <.confirm_modal
          :if={@can_edit}
          id="delete-scene-confirm"
          title={dgettext("scenes", "Delete scene?")}
          message={dgettext("scenes", "Are you sure you want to delete this scene?")}
          confirm_text={dgettext("scenes", "Delete")}
          confirm_variant="error"
          icon="alert-triangle"
          on_confirm={JS.push("confirm_delete")}
        />
      </div>
    </Layouts.focus>
    """
  end

  # ===========================================================================
  # Scene Table
  # ===========================================================================

  attr :rows, :list, required: true
  attr :sort_by, :string, required: true
  attr :sort_dir, :atom, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, default: false

  defp scene_table(assigns) do
    ~H"""
    <table class="table table-sm w-full">
      <thead class="sticky top-0 bg-base-100 z-10">
        <tr class="text-xs text-base-content/50 uppercase">
          <th class="font-medium">
            <button
              type="button"
              phx-click="sort_scenes"
              phx-value-column="name"
              class="flex items-center gap-1 hover:text-base-content"
            >
              {dgettext("scenes", "Name")}
              <.sort_indicator column="name" sort_by={@sort_by} sort_dir={@sort_dir} />
            </button>
          </th>
          <th class="font-medium text-right hidden sm:table-cell">
            <button
              type="button"
              phx-click="sort_scenes"
              phx-value-column="zone_count"
              class="flex items-center gap-1 ml-auto hover:text-base-content"
            >
              {dgettext("scenes", "Zones")}
              <.sort_indicator column="zone_count" sort_by={@sort_by} sort_dir={@sort_dir} />
            </button>
          </th>
          <th class="font-medium text-right">
            <button
              type="button"
              phx-click="sort_scenes"
              phx-value-column="pin_count"
              class="flex items-center gap-1 ml-auto hover:text-base-content"
            >
              {dgettext("scenes", "Pins")}
              <.sort_indicator column="pin_count" sort_by={@sort_by} sort_dir={@sort_dir} />
            </button>
          </th>
          <th class="font-medium text-right hidden sm:table-cell">
            <button
              type="button"
              phx-click="sort_scenes"
              phx-value-column="connection_count"
              class="flex items-center gap-1 ml-auto hover:text-base-content"
            >
              {dgettext("scenes", "Connections")}
              <.sort_indicator
                column="connection_count"
                sort_by={@sort_by}
                sort_dir={@sort_dir}
              />
            </button>
          </th>
          <th class="font-medium text-right hidden md:table-cell">
            <button
              type="button"
              phx-click="sort_scenes"
              phx-value-column="updated_at"
              class="flex items-center gap-1 ml-auto hover:text-base-content"
            >
              {dgettext("scenes", "Modified")}
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
              navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/scenes/#{row.id}"}
              class="font-medium hover:underline"
            >
              {row.name}
            </.link>
          </td>
          <td class="text-right tabular-nums hidden sm:table-cell">{row.zone_count}</td>
          <td class="text-right tabular-nums">{row.pin_count}</td>
          <td class="text-right tabular-nums hidden sm:table-cell">{row.connection_count}</td>
          <td class="text-right text-base-content/50 text-xs hidden md:table-cell">
            {format_relative_time(row.updated_at)}
          </td>
          <td :if={@can_edit} class="text-right">
            <div phx-hook="TableRowMenu" id={"scene-menu-#{row.id}"}>
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
                      data-modal-id="delete-scene-confirm"
                    >
                      <.icon name="trash-2" class="size-4" />
                      {dgettext("scenes", "Delete")}
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
        scenes = Scenes.list_scenes(project.id)
        scenes_tree = Scenes.list_scenes_tree(project.id)
        can_edit = Projects.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(focus_layout_defaults())
          |> assign(:tree_panel_open, true)
          |> assign(:tree_panel_tab, "scenes")
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:scenes, scenes)
          |> assign(:scenes_tree, scenes_tree)
          |> assign(:dashboard_stats, nil)
          |> assign(:all_scene_table_data, [])
          |> assign(:scene_table_data, [])
          |> assign(:scene_issues, [])
          |> assign(:sort_by, "name")
          |> assign(:sort_dir, :asc)
          |> assign(:page, 1)
          |> assign(:total_pages, 1)
          |> assign(:pending_delete_id, nil)

        if connected?(socket), do: Collaboration.subscribe_dashboard(project.id)
        if connected?(socket) and scenes != [], do: send(self(), :load_dashboard_data)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("scenes", "You don't have access to this project."))
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
    scenes = Scenes.list_scenes(project_id)

    # Run independent queries in parallel with caching
    tasks = [
      Task.async(fn ->
        {DashboardCache.fetch(project_id, :scene_stats, fn ->
           Scenes.scene_stats_for_project(project_id)
         end),
         DashboardCache.fetch(project_id, :scene_bg, fn ->
           Scenes.scenes_with_background_count(project_id)
         end)}
      end),
      Task.async(fn ->
        DashboardCache.fetch(project_id, :scene_issues, fn ->
          Scenes.detect_scene_issues(project_id)
        end)
      end)
    ]

    [{stats, bg_count}, issues] = Task.await_many(tasks, 15_000)

    table_data =
      Enum.map(scenes, fn scene ->
        scene_stats =
          Map.get(stats, scene.id, %{
            zone_count: 0,
            pin_count: 0,
            connection_count: 0
          })

        %{
          id: scene.id,
          name: scene.name,
          zone_count: scene_stats.zone_count,
          pin_count: scene_stats.pin_count,
          connection_count: scene_stats.connection_count,
          updated_at: scene.updated_at
        }
      end)

    sorted_table =
      sort_table(
        table_data,
        socket.assigns.sort_by,
        socket.assigns.sort_dir,
        scene_sort_columns()
      )

    {page_rows, total_pages} = paginate(sorted_table, 1)

    dashboard_stats = %{
      scene_count: length(scenes),
      zone_count: table_data |> Enum.map(& &1.zone_count) |> Enum.sum(),
      pin_count: table_data |> Enum.map(& &1.pin_count) |> Enum.sum(),
      background_count: bg_count
    }

    formatted_issues =
      format_scene_issues(issues, socket.assigns.workspace, socket.assigns.project)

    {:noreply,
     socket
     |> assign(:dashboard_stats, dashboard_stats)
     |> assign(:all_scene_table_data, sorted_table)
     |> assign(:scene_table_data, page_rows)
     |> assign(:page, 1)
     |> assign(:total_pages, total_pages)
     |> assign(:scene_issues, formatted_issues)}
  end

  @impl true
  def handle_info({StoryarnWeb.SceneLive.Form, {:saved, scene}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, dgettext("scenes", "Scene created successfully."))
     |> push_navigate(
       to:
         ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{scene.id}"
     )}
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  # Tree panel events (from FocusLayout)
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

  def handle_event("switch_tree_tab", %{"tab" => tab}, socket)
      when tab in ~w(scenes layers) do
    {:noreply, assign(socket, :tree_panel_tab, tab)}
  end

  def handle_event("sort_scenes", %{"column" => column}, socket) do
    {:noreply,
     handle_sort(socket, column, :all_scene_table_data, :scene_table_data, scene_sort_columns())}
  end

  def handle_event("page_scenes", %{"page" => page}, socket) do
    {:noreply, handle_page(socket, page, :all_scene_table_data, :scene_table_data)}
  end

  def handle_event(event, %{"id" => id}, socket)
      when event in ~w(set_pending_delete set_pending_delete_scene) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event(event, _params, socket)
      when event in ~w(confirm_delete confirm_delete_scene) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event(event, %{"id" => scene_id}, socket)
      when event in ~w(delete delete_scene) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Scenes.get_scene(socket.assigns.project.id, scene_id) do
        nil -> {:noreply, put_flash(socket, :error, dgettext("scenes", "Scene not found."))}
        scene -> do_delete_scene(socket, scene)
      end
    end)
  end

  def handle_event("create_scene", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Scenes.create_scene(socket.assigns.project, %{name: dgettext("scenes", "Untitled")}) do
        {:ok, new_scene} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{new_scene.id}"
           )}

        {:error, :limit_reached, _details} ->
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not create scene."))}
      end
    end)
  end

  def handle_event("create_child_scene", %{"parent-id" => parent_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      attrs = %{name: dgettext("scenes", "Untitled"), parent_id: parent_id}

      case Scenes.create_scene(socket.assigns.project, attrs) do
        {:ok, new_scene} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{new_scene.id}"
           )}

        {:error, :limit_reached, _details} ->
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not create scene."))}
      end
    end)
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Scenes.get_scene(socket.assigns.project.id, item_id) do
        nil -> {:noreply, put_flash(socket, :error, dgettext("scenes", "Scene not found."))}
        scene -> do_move_scene(socket, scene, new_parent_id, position)
      end
    end)
  end

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp do_delete_scene(socket, scene) do
    case Scenes.delete_scene(scene) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("scenes", "Scene moved to trash."))
         |> reload_scenes()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not delete scene."))}
    end
  end

  defp do_move_scene(socket, scene, new_parent_id, position) do
    new_parent_id = MapUtils.parse_int(new_parent_id)
    position = MapUtils.parse_int(position) || 0

    case Scenes.move_scene_to_position(scene, new_parent_id, position) do
      {:ok, _} ->
        {:noreply, reload_scenes(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not move scene."))}
    end
  end

  defp reload_scenes(socket) do
    project_id = socket.assigns.project.id

    reload_dashboard(
      socket,
      :scenes,
      :all_scene_table_data,
      :scene_table_data,
      :scene_issues,
      fn s ->
        s
        |> assign(:scenes, Scenes.list_scenes(project_id))
        |> assign(:scenes_tree, Scenes.list_scenes_tree(project_id))
      end
    )
  end

  defp scene_sort_columns do
    %{
      "name" => &String.downcase(&1.name),
      "zone_count" => & &1.zone_count,
      "pin_count" => & &1.pin_count,
      "connection_count" => & &1.connection_count,
      "updated_at" => &(&1.updated_at || ~U[1970-01-01 00:00:00Z])
    }
  end

  defp format_scene_issues(issues, workspace, project) do
    Enum.map(issues, fn issue ->
      {severity, message} =
        case issue.issue_type do
          :empty_scene ->
            {:info,
             dgettext("scenes", "Scene \"%{name}\" has no zones or pins", name: issue.scene_name)}

          :no_background ->
            {:warning,
             dgettext("scenes", "Scene \"%{name}\" has no background image",
               name: issue.scene_name
             )}

          :missing_shortcut ->
            {:warning,
             dgettext("scenes", "Scene \"%{name}\" has no shortcut", name: issue.scene_name)}

          _ ->
            {:info, gettext("Issue detected")}
        end

      %{
        severity: severity,
        message: message,
        href: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/scenes/#{issue.scene_id}"
      }
    end)
  end
end
