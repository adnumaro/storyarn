defmodule StoryarnWeb.ProjectLive.Show do
  @moduledoc """
  Project dashboard — overview with stats, issues, speakers, and activity.
  """

  use StoryarnWeb, :live_view

  import StoryarnWeb.Components.DashboardComponents

  alias Storyarn.Localization
  alias Storyarn.Projects

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      workspaces={@workspaces}
      current_workspace={@workspace}
    >
      <div class="max-w-5xl mx-auto px-4 sm:px-6 py-8 space-y-6">
        <%!-- Project Header --%>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold">{@project.name}</h1>
            <p :if={@project.description} class="text-base-content/60 mt-1">
              {@project.description}
            </p>
          </div>
          <.link
            :if={@can_manage}
            navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/settings"}
            class="btn btn-ghost btn-sm"
          >
            <.icon name="settings" class="size-4 mr-1" />
            {dgettext("projects", "Settings")}
          </.link>
        </div>

        <%!-- Loading State --%>
        <div :if={is_nil(@stats)} class="flex items-center justify-center py-12">
          <span class="loading loading-spinner loading-lg text-primary"></span>
        </div>

        <%!-- Dashboard Content --%>
        <div :if={@stats} class="space-y-6">
          <%!-- Section 1: Stats --%>
          <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
            <.stat_card
              icon="file-text"
              label={dgettext("projects", "Sheets")}
              value={@stats.sheet_count}
              href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets"}
            />
            <.stat_card
              icon="variable"
              label={dgettext("projects", "Variables")}
              value={@stats.variable_count}
              href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets"}
            />
            <.stat_card
              icon="git-branch"
              label={dgettext("projects", "Flows")}
              value={@stats.flow_count}
              href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows"}
            />
            <.stat_card
              icon="message-square"
              label={dgettext("projects", "Dialogue Lines")}
              value={@stats.dialogue_count}
              href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows"}
            />
            <.stat_card
              icon="map"
              label={dgettext("projects", "Scenes")}
              value={@stats.scene_count}
              href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/scenes"}
            />
            <.stat_card
              icon="text"
              label={dgettext("projects", "Words")}
              value={@stats.total_word_count}
            />
          </div>

          <%!-- Section 2: Content Breakdown --%>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <.dashboard_section title={dgettext("projects", "Node Distribution")}>
              <.ranked_list
                items={format_node_distribution(@node_dist)}
                empty_message={dgettext("projects", "No flow nodes yet")}
              />
            </.dashboard_section>

            <.dashboard_section title={dgettext("projects", "Top Speakers")}>
              <.ranked_list
                items={format_speakers(@speakers, @workspace.slug, @project.slug)}
                empty_message={dgettext("projects", "No dialogue with speakers yet")}
              />
            </.dashboard_section>
          </div>

          <%!-- Section 3: Issues --%>
          <.dashboard_section title={dgettext("projects", "Issues & Warnings")}>
            <.issue_list
              issues={@issues}
              empty_message={dgettext("projects", "No issues detected")}
            />
          </.dashboard_section>

          <%!-- Section 4: Localization Progress (conditional) --%>
          <.dashboard_section
            :if={@localization != []}
            title={dgettext("projects", "Localization Progress")}
          >
            <div class="space-y-1">
              <.progress_row
                :for={lang <- @localization}
                label={lang.name}
                percentage={lang.percentage}
                detail={"#{lang.final} / #{lang.total}"}
                href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/localization"}
              />
            </div>
          </.dashboard_section>

          <%!-- Section 5: Recent Activity --%>
          <.dashboard_section title={dgettext("projects", "Recent Activity")}>
            <div :if={@activity == []} class="text-sm text-base-content/50 py-4 text-center">
              {dgettext("projects", "No activity yet")}
            </div>
            <div :for={item <- @activity} class="flex items-center gap-3 py-2">
              <.icon name={activity_icon(item.type)} class="size-4 text-base-content/40" />
              <span class="text-sm flex-1">
                <span class="font-medium">{item.name}</span>
                <span class="text-base-content/50">
                  · {activity_type_label(item.type)}
                </span>
              </span>
              <span class="text-xs text-base-content/40">
                {format_relative_time(item.updated_at)}
              </span>
            </div>
          </.dashboard_section>
        </div>
      </div>
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

        socket =
          socket
          |> assign(:page_title, project.name)
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:current_workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_manage, can_manage)
          |> assign(:stats, nil)
          |> assign(:node_dist, nil)
          |> assign(:speakers, nil)
          |> assign(:issues, nil)
          |> assign(:localization, [])
          |> assign(:activity, [])

        if connected?(socket) do
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
  def handle_info(:load_dashboard_data, socket) do
    project = socket.assigns.project
    project_id = project.id
    ws = socket.assigns.workspace.slug
    ps = project.slug

    stats = Projects.project_stats(project_id)
    node_dist = Projects.count_all_nodes_by_type(project_id)
    speakers = Projects.count_dialogue_lines_by_speaker(project_id)
    issues = Projects.detect_issues(project_id, workspace_slug: ws, project_slug: ps)
    activity = Projects.recent_activity(project_id)

    localization =
      case Localization.list_languages(project_id) do
        [] -> []
        _languages -> Localization.progress_by_language(project_id)
      end

    {:noreply,
     socket
     |> assign(:stats, stats)
     |> assign(:node_dist, node_dist)
     |> assign(:speakers, speakers)
     |> assign(:issues, issues)
     |> assign(:localization, localization)
     |> assign(:activity, activity)}
  end

  # ===========================================================================
  # Formatters
  # ===========================================================================

  defp format_node_distribution(node_dist) when is_map(node_dist) do
    node_dist
    |> Enum.map(fn {type, count} ->
      %{label: node_type_label(type), value: count}
    end)
    |> Enum.sort_by(& &1.value, :desc)
  end

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

  defp format_node_distribution(_), do: []

  defp format_speakers(speakers, workspace_slug, project_slug) when is_list(speakers) do
    Enum.map(speakers, fn s ->
      %{
        label: s.sheet_name || dgettext("projects", "Unknown Speaker"),
        value: s.line_count,
        href:
          if(s.sheet_id,
            do: "/workspaces/#{workspace_slug}/projects/#{project_slug}/sheets/#{s.sheet_id}",
            else: nil
          )
      }
    end)
  end

  defp format_speakers(_, _, _), do: []

  defp activity_icon("sheet"), do: "file-text"
  defp activity_icon("flow"), do: "git-branch"
  defp activity_icon("scene"), do: "map"
  defp activity_icon("screenplay"), do: "scroll-text"
  defp activity_icon(_), do: "clock"

  defp activity_type_label("sheet"), do: dgettext("projects", "Sheet")
  defp activity_type_label("flow"), do: dgettext("projects", "Flow")
  defp activity_type_label("scene"), do: dgettext("projects", "Scene")
  defp activity_type_label("screenplay"), do: dgettext("projects", "Screenplay")
  defp activity_type_label(type), do: type

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> dgettext("projects", "just now")
      diff < 3600 -> dgettext("projects", "%{count}m ago", count: div(diff, 60))
      diff < 86_400 -> dgettext("projects", "%{count}h ago", count: div(diff, 3600))
      diff < 604_800 -> dgettext("projects", "%{count}d ago", count: div(diff, 86_400))
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end
