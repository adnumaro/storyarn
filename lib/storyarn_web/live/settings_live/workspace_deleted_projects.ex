defmodule StoryarnWeb.SettingsLive.WorkspaceDeletedProjects do
  @moduledoc """
  LiveView for recovering deleted projects from their snapshots.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Billing
  alias Storyarn.Projects
  alias Storyarn.Versioning
  alias StoryarnWeb.Components.SettingsLayout
  alias StoryarnWeb.Helpers.Authorize

  @impl true
  def mount(_params, _session, socket) do
    %{workspace: workspace, membership: membership} = socket.assigns

    if membership.role in ["owner", "admin"] do
      deleted_projects = Projects.list_deleted_projects(workspace.id)

      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        "workspace:#{workspace.id}:recovery"
      )

      {:ok,
       socket
       |> assign(:page_title, dgettext("workspaces", "Deleted Projects"))
       |> assign(
         :current_path,
         ~p"/users/settings/workspaces/#{workspace.slug}/deleted-projects"
       )
       |> assign(:deleted_projects, deleted_projects)
       |> assign(:expanded_project_id, nil)
       |> assign(:snapshots, [])
       |> assign(:recovering, false)}
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
    <SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      workspaces={@workspaces}
      managed_workspace_slugs={@managed_workspace_slugs}
      current_path={@current_path}
    >
      <.vue
        v-component="live/workspace/settings/DeletedProjects"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-deleted-projects-vue"
        deleted-projects={serialize_deleted_projects(@deleted_projects)}
        expanded-project-id={@expanded_project_id}
        snapshots={serialize_snapshots(@snapshots)}
        recovering={@recovering}
      />
    </SettingsLayout.settings>
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
          ),
        snapshot_count: project.snapshot_count
      }
    end)
  end

  defp serialize_snapshots(snapshots) do
    Enum.map(snapshots, fn snapshot ->
      %{
        id: snapshot.id,
        title: snapshot.title,
        version_number: snapshot.version_number,
        formatted_date: Calendar.strftime(snapshot.inserted_at, "%b %d, %Y at %H:%M"),
        entity_counts: snapshot.entity_counts
      }
    end)
  end

  @impl true
  def handle_event("toggle_project", %{"id" => id}, socket) do
    project_id = String.to_integer(id)

    if socket.assigns.expanded_project_id == project_id do
      {:noreply,
       socket
       |> assign(:expanded_project_id, nil)
       |> assign(:snapshots, [])}
    else
      snapshots = Versioning.list_project_snapshots(project_id, limit: 20)

      {:noreply,
       socket
       |> assign(:expanded_project_id, project_id)
       |> assign(:snapshots, snapshots)}
    end
  end

  @impl true
  def handle_event("recover_project", %{"snapshot_id" => snapshot_id, "project_id" => project_id}, socket) do
    Authorize.with_authorization(socket, :manage_workspace, fn socket ->
      workspace = socket.assigns.workspace

      case Billing.can_create_project?(workspace) do
        :ok ->
          %{
            workspace_id: workspace.id,
            snapshot_id: snapshot_id,
            project_id: project_id,
            user_id: socket.assigns.current_scope.user.id
          }
          |> Storyarn.Workers.RecoverProjectWorker.new()
          |> Oban.insert()

          {:noreply,
           socket
           |> assign(:recovering, true)
           |> put_flash(:info, dgettext("workspaces", "Recovery started. This may take a moment..."))}

        {:error, :limit_reached, _details} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             dgettext("workspaces", "Workspace project limit reached. Upgrade your plan to recover this project.")
           )}
      end
    end)
  end

  @impl true
  def handle_info({:recovery_completed, %{project_name: name}}, socket) do
    deleted_projects = Projects.list_deleted_projects(socket.assigns.workspace.id)

    {:noreply,
     socket
     |> assign(:recovering, false)
     |> assign(:deleted_projects, deleted_projects)
     |> put_flash(:info, dgettext("workspaces", "Project recovered as '%{name}'", name: name))}
  end

  @impl true
  def handle_info({:recovery_failed, %{reason: reason}}, socket) do
    {:noreply,
     socket
     |> assign(:recovering, false)
     |> put_flash(:error, dgettext("workspaces", "Recovery failed: %{reason}", reason: reason))}
  end

  defp format_time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

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
