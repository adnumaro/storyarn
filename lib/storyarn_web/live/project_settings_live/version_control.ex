defmodule StoryarnWeb.ProjectSettingsLive.VersionControl do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Commercial
  alias Storyarn.Projects
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Helpers.SaveStatusTimer

  # ===========================================================================
  # Render
  # ===========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      current_path={@current_path}
      settings_nav={@settings_nav}
    >
      <.vue
        v-component="live/project/settings/ProjectSettingsVersionControl"
        v-socket={@socket}
        v-inject="settings-layout"
        id="project-settings-version-control"
        auto-version-flows={version_control_value(@version_control_form, :auto_version_flows)}
        auto-version-scenes={version_control_value(@version_control_form, :auto_version_scenes)}
        auto-version-sheets={version_control_value(@version_control_form, :auto_version_sheets)}
        version-usage={serialize_version_usage(@version_usage)}
        usage-path={
          ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/settings/usage-limits"
        }
        save-status={Atom.to_string(@save_status)}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  # ===========================================================================
  # Serialization helpers
  # ===========================================================================

  defp version_control_value(nil, _field), do: false

  defp version_control_value(form, field) do
    case form[field] do
      %{value: val} -> val == true || val == "true"
      _ -> false
    end
  end

  defp serialize_version_usage(nil), do: nil

  defp serialize_version_usage(usage) do
    %{
      projectSnapshots: %{
        used: usage.project_snapshots.used,
        limit: usage.project_snapshots.limit
      },
      namedVersions: %{
        used: usage.named_versions.used,
        limit: usage.named_versions.limit
      }
    }
  end

  # ===========================================================================
  # Mount & handle_params
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    stale_project = socket.assigns.project

    if connected?(socket) do
      :ok = Projects.subscribe_project_ownership_changes(stale_project.id)
    end

    case reload_project_owner(socket, stale_project.id) do
      {:ok, project, membership} ->
        socket =
          socket
          |> assign(:project, project)
          |> assign(:membership, membership)
          |> assign(:current_workspace, project.workspace)
          |> assign(
            :version_control_form,
            to_form(version_control_changeset(project), as: "version_control")
          )
          |> assign(:version_usage, Commercial.project_usage(project.id, project.workspace_id))
          |> assign(:save_status, :idle)

        {:ok, socket}

      _lost_access ->
        mount_access_denied(socket, stale_project)
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
  def handle_event("save_version_control", %{"version_control" => params}, socket) do
    Authorize.with_authorization(
      socket,
      :manage_project,
      fn socket ->
        attrs = %{
          auto_version_flows: params["auto_version_flows"] == "true",
          auto_version_scenes: params["auto_version_scenes"] == "true",
          auto_version_sheets: params["auto_version_sheets"] == "true"
        }

        case Projects.update_project(
               socket.assigns.current_scope,
               socket.assigns.project.id,
               attrs
             ) do
          {:ok, project} ->
            track_version_control_settings(socket, project, attrs)

            {:noreply,
             socket
             |> assign(:project, project)
             |> assign(
               :version_control_form,
               to_form(version_control_changeset(project), as: "version_control")
             )
             |> SaveStatusTimer.mark_saved()}

          {:error, :unauthorized} ->
            project_access_lost(socket)

          {:error, :not_found} ->
            project_access_lost(socket)

          {:error, :ownership_invariant_violation} ->
            ownership_invariant_error(socket)

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to save settings."))}
        end
      end,
      fn
        socket, :ownership_invariant_violation ->
          ownership_invariant_error(socket)

        socket, _reason ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("You don't have permission to perform this action.")
           )}
      end
    )
  end

  defp track_version_control_settings(socket, project, attrs) do
    Projects.version_control_settings_updated(socket.assigns.current_scope, project, attrs)
  end

  @impl true
  def handle_info({:reset_save_status, token}, socket) do
    if socket.assigns[:save_status_reset_token] == token do
      {:noreply, assign(socket, :save_status, :idle)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:project_ownership_transferred, %{project_id: project_id}},
        %{assigns: %{project: %{id: project_id}}} = socket
      ) do
    with {:ok, project, membership} <-
           Projects.reload_project(socket.assigns.current_scope, project_id),
         true <- project.owner_id == socket.assigns.current_scope.user.id,
         true <- Projects.can?(membership.role, :manage_project) do
      {:noreply,
       socket
       |> assign(:project, project)
       |> assign(:membership, membership)
       |> assign(:current_workspace, project.workspace)
       |> assign(
         :version_control_form,
         to_form(version_control_changeset(project), as: "version_control")
       )
       |> assign(:version_usage, Commercial.project_usage(project.id, project.workspace_id))}
    else
      _lost_access ->
        project_access_lost(socket)
    end
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp reload_project_owner(socket, project_id) do
    with {:ok, project, membership} <-
           Projects.reload_project(socket.assigns.current_scope, project_id),
         true <- project.owner_id == socket.assigns.current_scope.user.id,
         true <- Projects.can?(membership.role, :manage_project) do
      {:ok, project, membership}
    else
      _lost_access -> {:error, :unauthorized}
    end
  end

  defp mount_access_denied(socket, project) do
    {:ok,
     socket
     |> put_flash(
       :error,
       dgettext("projects", "You don't have permission to manage this project.")
     )
     |> redirect(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")}
  end

  defp project_access_lost(socket) do
    project = socket.assigns.project

    {:noreply,
     socket
     |> put_flash(
       :error,
       dgettext("projects", "You don't have permission to manage this project.")
     )
     |> push_navigate(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")}
  end

  defp ownership_invariant_error(socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       dgettext(
         "projects",
         "Version control settings could not be saved because project ownership is inconsistent."
       )
     )}
  end

  defp version_control_changeset(project) do
    types = %{
      auto_version_flows: :boolean,
      auto_version_scenes: :boolean,
      auto_version_sheets: :boolean
    }

    data = %{
      auto_version_flows: project.auto_version_flows,
      auto_version_scenes: project.auto_version_scenes,
      auto_version_sheets: project.auto_version_sheets
    }

    Ecto.Changeset.cast({data, types}, %{}, Map.keys(types))
  end
end
