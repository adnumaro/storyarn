defmodule StoryarnWeb.ProjectSettingsLive.Snapshots do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Versioning
  alias StoryarnWeb.Helpers.Authorize

  # ===========================================================================
  # Render
  # ===========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}"}
      back_label={dgettext("projects", "Back to project")}
      sidebar_sections={project_settings_sections(@workspace, @project)}
    >
      <:title>{dgettext("projects", "Snapshots")}</:title>
      <:subtitle>
        {dgettext("projects", "Create and restore point-in-time project backups")}
      </:subtitle>

      <.vue
        v-component="modules/projects/settings/Snapshots"
        v-socket={@socket}
        id="project-settings-snapshots"
        snapshots={serialize_snapshots(@snapshots)}
        can-create-snapshot={@can_create_snapshot}
        restoration-in-progress={@restoration_in_progress}
        workspace-slug={@workspace.slug}
        project-slug={@project.slug}
      />
    </Layouts.settings>
    """
  end

  # ===========================================================================
  # Serialization helpers
  # ===========================================================================

  defp serialize_snapshots(snapshots) do
    Enum.map(snapshots, fn s ->
      %{
        id: s.id,
        title: s.title,
        description: s.description,
        versionNumber: s.version_number,
        insertedAt: s.inserted_at && DateTime.to_iso8601(s.inserted_at),
        snapshotSizeBytes: s.snapshot_size_bytes,
        entityCounts: s.entity_counts,
        createdByEmail: s.created_by && s.created_by.email
      }
    end)
  end

  # ===========================================================================
  # Mount & handle_params
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    %{project: project, membership: membership} = socket.assigns

    if Projects.can?(membership.role, :manage_project) do
      socket =
        socket
        |> assign(:current_workspace, project.workspace)
        |> assign(:snapshots, Versioning.list_project_snapshots(project.id))
        |> assign(
          :can_create_snapshot,
          Billing.can_create_project_snapshot?(project.id, project.workspace_id) == :ok
        )
        |> assign(:snapshot_form, to_form(snapshot_changeset(%{}), as: "snapshot"))
        |> assign(:restoration_in_progress, restoration_in_progress?(project.id))
        |> maybe_subscribe_restoration(project.id)

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(
         :error,
         dgettext("projects", "You don't have permission to manage this project.")
       )
       |> redirect(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")}
    end
  end

  @impl true
  def handle_params(_params, url, socket) do
    current_path = URI.parse(url).path

    socket =
      socket
      |> assign(:page_title, dgettext("projects", "Project Settings"))
      |> assign(:current_path, current_path)

    {:noreply, socket}
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  def handle_event("create_snapshot", %{"snapshot" => params}, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      do_create_snapshot(socket, params)
    end)
  end

  def handle_event("restore_snapshot", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      do_restore_snapshot(socket, id)
    end)
  end

  def handle_event("delete_snapshot", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      do_delete_snapshot(socket, id)
    end)
  end

  def handle_event("clear_stale_lock", _params, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      case Projects.clear_stale_restoration_lock(socket.assigns.project.id) do
        {:ok, :cleared} ->
          {:noreply,
           socket
           |> assign(:restoration_in_progress, false)
           |> put_flash(:info, dgettext("projects", "Stale restoration lock cleared."))}

        {:error, :not_stale} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             dgettext("projects", "Lock is not stale yet. Please wait or let the restore finish.")
           )}
      end
    end)
  end

  # ===========================================================================
  # Handle Info (restoration events)
  # ===========================================================================

  @impl true
  def handle_info({:project_restoration_started, _payload}, socket) do
    {:noreply, assign(socket, :restoration_in_progress, true)}
  end

  @impl true
  def handle_info({:project_restoration_completed, payload}, socket) do
    project = socket.assigns.project

    {:noreply,
     socket
     |> assign(:restoration_in_progress, false)
     |> assign(:snapshots, Versioning.list_project_snapshots(project.id))
     |> assign(
       :can_create_snapshot,
       Billing.can_create_project_snapshot?(project.id, project.workspace_id) == :ok
     )
     |> put_flash(
       :info,
       dgettext(
         "projects",
         "Project restored. %{restored} entities restored, %{skipped} skipped.",
         restored: payload.restored,
         skipped: payload.skipped
       )
     )}
  end

  @impl true
  def handle_info({:project_restoration_failed, _payload}, socket) do
    {:noreply,
     socket
     |> assign(:restoration_in_progress, false)
     |> put_flash(
       :error,
       dgettext("projects", "Project restoration failed. Please try again.")
     )}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ===========================================================================
  # Private
  # ===========================================================================

  defp maybe_subscribe_restoration(socket, project_id) do
    if connected?(socket), do: Collaboration.subscribe_restoration(project_id)
    socket
  end

  defp restoration_in_progress?(project_id) do
    case Projects.restoration_in_progress?(project_id) do
      {true, _} -> true
      _ -> false
    end
  end
end
