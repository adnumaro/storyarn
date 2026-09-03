defmodule StoryarnWeb.SettingsLive.WorkspaceAI do
  @moduledoc """
  Workspace › AI: the Storyarn AI allowance policy and whether members may use
  their own provider keys. Both switches are owner-only; admins and members
  can read the state.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.AI
  alias Storyarn.Platform.FeatureFlags
  alias Storyarn.Workspaces
  alias StoryarnWeb.Live.Hooks.SettingsNav

  @impl true
  def mount(_params, _session, socket) do
    stale_workspace = socket.assigns.workspace

    if connected?(socket) do
      :ok = Workspaces.subscribe_workspace_ownership_changes(stale_workspace.id)
    end

    case Workspaces.authorize(
           socket.assigns.current_scope,
           stale_workspace.id,
           :access_workspace_general_settings
         ) do
      {:ok, workspace, membership} ->
        {:ok,
         socket
         |> assign(:workspace, workspace)
         |> assign(:membership, membership)
         |> assign(:page_title, dgettext("workspaces", "Workspace AI"))
         |> assign(:current_path, ~p"/users/settings/workspaces/#{workspace.slug}/ai")
         |> assign_ai_settings()}

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
        v-component="live/workspace/settings/WorkspaceSettingsAI"
        v-socket={@socket}
        v-inject="settings-layout"
        id="workspace-settings-ai"
        is-owner={@workspace.owner_id == @current_scope.user.id}
        ai={serialize_ai_settings(assigns)}
        integrations-path={~p"/users/settings/integrations"}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  @impl true
  def handle_event("update_managed_ai_policy", %{"enabled" => enabled}, socket) when is_boolean(enabled) do
    if FeatureFlags.enabled?(:ai_integrations, for: socket.assigns.current_scope.user) do
      update_managed_ai_policy(socket, enabled)
    else
      {:noreply, put_flash(socket, :error, dgettext("workspaces", "Storyarn AI policy could not be updated."))}
    end
  end

  def handle_event("update_managed_ai_policy", _params, socket) do
    {:noreply, put_flash(socket, :error, dgettext("workspaces", "Storyarn AI policy could not be updated."))}
  end

  def handle_event("update_personal_ai_members_policy", %{"enabled" => enabled}, socket) when is_boolean(enabled) do
    if FeatureFlags.enabled?(:ai_integrations, for: socket.assigns.current_scope.user) do
      update_personal_ai_members_policy(socket, enabled)
    else
      {:noreply, put_flash(socket, :error, dgettext("workspaces", "Personal AI member policy could not be updated."))}
    end
  end

  def handle_event("update_personal_ai_members_policy", _params, socket) do
    {:noreply, put_flash(socket, :error, dgettext("workspaces", "Personal AI member policy could not be updated."))}
  end

  @impl true
  def handle_info(
        {:workspace_ownership_transferred, %{workspace_id: workspace_id}},
        %{assigns: %{workspace: %{id: workspace_id}}} = socket
      ) do
    case Workspaces.authorize(
           socket.assigns.current_scope,
           workspace_id,
           :access_workspace_general_settings
         ) do
      {:ok, workspace, membership} ->
        socket =
          socket
          |> assign(:workspace, workspace)
          |> assign(:membership, membership)
          |> assign_ai_settings()

        {:noreply, assign(socket, :settings_nav, SettingsNav.build_nav(socket.assigns))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("workspaces", "You don't have permission to manage this workspace.")
         )
         |> push_navigate(to: ~p"/users/settings")}
    end
  end

  defp assign_ai_settings(socket) do
    user = socket.assigns.current_scope.user
    visible? = FeatureFlags.enabled?(:ai_integrations, for: user)

    if visible? do
      {:ok, policy} = AI.get_workspace_policy(socket.assigns.current_scope, socket.assigns.workspace.id)
      {:ok, allowance} = AI.allowance_summary(socket.assigns.current_scope, socket.assigns.workspace.id)

      socket
      |> assign(:ai_visible, true)
      |> assign(:ai_policy_lanes, policy.allowed_lanes)
      |> assign(:ai_managed_allowed, "managed" in policy.allowed_lanes)
      |> assign(:ai_personal_members_allowed, "personal_byok" in policy.allowed_lanes)
      |> assign(:ai_allowance, allowance)
      |> assign(:ai_provenance, AI.managed_provenance())
    else
      socket
      |> assign(:ai_visible, false)
      |> assign(:ai_policy_lanes, [])
      |> assign(:ai_managed_allowed, false)
      |> assign(:ai_personal_members_allowed, false)
      |> assign(:ai_allowance, %{})
      |> assign(:ai_provenance, nil)
    end
  end

  defp update_personal_ai_members_policy(socket, enabled) do
    lanes = toggle_lane(current_lanes(socket), "personal_byok", enabled)

    case AI.update_workspace_policy(socket.assigns.current_scope, socket.assigns.workspace.id, lanes) do
      {:ok, _policy} ->
        {:noreply,
         socket
         |> assign_ai_settings()
         |> put_flash(:info, dgettext("workspaces", "Personal AI member policy updated."))}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("workspaces", "Only the workspace owner can change Personal AI member policy.")
         )}

      {:error, :ownership_invariant_violation} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext(
             "workspaces",
             "Personal AI member policy could not be updated because workspace ownership is inconsistent. Contact support before retrying."
           )
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Personal AI member policy could not be updated."))}
    end
  end

  # Two owner sessions toggling different switches must not clobber each
  # other: the lane list is rebuilt from the policy as stored right now, not
  # from the lanes this page rendered.
  defp current_lanes(socket) do
    case AI.get_workspace_policy(socket.assigns.current_scope, socket.assigns.workspace.id) do
      {:ok, policy} -> policy.allowed_lanes
      {:error, _reason} -> socket.assigns.ai_policy_lanes
    end
  end

  defp toggle_lane(lanes, lane, true), do: Enum.uniq([lane | lanes])
  defp toggle_lane(lanes, lane, false), do: List.delete(lanes, lane)

  defp update_managed_ai_policy(socket, enabled) do
    lanes = toggle_lane(current_lanes(socket), "managed", enabled)

    case AI.update_workspace_policy(socket.assigns.current_scope, socket.assigns.workspace.id, lanes) do
      {:ok, _policy} ->
        {:noreply,
         socket
         |> assign_ai_settings()
         |> put_flash(:info, dgettext("workspaces", "Storyarn AI policy updated."))}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("workspaces", "Only the workspace owner can change Storyarn AI policy."))}

      {:error, :ownership_invariant_violation} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext(
             "workspaces",
             "Storyarn AI policy could not be updated because workspace ownership is inconsistent. Contact support before retrying."
           )
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Storyarn AI policy could not be updated."))}
    end
  end

  defp serialize_ai_allowance(%{} = allowance) do
    %{
      status: Map.get(allowance, :status),
      availableUnits: Map.get(allowance, :available_units, 0),
      reservedUnits: Map.get(allowance, :reserved_units, 0),
      committedUnits: Map.get(allowance, :committed_units, 0)
    }
  end

  defp serialize_ai_provenance(%{} = provenance) do
    %{
      provider: Map.get(provenance, :provider),
      model: Map.get(provenance, :model),
      region: Map.get(provenance, :region),
      dataRetention: Map.get(provenance, :data_retention),
      trainingUsage: Map.get(provenance, :training_usage)
    }
  end

  defp serialize_ai_provenance(nil), do: nil

  defp serialize_ai_settings(assigns) do
    %{
      visible: assigns.ai_visible,
      managedAllowed: assigns.ai_managed_allowed,
      personalMembersAllowed: assigns.ai_personal_members_allowed,
      allowance: serialize_ai_allowance(assigns.ai_allowance),
      provenance: serialize_ai_provenance(assigns.ai_provenance)
    }
  end
end
