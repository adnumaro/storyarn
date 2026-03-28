defmodule StoryarnWeb.ProjectLive.Show do
  @moduledoc """
  Project dashboard — overview with stats, issues, speakers, and activity.
  """

  use StoryarnWeb, :live_view

  import StoryarnWeb.Live.Shared.TreePanelHandlers

  use StoryarnWeb.Live.Shared.DashboardHandlers
  alias StoryarnWeb.Live.Shared.RestorationHandlers

  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Localization
  alias Storyarn.Projects

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      socket={@socket}
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:dashboard}
      has_tree={false}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      on_dashboard={true}
      can_edit={@can_manage}
      restoration_banner={@restoration_banner}
    >
      <.vue
        v-component="project/ProjectDashboard"
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
    </Layouts.app>
    """
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(socket.assigns.current_scope, workspace_slug, project_slug) do
      {:ok, project, membership} ->
        can_manage = Projects.can?(membership.role, :manage_project)
        {_, restoration_banner} = RestorationHandlers.check_restoration_lock(project.id, false)

        socket =
          socket
          |> assign(:page_title, project.name)
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_manage, can_manage)
          |> assign(:restoration_banner, restoration_banner)
          |> assign(:stats, nil)
          |> assign(:node_dist, nil)
          |> assign(:speakers, nil)
          |> assign(:issues, nil)
          |> assign(:localization, [])
          |> assign(:activity, [])
          |> assign(focus_layout_defaults())

        if connected?(socket) do
          Collaboration.subscribe_dashboard(project.id)
          Collaboration.subscribe_restoration(project.id)
          send(self(), :load_dashboard_data)
        end

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("projects", "Project not found."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

  @impl true
  def handle_info({:project_restoration_started, payload}, socket),
    do:
      RestorationHandlers.handle_restoration_event(
        {:project_restoration_started, payload},
        socket
      )

  @impl true
  def handle_info({:project_restoration_completed, payload}, socket),
    do:
      RestorationHandlers.handle_restoration_event(
        {:project_restoration_completed, payload},
        socket
      )

  @impl true
  def handle_info({:project_restoration_failed, payload}, socket),
    do:
      RestorationHandlers.handle_restoration_event(
        {:project_restoration_failed, payload},
        socket
      )

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

  @node_type_labels %{
    "dialogue" => "Dialogue",
    "condition" => "Condition",
    "instruction" => "Instruction",
    "hub" => "Hub",
    "jump" => "Jump",
    "slug_line" => "Slug Line",
    "subflow" => "Subflow",
    "entry" => "Entry",
    "exit" => "Exit"
  }

  defp node_type_label(type), do: Map.get(@node_type_labels, type, type)

  defp format_speakers(speakers, workspace_slug, project_slug) when is_list(speakers) do
    Enum.map(speakers, fn s ->
      %{
        name: s.sheet_name || "Unknown Speaker",
        count: s.line_count,
        href:
          if(s.sheet_id,
            do: "/workspaces/#{workspace_slug}/projects/#{project_slug}/sheets/#{s.sheet_id}",
            else: nil
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
