defmodule StoryarnWeb.SettingsLive.Connections do
  @moduledoc """
  LiveView for connected accounts (OAuth providers).
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Accounts

  on_mount {StoryarnWeb.UserAuth, :require_sudo_mode}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    identities = Accounts.list_user_identities(user)

    socket =
      socket
      |> assign(:page_title, dgettext("settings", "Connected Accounts"))
      |> assign(:current_path, ~p"/users/settings/connections")
      |> assign(:identities, identities)
      |> assign(:has_password, !is_nil(user.hashed_password))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      flash={@flash}
      current_scope={@current_scope}
      workspaces={@workspaces}
      managed_workspace_slugs={@managed_workspace_slugs}
      current_path={@current_path}
    >
      <.vue
        v-component="modules/settings/Connections"
        v-socket={@socket}
        id="settings-connections-vue"
        identities={serialize_identities(@identities)}
        has-password={@has_password}
      />
    </Layouts.settings>
    """
  end

  defp serialize_identities(identities) do
    Enum.map(identities, fn identity ->
      %{
        provider: identity.provider,
        provider_email: identity.provider_email,
        provider_name: identity.provider_name
      }
    end)
  end


end
