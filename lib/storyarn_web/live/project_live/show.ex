defmodule StoryarnWeb.ProjectLive.Show do
  @moduledoc """
  Project dashboard — overview with stats, issues, speakers, and activity.
  """

  use StoryarnWeb, :live_view
  use StoryarnWeb.Live.Shared.DashboardHandlers

  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Localization
  alias Storyarn.Projects
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers
  alias StoryarnWeb.Live.Shared.RestorationHandlers

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
      active_tool={:dashboard}
      is_super_admin={@is_super_admin}
      online_users={@online_users}
      restoration_banner={@restoration_banner}
    >
      <.vue
        v-component="modules/workspaces/projects/ProjectDashboard"
        v-socket={@socket}
        id="project-dashboard"
        stats={@stats}
        node-dist={@node_dist || []}
        speakers={@speakers || []}
        issues={@issues || []}
        localization={@localization}
        activity={@activity}
        can-edit={@can_manage}
        workspace-slug={@workspace.slug}
        project-slug={@project.slug}
        loading={is_nil(@stats)}
      />
    </StoryarnWeb.Components.ProjectShell.project_shell>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    %{project: project, membership: membership} = socket.assigns
    can_manage = Projects.can?(membership.role, :manage_project)
    {_, restoration_banner} = RestorationHandlers.check_restoration_lock(project.id, false)

    socket =
      socket
      |> assign(:page_title, project.name)
      |> assign(:can_manage, can_manage)
      |> assign(:restoration_banner, restoration_banner)
      |> assign(:stats, nil)
      |> assign(:node_dist, nil)
      |> assign(:speakers, nil)
      |> assign(:issues, nil)
      |> assign(:localization, [])
      |> assign(:activity, [])
      |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Storyarn.PubSub, ProjectChromeHelpers.shell_topic(project.id))
      Collaboration.subscribe_dashboard(project.id)
      Collaboration.subscribe_restoration(project.id)
      send(self(), :load_dashboard_data)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: ProjectChromeHelpers.forward_tree_panel(socket, event, params)

  @impl true
  def handle_info({:project_restoration_started, payload}, socket),
    do: RestorationHandlers.handle_restoration_event({:project_restoration_started, payload}, socket)

  @impl true
  def handle_info({:project_restoration_completed, payload}, socket),
    do: RestorationHandlers.handle_restoration_event({:project_restoration_completed, payload}, socket)

  @impl true
  def handle_info({:project_restoration_failed, payload}, socket),
    do: RestorationHandlers.handle_restoration_event({:project_restoration_failed, payload}, socket)

  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}

  def handle_info({:toolbar_event, _name, _params}, socket), do: {:noreply, socket}

  def handle_info(:load_dashboard_data, socket) do
    project = socket.assigns.project
    project_id = project.id
    ws = socket.assigns.workspace.slug
    ps = project.slug

    # Run independent queries in parallel with caching
    tasks = [
      Task.async(fn ->
        DashboardCache.fetch(project_id, :project_stats, fn ->
          Projects.project_stats(project_id)
        end)
      end),
      Task.async(fn ->
        {DashboardCache.fetch(project_id, :node_dist, fn ->
           Projects.count_all_nodes_by_type(project_id)
         end),
         DashboardCache.fetch(project_id, :speakers, fn ->
           Projects.count_dialogue_lines_by_speaker(project_id)
         end)}
      end),
      Task.async(fn ->
        DashboardCache.fetch(project_id, :project_issues, fn ->
          Projects.detect_issues(project_id, workspace_slug: ws, project_slug: ps)
        end)
      end),
      Task.async(fn ->
        DashboardCache.fetch(project_id, :recent_activity, fn ->
          Projects.recent_activity(project_id)
        end)
      end),
      Task.async(fn ->
        DashboardCache.fetch(project_id, :localization_progress, fn ->
          case Localization.list_languages(project_id) do
            [] -> []
            _languages -> Localization.progress_by_language(project_id)
          end
        end)
      end)
    ]

    [stats, {node_dist, speakers}, issues, activity, localization] =
      Task.await_many(tasks, 15_000)

    {:noreply,
     socket
     |> assign(:stats, stats)
     |> assign(:node_dist, format_node_distribution(node_dist))
     |> assign(:speakers, format_speakers(speakers, ws, ps))
     |> assign(:issues, format_issues(issues))
     |> assign(:localization, localization)
     |> assign(:activity, format_activity(activity))}
  end

  # ===========================================================================
  # Formatters (serialize for Vue)
  # ===========================================================================

  defp format_node_distribution(node_dist) when is_map(node_dist) do
    total = node_dist |> Map.values() |> Enum.sum() |> max(1)

    node_dist
    |> Enum.map(fn {type, count} ->
      %{
        label: node_type_label(type),
        count: count,
        percentage: round(count / total * 100)
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp format_node_distribution(_), do: []

  defp node_type_label("dialogue"), do: dgettext("flows", "Dialogue")
  defp node_type_label("condition"), do: dgettext("flows", "Condition")
  defp node_type_label("instruction"), do: dgettext("flows", "Instruction")
  defp node_type_label("hub"), do: dgettext("flows", "Hub")
  defp node_type_label("jump"), do: dgettext("flows", "Jump")
  defp node_type_label("slug_line"), do: dgettext("flows", "Slug Line")
  defp node_type_label("subflow"), do: dgettext("flows", "Subflow")
  defp node_type_label("entry"), do: dgettext("flows", "Entry")
  defp node_type_label("exit"), do: dgettext("flows", "Exit")
  defp node_type_label(type), do: type

  defp format_speakers(speakers, workspace_slug, project_slug) when is_list(speakers) do
    Enum.map(speakers, fn s ->
      %{
        name: s.sheet_name || dgettext("sheets", "Unknown Speaker"),
        count: s.line_count,
        href:
          if(s.sheet_id,
            do: "/workspaces/#{workspace_slug}/projects/#{project_slug}/sheets/#{s.sheet_id}"
          )
      }
    end)
  end

  defp format_speakers(_, _, _), do: []

  defp format_issues(issues) when is_list(issues) do
    Enum.map(issues, fn issue ->
      %{
        severity: to_string(issue.severity),
        message: issue.message,
        href: issue.href
      }
    end)
  end

  defp format_issues(_), do: []

  defp format_activity(activity) when is_list(activity) do
    Enum.map(activity, fn item ->
      %{
        name: item.name,
        type: item.type,
        updated_at: item.updated_at && DateTime.to_iso8601(item.updated_at)
      }
    end)
  end

  defp format_activity(_), do: []
end
