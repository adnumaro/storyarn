defmodule StoryarnWeb.SettingsLive.WorkspaceUsage do
  @moduledoc """
  Workspace › Usage: the limits every project in the workspace shares
  (projects, storage) and how much of them it uses. The limits come from the
  workspace owner's plan, which the owner manages in Plan & billing.

  The owner, admins and members see it. Viewers and project-only members get
  no workspace totals.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Commercial
  alias Storyarn.Workspaces
  alias StoryarnWeb.Live.Shared.UsageAccess

  @impl true
  def mount(_params, _session, socket) do
    stale_workspace = socket.assigns.workspace

    case Workspaces.authorize(
           socket.assigns.current_scope,
           stale_workspace.id,
           :view_workspace_usage
         ) do
      {:ok, workspace, membership} ->
        {:ok,
         socket
         |> assign(:workspace, workspace)
         |> assign(:membership, membership)
         |> assign(:page_title, dgettext("workspaces", "Usage"))
         |> assign(:current_path, ~p"/users/settings/workspaces/#{workspace.slug}/usage")
         |> assign(:plan_path, UsageAccess.plan_path(socket.assigns.current_scope, workspace))
         |> assign(:usage, serialize_usage(Commercial.workspace_usage(workspace)))}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(
           :error,
           dgettext("workspaces", "You don't have permission to see this workspace's usage.")
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
      current_path={@current_path}
      settings_nav={@settings_nav}
    >
      <.vue
        v-component="live/workspace/settings/WorkspaceSettingsUsage"
        v-socket={@socket}
        v-inject="settings-layout"
        id="workspace-settings-usage"
        usage={@usage}
        plan-path={@plan_path}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  defp serialize_usage(usage) do
    %{
      projects: serialize_count_bucket(usage.projects),
      storageBytes: serialize_storage_bucket(usage.storage_bytes),
      storage: serialize_storage_usage(usage.storage, usage.storage_bytes.limit)
    }
  end

  defp serialize_count_bucket(bucket) do
    %{used: bucket.used || 0, limit: serialize_count_limit(bucket.limit)}
  end

  defp serialize_count_limit(:unlimited), do: "unlimited"
  defp serialize_count_limit(limit) when is_integer(limit) and limit >= 0, do: limit
  defp serialize_count_limit(_unknown_limit), do: nil

  # Workspace-owned copy of the storage serializers: the Project settings
  # components belong to another boundary, and the Usage page must not depend
  # on them (see `config/architecture_boundaries.exs`).
  defp serialize_storage_usage(storage, limit) do
    %{
      currentAssetsBytes: serialize_byte_count(storage.current_assets.bytes),
      assetTrashBytes: serialize_byte_count(storage.asset_trash.bytes),
      fullSnapshotsBytes: serialize_byte_count(storage.full_snapshots.bytes),
      activeReservationsBytes: serialize_byte_count(storage.active_reservations.bytes),
      totalAccountedBytes: serialize_byte_count(storage.accounted_bytes),
      limitBytes: serialized_storage_limit(limit),
      remainingBytes: remaining_storage_bytes(storage.accounted_bytes, limit),
      limitKind: storage_limit_kind(limit)
    }
  end

  defp serialize_storage_bucket(bucket) do
    %{used: serialize_byte_count(bucket.used), limit: serialized_storage_limit(bucket.limit)}
  end

  defp serialize_byte_count(value) when is_integer(value) and value >= 0, do: Integer.to_string(value)

  defp remaining_storage_bytes(used, limit) when is_integer(limit) and limit >= 0 do
    serialize_byte_count(max(limit - used, 0))
  end

  defp remaining_storage_bytes(_used, _limit), do: nil

  defp serialized_storage_limit(limit) when is_integer(limit) and limit >= 0, do: serialize_byte_count(limit)
  defp serialized_storage_limit(_limit), do: nil

  defp storage_limit_kind(limit) when is_integer(limit) and limit >= 0, do: "limited"
  defp storage_limit_kind(limit) when limit in [:unlimited, :infinity], do: "unlimited"
  defp storage_limit_kind(_limit), do: "unknown"
end
