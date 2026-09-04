defmodule StoryarnWeb.SettingsLive.AITeamOverview do
  @moduledoc """
  Read-only account overview of personal AI role selections by workspace.

  The overview includes every workspace visible to the actor, including
  project-only access, but only workspace-level members receive an edit link.

  Outside the sudo window the page mounts locked and loads nothing until the
  user confirms their password in place.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.AI
  alias StoryarnWeb.Live.Shared.SudoReauth
  alias StoryarnWeb.UserAuth

  on_mount {StoryarnWeb.Live.Hooks.RequireFeatureFlag, :ai_integrations}
  on_mount {UserAuth, :load_sudo_state}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, dgettext("integrations", "My AI Team"))
      |> assign(:current_path, ~p"/users/settings/ai-team")
      |> SudoReauth.assign_reauth(~p"/users/settings/ai-team")
      |> assign_overview()

    {:ok, socket}
  end

  @impl true
  def handle_event("confirm_access", params, socket) do
    SudoReauth.confirm(socket, params)
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
      sudo_grant={@sudo_grant}
    >
      <.vue
        v-component="live/account/settings/MyAITeamOverview"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-ai-team-overview-vue"
        workspaces={@overview.workspaces}
        sudo-active={@sudo_active}
        reauth={SudoReauth.reauth_props(@sudo_return_to, @sudo_handoff, @trigger_sudo_submit)}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  defp assign_overview(%{assigns: %{sudo_active: false}} = socket), do: assign(socket, :overview, %{workspaces: []})

  defp assign_overview(socket) do
    case AI.personal_preferences_overview(socket.assigns.current_scope) do
      {:ok, overview} ->
        assign(socket, :overview, with_edit_paths(overview, socket.assigns.sudo_grant))

      {:error, _reason} ->
        socket
        |> put_flash(:error, dgettext("integrations", "AI preferences are not available."))
        |> push_navigate(to: ~p"/users/settings/integrations")
    end
  end

  defp with_edit_paths(overview, sudo_grant) do
    workspaces =
      Enum.map(overview.workspaces, fn workspace ->
        edit_path =
          if workspace.can_configure do
            UserAuth.with_sudo_grant(
              ~p"/users/settings/ai-team/#{workspace.slug}",
              sudo_grant
            )
          end

        Map.put(workspace, :edit_path, edit_path)
      end)

    Map.put(overview, :workspaces, workspaces)
  end
end
