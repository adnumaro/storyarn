defmodule StoryarnWeb.SettingsLive.WorkspaceDeletedProjects do
  @moduledoc """
  Read-only inventory of projects retained in workspace trash.

  Recovery remains unavailable until the canonical project-snapshot restore
  workflow is connected.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Projects
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Workspaces

  @impl true
  def mount(_params, _session, socket) do
    %{workspace: workspace, membership: membership} = socket.assigns

    if Workspaces.can?(membership.role, :access_workspace_settings) do
      deleted_projects = Projects.list_deleted_projects(workspace.id)

      {:ok,
       socket
       |> assign(:page_title, dgettext("workspaces", "Deleted Projects"))
       |> assign(
         :current_path,
         ~p"/users/settings/workspaces/#{workspace.slug}/deleted-projects"
       )
       |> assign(:deleted_projects, deleted_projects)}
    else
      {:ok,
       socket
       |> put_flash(
         :error,
         dgettext("workspaces", "You don't have permission to manage this workspace.")
       )
       |> push_navigate(to: ~p"/users/settings")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      workspaces={@workspaces}
      managed_workspace_slugs={@managed_workspace_slugs}
      general_workspace_slugs={@general_workspace_slugs}
      current_path={@current_path}
    >
      <.vue
        v-component="live/workspace/settings/WorkspaceSettingsDeletedProjects"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-deleted-projects-vue"
        deleted-projects={serialize_deleted_projects(@deleted_projects)}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  defp serialize_deleted_projects(projects) do
    Enum.map(projects, fn project ->
      %{
        id: project.id,
        name: project.name,
        deleted_time_ago: dgettext("workspaces", "Deleted %{time_ago}", time_ago: format_time_ago(project.deleted_at)),
        deleted_by_text:
          if(project.deleted_by,
            do: dgettext("workspaces", "by %{email}", email: project.deleted_by.email)
          )
      }
    end)
  end

  defp format_time_ago(datetime) do
    diff = DateTime.diff(TimeHelpers.now(), datetime, :second)

    cond do
      diff < 60 ->
        dgettext("workspaces", "just now")

      diff < 3600 ->
        dngettext("workspaces", "%{count} minute ago", "%{count} minutes ago", div(diff, 60), count: div(diff, 60))

      diff < 86_400 ->
        dngettext("workspaces", "%{count} hour ago", "%{count} hours ago", div(diff, 3600), count: div(diff, 3600))

      true ->
        dngettext("workspaces", "%{count} day ago", "%{count} days ago", div(diff, 86_400), count: div(diff, 86_400))
    end
  end
end
