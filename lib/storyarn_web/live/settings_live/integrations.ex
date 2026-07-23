defmodule StoryarnWeb.SettingsLive.Integrations do
  @moduledoc """
  LiveView for the "AI Integrations" account settings page.

  Renders one card per known provider and lets the user connect or disconnect.
  Gated by the `:ai_integrations` feature flag — direct URL access without the
  flag redirects to settings home (see `RequireFeatureFlag` hook).

  Credential mutation is sudo-protected at mount and rechecked for every
  connect/disconnect event so a long-lived LiveView cannot outlive elevation.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.AI
  alias Storyarn.RateLimiter
  alias StoryarnWeb.UserAuth

  on_mount {StoryarnWeb.Live.Hooks.RequireFeatureFlag, :ai_integrations}
  on_mount {UserAuth, {:require_sudo_mode, __MODULE__}}

  def sudo_return_to(_params, _live_action), do: ~p"/users/settings/integrations"

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, dgettext("integrations", "AI Integrations"))
      |> assign(:current_path, ~p"/users/settings/integrations")
      |> assign_cards()

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
        v-component="live/account/settings/AccountSettingsIntegrations"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-integrations-vue"
        cards={@cards}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  @impl true
  def handle_event("connect", %{"provider" => provider, "api_key" => api_key}, socket) do
    with_sudo(socket, fn socket -> connect(socket, provider, api_key) end)
  end

  def handle_event("disconnect", %{"provider" => provider}, socket) do
    with_sudo(socket, fn socket -> disconnect(socket, provider) end)
  end

  defp connect(socket, provider, api_key) do
    user = socket.assigns.current_scope.user

    with :ok <- RateLimiter.check_ai_integration_connect(user.id),
         {:ok, _integration} <- AI.connect(user, provider, trim(api_key)) do
      {:reply, %{status: "ok"}, assign_cards(socket)}
    else
      {:error, :rate_limited} ->
        {:reply, error_reply("rate_limited"), socket}

      {:error, :already_connected} ->
        {:reply, error_reply("already_connected"), socket}

      {:error, :unknown_provider} ->
        {:reply, error_reply("unknown_provider"), socket}

      {:error, :invalid_key} ->
        {:reply, error_reply("invalid_key"), socket}

      {:error, :network_error} ->
        {:reply, error_reply("network_error"), socket}

      {:error, :provider_error} ->
        {:reply, error_reply("provider_error"), socket}

      {:error, %Ecto.Changeset{}} ->
        {:reply, error_reply("invalid_data"), socket}

      {:error, {:unexpected_status, _status}} ->
        {:reply, error_reply("provider_error"), socket}
    end
  end

  defp disconnect(socket, provider) do
    user = socket.assigns.current_scope.user

    case AI.get_active(user, provider) do
      nil ->
        {:reply, error_reply("not_connected"), socket}

      integration ->
        case AI.revoke(socket.assigns.current_scope.user, integration) do
          # Concurrent revoke means the end state the user wanted is already
          # in place — treat it as success.
          {:ok, _revoked} -> {:reply, %{status: "ok"}, assign_cards(socket)}
          {:error, :already_revoked} -> {:reply, %{status: "ok"}, assign_cards(socket)}
          {:error, %Ecto.Changeset{}} -> {:reply, error_reply("invalid_data"), socket}
        end
    end
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
        {:noreply,
         push_navigate(socket,
           to: UserAuth.sudo_confirmation_path(~p"/users/settings/integrations")
         )}
    end
  end

  defp assign_cards(socket) do
    user = socket.assigns.current_scope.user

    integrations_by_provider =
      user
      |> AI.list_active()
      |> Map.new(fn integration -> {integration.provider, integration} end)

    cards =
      Enum.map(AI.provider_metadata(), fn metadata ->
        integration = Map.get(integrations_by_provider, Atom.to_string(metadata.id))
        build_card(metadata, integration)
      end)

    assign(socket, :cards, cards)
  end

  defp build_card(metadata, nil) do
    %{
      provider: metadata.id,
      name: metadata.name,
      key_generation_url: metadata.key_generation_url,
      docs_url: metadata.docs_url,
      key_placeholder: metadata.key_placeholder,
      status: "not_connected",
      account_email: nil,
      account_display_name: nil,
      key_last_four: nil,
      connected_at: nil
    }
  end

  defp build_card(metadata, %{} = integration) do
    %{
      provider: metadata.id,
      name: metadata.name,
      key_generation_url: metadata.key_generation_url,
      docs_url: metadata.docs_url,
      key_placeholder: metadata.key_placeholder,
      status: "connected",
      account_email: integration.account_email,
      account_display_name: integration.account_display_name,
      key_last_four: integration.key_last_four,
      connected_at: integration.connected_at
    }
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(_value), do: ""

  defp error_reply(code), do: %{status: "error", error: code}
end
