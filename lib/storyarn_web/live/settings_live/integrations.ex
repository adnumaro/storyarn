defmodule StoryarnWeb.SettingsLive.Integrations do
  @moduledoc """
  LiveView for the "AI Integrations" account settings page.

  Renders one card per known provider and lets the user connect or disconnect.
  Gated by the `:ai_integrations` feature flag — direct URL access without the
  flag redirects to settings home (see `RequireFeatureFlag` hook).

  ## Follow-up

    * Slice 6 — wrap in `require_sudo_mode` for stronger auth. Not enabled in
      v1 because the feature is beta-flagged and we want low-friction testing.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.AI
  alias Storyarn.RateLimiter

  on_mount {StoryarnWeb.Live.Hooks.RequireFeatureFlag, :ai_integrations}

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

  def handle_event("disconnect", %{"provider" => provider}, socket) do
    user = socket.assigns.current_scope.user

    case AI.get_active(user, provider) do
      nil ->
        {:reply, error_reply("not_connected"), socket}

      integration ->
        case AI.revoke(integration) do
          # Concurrent revoke means the end state the user wanted is already
          # in place — treat it as success.
          {:ok, _revoked} -> {:reply, %{status: "ok"}, assign_cards(socket)}
          {:error, :already_revoked} -> {:reply, %{status: "ok"}, assign_cards(socket)}
        end
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
