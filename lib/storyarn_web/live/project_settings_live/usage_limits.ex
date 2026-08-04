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

  defp serialize_storage_usage(storage, limit) do
    %{
      currentAssetsBytes: serialize_byte_count(storage.current_assets.bytes),
      fullSnapshotsBytes: serialize_byte_count(storage.full_snapshots.bytes),
      linkedSnapshotsBytes: serialize_byte_count(storage.linked_snapshots.bytes),
      activeReservationsBytes: serialize_byte_count(storage.active_reservations.bytes),
      totalAccountedBytes: serialize_byte_count(storage.accounted_bytes),
      limitBytes: serialized_storage_limit(limit),
      remainingBytes: remaining_bytes(storage.accounted_bytes, limit),
      limitKind: limit_kind(limit)
    }
  end

  defp remaining_bytes(used, limit) when is_integer(limit) and limit >= 0, do: serialize_byte_count(max(limit - used, 0))

  defp remaining_bytes(_used, _limit), do: nil

  defp limit_kind(limit) when is_integer(limit) and limit >= 0, do: "limited"
  defp limit_kind(limit) when limit in [:unlimited, :infinity], do: "unlimited"
  defp limit_kind(_limit), do: "unknown"

  defp serialized_storage_limit(limit) when is_integer(limit) and limit >= 0, do: serialize_byte_count(limit)

  defp serialized_storage_limit(_limit), do: nil

  defp serialize_storage_bucket(bucket) do
    %{
      used: serialize_byte_count(bucket.used),
      limit: serialized_storage_limit(bucket.limit)
    }
  end

  defp serialize_bucket(bucket) do
    %{
      used: bucket.used,
      limit: bucket.limit
    }
  end

  defp serialize_byte_count(value) when is_integer(value) and value >= 0, do: Integer.to_string(value)

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
