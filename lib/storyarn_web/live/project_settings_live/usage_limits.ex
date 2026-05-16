defmodule StoryarnWeb.ProjectSettingsLive.UsageLimits do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Billing
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
      workspace={@workspace}
      project={@project}
    >
      <:title>{dgettext("projects", "Usage Limits")}</:title>
      <:subtitle>
        {dgettext("projects", "Review project and workspace usage against plan limits")}
      </:subtitle>

      <.vue
        v-component="live/project/settings/ProjectSettingsUsageLimits"
        v-socket={@socket}
        v-inject="settings-layout"
        id="project-settings-usage-limits"
        usage-limits={serialize_usage_limits(@usage_limits)}
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
        storageBytes: serialize_bucket(usage.workspace.storage_bytes)
      },
      itemBreakdown: %{
        sheets: usage.item_breakdown.sheets,
        flows: usage.item_breakdown.flows,
        scenes: usage.item_breakdown.scenes,
        flowNodes: usage.item_breakdown.flow_nodes
      },
      storage: %{
        projectBytes: usage.storage.project_bytes,
        assetCount: usage.storage.asset_count
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
    %{project: project, membership: membership} = socket.assigns

    if Projects.can?(membership.role, :manage_project) do
      socket =
        socket
        |> assign(:current_workspace, project.workspace)
        |> assign(:usage_limits, Billing.project_limits_usage(project))

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
end
