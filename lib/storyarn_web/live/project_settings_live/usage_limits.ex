defmodule StoryarnWeb.ProjectSettingsLive.UsageLimits do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents,
    only: [serialize_byte_count: 1, serialize_storage_bucket: 1, serialize_storage_usage: 2]

  alias Storyarn.Commercial
  alias Storyarn.Projects

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
        v-component="live/project/settings/ProjectSettingsUsageLimits"
        v-socket={@socket}
        v-inject="settings-layout"
        id="project-settings-usage-limits"
        usage-limits={serialize_usage_limits(@usage_limits)}
        workspace-plan-path={~p"/users/settings/workspaces/#{@workspace.slug}/plan"}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  # ===========================================================================
  # Serialization helpers
  # ===========================================================================

  defp serialize_usage_limits(usage) do
    %{
      plan: %{
        key: usage.plan.key,
        name: usage.plan.name
      },
      project: %{
        items: serialize_bucket(usage.project.items),
        projectSnapshots: serialize_bucket(usage.project.project_snapshots),
        namedVersions: serialize_bucket(usage.project.named_versions)
      },
      workspace: %{
        projects: serialize_bucket(usage.workspace.projects),
        members: serialize_bucket(usage.workspace.members),
        storageBytes: serialize_storage_bucket(usage.workspace.storage_bytes)
      },
      itemBreakdown: %{
        sheets: usage.item_breakdown.sheets,
        flows: usage.item_breakdown.flows,
        scenes: usage.item_breakdown.scenes,
        flowNodes: usage.item_breakdown.flow_nodes
      },
      storage: %{
        projectAccountedBytes: serialize_byte_count(usage.storage.project_bytes),
        projectAssetBytes: serialize_byte_count(usage.storage.project_asset_bytes),
        projectSnapshotBytes: serialize_byte_count(usage.storage.project_snapshot_bytes),
        projectReservationBytes: serialize_byte_count(usage.storage.project_reservation_bytes),
        assetCount: usage.storage.asset_count,
        workspace:
          serialize_storage_usage(
            usage.storage.workspace,
            usage.workspace.storage_bytes.limit
          )
      }
    }
  end

  defp serialize_bucket(bucket) do
    %{
      used: bucket.used,
      limit: bucket.limit
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
          |> assign(:usage_limits, Commercial.project_limits_usage(project))

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

  @impl true
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
       |> assign(:usage_limits, Commercial.project_limits_usage(project))}
    else
      _lost_access ->
        project = socket.assigns.project

        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("projects", "You don't have permission to manage this project.")
         )
         |> push_navigate(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")}
    end
  end

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
end
