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
      <:title>{dgettext("settings", "Connected Accounts")}</:title>
      <:subtitle>{dgettext("settings", "Link your social accounts for easier sign-in")}</:subtitle>

      <.vue
        v-component="settings/Connections"
        v-socket={@socket}
        id="settings-connections-vue"
        identities={serialize_identities(@identities)}
        has-password={@has_password}
        translations={connections_translations()}
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

  defp connections_translations do
    %{
      notConnected: dgettext("settings", "Not connected"),
      unlink: dgettext("settings", "Unlink"),
      connect: dgettext("settings", "Connect"),
      connected: dgettext("settings", "Connected"),
      setPasswordFirst: dgettext("settings", "Set a password before unlinking"),
      unlinkTitle: dgettext("settings", "Unlink account?"),
      unlinkMessage: dgettext("settings", "Are you sure you want to unlink this account?"),
      cancel: gettext("Cancel"),
      whyConnect: dgettext("settings", "Why connect accounts?"),
      reasons: [
        dgettext("settings", "Sign in faster without typing your password"),
        dgettext("settings", "Access your account even if you forget your password"),
        dgettext("settings", "Keep your account secure with multiple authentication methods")
      ]
    }
  end
end
