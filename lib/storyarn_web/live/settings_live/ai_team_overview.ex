defmodule StoryarnWeb.SettingsLive.AITeamOverview do
  @moduledoc """
  Read-only account overview of personal AI role selections by workspace.

  The overview includes every workspace visible to the actor, including
  project-only access, but only workspace-level members receive an edit link.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.AI
  alias StoryarnWeb.UserAuth

  on_mount {StoryarnWeb.Live.Hooks.RequireFeatureFlag, :ai_integrations}
  on_mount {UserAuth, {:require_sudo_mode, __MODULE__}}

  def sudo_return_to(_params, _live_action), do: ~p"/users/settings/ai-team"

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, dgettext("integrations", "My AI Team"))
      |> assign(:current_path, ~p"/users/settings/ai-team")
      |> assign_overview()

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
      managed_workspace_slugs={@managed_workspace_slugs}
      general_workspace_slugs={@general_workspace_slugs}
      current_path={@current_path}
      sudo_grant={@sudo_grant}
    >
      <.vue
        v-component="live/account/settings/MyAITeamOverview"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-ai-team-overview-vue"
        workspaces={@overview.workspaces}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

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
