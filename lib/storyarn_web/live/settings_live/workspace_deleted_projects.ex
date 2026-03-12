defmodule StoryarnWeb.SettingsLive.WorkspaceDeletedProjects do
  @moduledoc """
  LiveView for recovering deleted projects from their snapshots.
  """
  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Billing
  alias Storyarn.Projects
  alias Storyarn.Versioning
  alias Storyarn.Workspaces

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope

    case Workspaces.get_workspace_by_slug(scope, slug) do
      {:ok, workspace, membership} ->
        if membership.role in ["owner", "admin"] do
          deleted_projects = Projects.list_deleted_projects(workspace.id)

          Phoenix.PubSub.subscribe(
            Storyarn.PubSub,
            "workspace:#{workspace.id}:recovery"
          )

          {:ok,
           socket
           |> assign(:page_title, gettext("Deleted Projects"))
           |> assign(:current_path, ~p"/users/settings/workspaces/#{slug}/deleted-projects")
           |> assign(:workspace, workspace)
           |> assign(:membership, membership)
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

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("workspaces", "Workspace not found."))
         |> push_navigate(to: ~p"/users/settings")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      flash={@flash}
      current_scope={@current_scope}
      workspaces={@workspaces}
      managed_workspace_slugs={@managed_workspace_slugs}
      current_path={@current_path}
    >
      <:title>{gettext("Deleted Projects")}</:title>
      <:subtitle>
        {gettext("Recover deleted projects from their snapshots")}
      </:subtitle>

      <div class="space-y-4">
        <div :if={@deleted_projects == []} class="py-12">
          <.empty_state
            icon="trash-2"
            title={gettext("No deleted projects")}
          >
            {gettext("Deleted projects with available snapshots will appear here.")}
          </.empty_state>
        </div>

        <div :for={project <- @deleted_projects} class="border border-base-300 rounded-lg">
          <button
            type="button"
            class="w-full flex items-center justify-between p-4 hover:bg-base-content/5 transition-colors"
            phx-click="toggle_project"
            phx-value-id={project.id}
          >
            <div class="flex items-center gap-3">
              <.icon name="folder" class="size-5 opacity-60" />
              <div class="text-left">
                <div class="font-medium">{project.name}</div>
                <div class="text-sm opacity-60">
                  {gettext("Deleted %{time_ago}",
                    time_ago: format_time_ago(project.deleted_at)
                  )}
                  <span :if={project.deleted_by}>
                    {gettext("by %{email}", email: project.deleted_by.email)}
                  </span>
                </div>
              </div>
            </div>
            <div class="flex items-center gap-3">
              <span class="badge badge-sm badge-ghost">
                {ngettext(
                  "%{count} snapshot",
                  "%{count} snapshots",
                  project.snapshot_count,
                  count: project.snapshot_count
                )}
              </span>
              <.icon
                name={if @expanded_project_id == project.id, do: "chevron-up", else: "chevron-down"}
                class="size-4 opacity-60"
              />
            </div>
          </button>

          <div
            :if={@expanded_project_id == project.id}
            class="border-t border-base-300 p-4 space-y-3"
          >
            <div :if={@snapshots == []} class="text-sm opacity-60 py-4 text-center">
              {gettext("No snapshots available for this project.")}
            </div>

            <div
              :for={snapshot <- @snapshots}
              class="flex items-center justify-between p-3 bg-base-200/50 rounded-lg"
            >
              <div>
                <div class="font-medium text-sm">
                  {snapshot.title || gettext("Snapshot v%{number}", number: snapshot.version_number)}
                </div>
                <div class="text-xs opacity-60 mt-0.5">
                  {Calendar.strftime(snapshot.inserted_at, "%b %d, %Y at %H:%M")}
                  <span :if={snapshot.entity_counts}>
                    — {format_entity_counts(snapshot.entity_counts)}
                  </span>
                </div>
              </div>
              <.button
                variant="primary"
                phx-click={show_modal("recover-confirm-#{snapshot.id}")}
                disabled={@recovering}
                class="btn-sm"
              >
                <.icon name="rotate-ccw" class="size-3.5" />
                {gettext("Recover")}
              </.button>

              <.confirm_modal
                id={"recover-confirm-#{snapshot.id}"}
                title={gettext("Recover project?")}
                message={
                  gettext(
                    "This will create a new project from snapshot v%{number}. The recovered project will appear in your workspace.",
                    number: snapshot.version_number
                  )
                }
                confirm_text={gettext("Recover")}
                confirm_variant="primary"
                icon="rotate-ccw"
                on_confirm={
                  JS.push("recover_project",
                    value: %{snapshot_id: snapshot.id, project_id: project.id}
                  )
                }
              />
            </div>
          </div>
        </div>
      </div>
    </Layouts.settings>
    """
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
  def handle_event(
        "recover_project",
        %{"snapshot_id" => snapshot_id, "project_id" => project_id},
        socket
      ) do
    with_authorization(socket, :manage_workspace, fn socket ->
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
           |> put_flash(:info, gettext("Recovery started. This may take a moment..."))}

        {:error, :limit_reached, _details} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext(
               "Workspace project limit reached. Upgrade your plan to recover this project."
             )
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
     |> put_flash(:info, gettext("Project recovered as '%{name}'", name: name))}
  end

  @impl true
  def handle_info({:recovery_failed, %{reason: reason}}, socket) do
    {:noreply,
     socket
     |> assign(:recovering, false)
     |> put_flash(:error, gettext("Recovery failed: %{reason}", reason: reason))}
  end

  defp format_time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 ->
        gettext("just now")

      diff < 3600 ->
        ngettext("%{count} minute ago", "%{count} minutes ago", div(diff, 60),
          count: div(diff, 60)
        )

      diff < 86_400 ->
        ngettext("%{count} hour ago", "%{count} hours ago", div(diff, 3600),
          count: div(diff, 3600)
        )

      true ->
        ngettext("%{count} day ago", "%{count} days ago", div(diff, 86_400),
          count: div(diff, 86_400)
        )
    end
  end

  defp format_entity_counts(counts) do
    parts = []

    parts =
      if counts["sheets"] && counts["sheets"] > 0,
        do: [
          ngettext("%{count} sheet", "%{count} sheets", counts["sheets"], count: counts["sheets"])
          | parts
        ],
        else: parts

    parts =
      if counts["flows"] && counts["flows"] > 0,
        do: [
          ngettext("%{count} flow", "%{count} flows", counts["flows"], count: counts["flows"])
          | parts
        ],
        else: parts

    parts =
      if counts["scenes"] && counts["scenes"] > 0,
        do: [
          ngettext("%{count} scene", "%{count} scenes", counts["scenes"], count: counts["scenes"])
          | parts
        ],
        else: parts

    parts |> Enum.reverse() |> Enum.join(", ")
  end
end
