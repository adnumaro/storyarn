defmodule StoryarnWeb.SettingsLive.WorkspaceDeletedProjects do
  @moduledoc """
  LiveView for recovering deleted projects from their snapshots.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Billing
  alias Storyarn.Projects
  alias Storyarn.Versioning
  alias Storyarn.Workspaces
  alias StoryarnWeb.Helpers.Authorize

  @max_bigint 9_223_372_036_854_775_807

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
       |> assign(:recovering, false)
       |> assign(
         :recovery_enabled,
         Versioning.restore_enabled?(:deleted_project_recovery)
       )}
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
      current_path={@current_path}
    >
      <.vue
        v-component="live/workspace/settings/WorkspaceSettingsDeletedProjects"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-deleted-projects-vue"
        deleted-projects={serialize_deleted_projects(@deleted_projects)}
        expanded-project-id={@expanded_project_id}
        snapshots={serialize_snapshots(@snapshots)}
        recovering={@recovering}
        recovery-enabled={@recovery_enabled}
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
    with :ok <- Versioning.ensure_restore_enabled(:deleted_project_recovery),
         :ok <- authorize_current_manager(socket),
         {:ok, project_id} <- parse_id(id),
         %Projects.Project{} <-
           Projects.get_deleted_project(socket.assigns.workspace.id, project_id) do
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
    else
      _error -> recovery_unavailable(socket)
    end
  end

  def handle_event("toggle_project", _params, socket), do: recovery_unavailable(socket)

  @impl true
  def handle_event("recover_project", %{"snapshot_id" => snapshot_id, "project_id" => project_id}, socket) do
    Authorize.with_authorization(socket, :manage_workspace, fn socket ->
      with :ok <- Versioning.ensure_restore_enabled(:deleted_project_recovery),
           :ok <- authorize_current_manager(socket),
           {:ok, project_id} <- parse_id(project_id),
           {:ok, snapshot_id} <- parse_id(snapshot_id),
           %Projects.Project{} <-
             Projects.get_deleted_project(socket.assigns.workspace.id, project_id),
           snapshot when not is_nil(snapshot) <-
             Versioning.get_project_snapshot(project_id, snapshot_id) do
        enqueue_recovery(socket, project_id, snapshot.id)
      else
        _error -> recovery_unavailable(socket)
      end
    end)
  end

  def handle_event("recover_project", _params, socket), do: recovery_unavailable(socket)

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

  defp enqueue_recovery(socket, project_id, snapshot_id) do
    workspace = socket.assigns.workspace

    case Billing.can_create_project?(workspace) do
      :ok ->
        result =
          %{
            workspace_id: workspace.id,
            snapshot_id: snapshot_id,
            project_id: project_id,
            user_id: socket.assigns.current_scope.user.id
          }
          |> Storyarn.Workers.RecoverProjectWorker.new()
          |> Oban.insert()

        case result do
          {:ok, _job} ->
            {:noreply,
             socket
             |> assign(:recovering, true)
             |> put_flash(
               :info,
               dgettext("workspaces", "Recovery started. This may take a moment...")
             )}

          {:error, _reason} ->
            recovery_unavailable(socket)
        end

      {:error, :limit_reached, _details} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext(
             "workspaces",
             "Workspace project limit reached. Upgrade your plan to recover this project."
           )
         )}
    end
  end

  defp recovery_unavailable(socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       dgettext("workspaces", "Recovery failed: %{reason}", reason: "temporarily unavailable")
     )}
  end

  defp parse_id(value) when is_integer(value) and value > 0 and value <= @max_bigint, do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 and id <= @max_bigint -> {:ok, id}
      _error -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp authorize_current_manager(socket) do
    workspace_id = socket.assigns.workspace.id
    user_id = socket.assigns.current_scope.user.id

    case Workspaces.get_membership(workspace_id, user_id) do
      %{role: role} when role in ["owner", "admin"] -> :ok
      _membership -> {:error, :unauthorized}
    end
  end
end
