defmodule StoryarnWeb.SettingsLive.WorkspacePlan do
  @moduledoc """
  Workspace › Plan & usage: the current plan and the limits every project in
  the workspace shares (projects, members, storage). Read-only; the page
  reserves the contact action for plan changes.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Commercial
  alias Storyarn.Workspaces

  @impl true
  def mount(_params, _session, socket) do
    stale_workspace = socket.assigns.workspace

    case Workspaces.authorize(
           socket.assigns.current_scope,
           stale_workspace.id,
           :access_workspace_settings
         ) do
      {:ok, workspace, membership} ->
        {:ok,
         socket
         |> assign(:workspace, workspace)
         |> assign(:membership, membership)
         |> assign(:page_title, dgettext("workspaces", "Plan & usage"))
         |> assign(:current_path, ~p"/users/settings/workspaces/#{workspace.slug}/plan")
         |> assign(:usage, serialize_usage(Commercial.workspace_usage(workspace)))}

      {:error, _reason} ->
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
      current_path={@current_path}
      settings_nav={@settings_nav}
    >
      <.vue
        v-component="live/workspace/settings/WorkspaceSettingsPlan"
        v-socket={@socket}
        v-inject="settings-layout"
        id="workspace-settings-plan"
        usage={@usage}
        contact-path={~p"/contact"}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  defp serialize_usage(usage) do
    %{
      plan: %{key: to_string(usage.plan)},
      projects: serialize_count_bucket(usage.projects),
      members: serialize_count_bucket(usage.members),
      storageBytes: serialize_storage_bucket(usage.storage_bytes),
      storage: serialize_storage_usage(usage.storage, usage.storage_bytes.limit)
    }
  end

  defp serialize_count_bucket(bucket) do
    %{used: bucket.used || 0, limit: bucket.limit}
  end

  # Workspace-owned copy of the storage serializers: the Project settings
  # components belong to another boundary, and the Plan page must not depend
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
