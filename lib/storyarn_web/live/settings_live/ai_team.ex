defmodule StoryarnWeb.SettingsLive.AITeam do
  @moduledoc """
  Workspace-scoped personal provider/model preferences ("My AI Team").

  This route stays inside the existing authenticated app live_session. Its
  module hooks add the actor-targeted AI flag and recent-authentication gate;
  the shared WorkspaceScope hook loads only a workspace visible to the actor.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.AI
  alias StoryarnWeb.UserAuth

  on_mount {StoryarnWeb.Live.Hooks.RequireFeatureFlag, :ai_integrations}
  on_mount {UserAuth, {:require_sudo_mode, __MODULE__}}

  def sudo_return_to(%{"slug" => slug}, _live_action), do: ~p"/users/settings/ai-team/#{slug}"

  @impl true
  def mount(_params, _session, %{assigns: %{membership: %{role: nil}}} = socket) do
    {:ok, redirect_to_overview(socket)}
  end

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, dgettext("integrations", "My AI Team"))
      |> assign(:current_path, ~p"/users/settings/ai-team/#{socket.assigns.workspace.slug}")
      |> assign(:providers_path, providers_path(socket))
      |> assign(:overview_path, overview_path(socket))
      |> assign_preferences()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      workspaces={@workspaces}
      workspace={@workspace}
      managed_workspace_slugs={@managed_workspace_slugs}
      general_workspace_slugs={@general_workspace_slugs}
      current_path={@current_path}
      sudo_grant={@sudo_grant}
    >
      <.vue
        v-component="live/account/settings/MyAITeam"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-ai-team-vue"
        workspace={@preference_summary.workspace}
        policy-allowed={@preference_summary.policy_allowed}
        slots={@preference_summary.slots}
        providers-path={@providers_path}
        overview-path={@overview_path}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  @impl true
  def handle_event("save_preference", params, socket) do
    with_sudo(socket, fn socket ->
      with {:ok, integration_id} <- positive_integer(params["integration_id"]),
           slot when is_binary(slot) <- params["slot"],
           model when is_binary(model) <- params["model"],
           {:ok, _preference} <-
             AI.put_personal_preference(
               socket.assigns.current_scope,
               socket.assigns.workspace.id,
               slot,
               integration_id,
               model
             ) do
        {:reply, %{status: "ok"}, assign_preferences(socket)}
      else
        {:error, reason} -> {:reply, error_reply(reason), socket}
        _invalid -> {:reply, error_reply(:invalid_data), socket}
      end
    end)
  end

  def handle_event("delete_preference", %{"slot" => slot}, socket) when is_binary(slot) do
    with_sudo(socket, fn socket ->
      case AI.delete_personal_preference(
             socket.assigns.current_scope,
             socket.assigns.workspace.id,
             slot
           ) do
        {:ok, _preference} ->
          {:reply, %{status: "ok"}, assign_preferences(socket)}

        {:error, reason} ->
          {:reply, error_reply(reason), socket}
      end
    end)
  end

  def handle_event("delete_preference", _params, socket), do: {:reply, error_reply(:invalid_data), socket}

  defp assign_preferences(socket) do
    case AI.personal_preferences(
           socket.assigns.current_scope,
           socket.assigns.workspace.id
         ) do
      {:ok, summary} ->
        assign(socket, :preference_summary, summary)

      {:error, _reason} ->
        socket
        |> put_flash(:error, dgettext("integrations", "AI preferences are not available."))
        |> push_navigate(to: overview_path(socket))
    end
  end

  defp providers_path(socket) do
    UserAuth.with_sudo_grant(
      ~p"/users/settings/integrations",
      socket.assigns.sudo_grant
    )
  end

  defp overview_path(socket) do
    UserAuth.with_sudo_grant(
      ~p"/users/settings/ai-team",
      socket.assigns.sudo_grant
    )
  end

  defp redirect_to_overview(socket) do
    socket
    |> put_flash(
      :error,
      dgettext(
        "integrations",
        "Workspace-level access is required to configure this AI team."
      )
    )
    |> push_navigate(to: overview_path(socket))
  end

  defp with_sudo(socket, fun) do
    case UserAuth.authorize_sudo(
           socket.assigns.current_scope.user,
           socket.assigns.sudo_session_token,
           socket.assigns.sudo_grant
         ) do
      {:ok, _grant} ->
        fun.(socket)

      :error ->
        return_to = ~p"/users/settings/ai-team/#{socket.assigns.workspace.slug}"

        {:noreply,
         push_navigate(socket,
           to: UserAuth.sudo_confirmation_path(return_to)
         )}
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _invalid -> {:error, :invalid_data}
    end
  end

  defp positive_integer(_value), do: {:error, :invalid_data}

  defp error_reply(reason), do: %{status: "error", error: error_code(reason)}

  defp error_code(:feature_disabled), do: "feature_disabled"
  defp error_code(:workspace_unavailable), do: "workspace_unavailable"
  defp error_code(:workspace_policy_disabled), do: "workspace_policy_disabled"
  defp error_code(:integration_unavailable), do: "integration_unavailable"
  defp error_code(:assignment_required), do: "assignment_required"
  defp error_code(:model_unavailable), do: "model_unavailable"
  defp error_code(:model_deprecated), do: "model_deprecated"
  defp error_code(:capability_mismatch), do: "capability_mismatch"
  defp error_code(:invalid_preference_slot), do: "invalid_preference_slot"
  defp error_code(:preference_not_found), do: "preference_not_found"
  defp error_code(:invalid_data), do: "invalid_data"
  defp error_code(%Ecto.Changeset{}), do: "invalid_data"
  defp error_code(_unknown), do: "unknown_error"
end
