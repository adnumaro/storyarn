defmodule StoryarnWeb.SettingsLive.WorkspacePlan do
  @moduledoc """
  Workspace › Plan & usage: the current plan and the limits every project in
  the workspace shares (projects, members, storage). Read-only; the page
  reserves the contact action for plan changes.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Commercial
  alias Storyarn.Workspaces
  alias StoryarnWeb.ProjectLive.Components.SettingsComponents

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
      storageBytes: SettingsComponents.serialize_storage_bucket(usage.storage_bytes),
      storage: SettingsComponents.serialize_storage_usage(usage.storage, usage.storage_bytes.limit)
    }
  end

  defp serialize_count_bucket(bucket) do
    %{used: bucket.used || 0, limit: bucket.limit}
  end
end
