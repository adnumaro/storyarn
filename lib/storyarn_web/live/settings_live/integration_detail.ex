defmodule StoryarnWeb.SettingsLive.IntegrationDetail do
  @moduledoc """
  Sensitive configuration surface for one personal AI provider.

  The provider comes from the validated route, and every mutation reloads the
  actor-owned active integration server-side. Client-supplied provider or
  integration identifiers are never used as authorization inputs.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.AI
  alias Storyarn.RateLimiter
  alias StoryarnWeb.SettingsLive.Sudo
  alias StoryarnWeb.UserAuth

  on_mount {StoryarnWeb.Live.Hooks.RequireFeatureFlag, :ai_integrations}
  on_mount {UserAuth, {:require_sudo_mode, __MODULE__}}

  def sudo_return_to(%{"provider" => provider}, _live_action), do: ~p"/users/settings/integrations/#{provider}"

  @impl true
  def mount(%{"provider" => provider}, _session, socket) do
    case provider_metadata(provider) do
      {:ok, metadata} ->
        socket =
          socket
          |> assign(:page_title, metadata.name)
          |> assign(:current_path, ~p"/users/settings/integrations")
          |> assign(:provider, provider)
          |> assign(:metadata, metadata)
          |> assign(:providers_path, providers_path(socket))
          |> assign_detail()

        {:ok, socket}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("integrations", "AI provider not found."))
         |> push_navigate(to: ~p"/users/settings/integrations")}
    end
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
        v-component="live/account/settings/ProviderIntegrationDetail"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-integration-detail-vue"
        card={@card}
        providers-path={@providers_path}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  @impl true
  def handle_event("connect", %{"api_key" => api_key}, socket) do
    with_sudo(socket, &connect(&1, api_key))
  end

  def handle_event("connect", _params, socket), do: {:reply, error_reply(:invalid_data), socket}

  def handle_event("replace_key", %{"api_key" => api_key}, socket) do
    with_sudo(socket, &replace_key(&1, api_key))
  end

  def handle_event("replace_key", _params, socket), do: {:reply, error_reply(:invalid_data), socket}

  def handle_event("revalidate", _params, socket) do
    with_sudo(socket, &revalidate(&1))
  end

  def handle_event("disconnect", _params, socket) do
    with_sudo(socket, &disconnect(&1))
  end

  def handle_event("assign_workspace", params, socket) do
    with_sudo(socket, fn socket -> update_workspace_assignment(socket, params, :assign) end)
  end

  def handle_event("unassign_workspace", params, socket) do
    with_sudo(socket, fn socket -> update_workspace_assignment(socket, params, :unassign) end)
  end

  defp connect(socket, api_key) do
    user = socket.assigns.current_scope.user

    with :ok <- RateLimiter.check_ai_integration_connect(user.id),
         nil <- AI.get_active(user, socket.assigns.provider),
         {:ok, _integration} <- AI.connect(user, socket.assigns.provider, trim(api_key)) do
      {:reply, %{status: "ok"}, assign_detail(socket)}
    else
      {:error, reason} -> {:reply, error_reply(reason), socket}
      %{} -> {:reply, error_reply(:already_connected), socket}
    end
  end

  defp replace_key(socket, api_key) do
    user = socket.assigns.current_scope.user

    with :ok <- RateLimiter.check_ai_integration_connect(user.id),
         %{} = integration <- AI.get_active(user, socket.assigns.provider),
         {:ok, _integration} <-
           AI.replace_integration_key(user, integration, trim(api_key)) do
      {:reply, %{status: "ok"}, assign_detail(socket)}
    else
      nil -> {:reply, error_reply(:not_connected), socket}
      {:error, reason} -> {:reply, error_reply(reason), socket}
    end
  end

  defp revalidate(socket) do
    user = socket.assigns.current_scope.user

    with :ok <- RateLimiter.check_ai_integration_connect(user.id),
         %{} = integration <- AI.get_active(user, socket.assigns.provider) do
      revalidation_reply(socket, AI.revalidate_integration(user, integration))
    else
      nil -> {:reply, error_reply(:not_connected), socket}
      {:error, reason} -> {:reply, error_reply(reason), socket}
    end
  end

  defp revalidation_reply(socket, {:ok, _integration}), do: {:reply, %{status: "ok"}, assign_detail(socket)}

  defp revalidation_reply(socket, {:error, :invalid_key}), do: {:reply, error_reply(:invalid_key), assign_detail(socket)}

  defp revalidation_reply(socket, {:error, reason}), do: {:reply, error_reply(reason), socket}

  defp disconnect(socket) do
    user = socket.assigns.current_scope.user

    user
    |> AI.get_active(socket.assigns.provider)
    |> disconnect_integration(socket, user)
  end

  defp disconnect_integration(nil, socket, _user), do: {:reply, %{status: "ok"}, assign_detail(socket)}

  defp disconnect_integration(integration, socket, user) do
    case AI.revoke(user, integration) do
      {:ok, _revoked} -> {:reply, %{status: "ok"}, assign_detail(socket)}
      {:error, :already_revoked} -> {:reply, %{status: "ok"}, assign_detail(socket)}
      {:error, reason} -> {:reply, error_reply(reason), socket}
    end
  end

  defp update_workspace_assignment(socket, params, action) do
    user = socket.assigns.current_scope.user

    with {:ok, workspace_id} <- positive_integer(params["workspace_id"]),
         %{} = integration <- AI.get_active(user, socket.assigns.provider),
         {:ok, _assignment} <-
           mutate_assignment(
             action,
             socket.assigns.current_scope,
             integration.id,
             workspace_id
           ) do
      {:reply, %{status: "ok"}, assign_detail(socket)}
    else
      nil -> {:reply, error_reply(:not_connected), socket}
      {:error, reason} -> {:reply, error_reply(reason), socket}
    end
  end

  defp mutate_assignment(:assign, scope, integration_id, workspace_id),
    do: AI.assign_integration(scope, integration_id, workspace_id)

  defp mutate_assignment(:unassign, scope, integration_id, workspace_id),
    do: AI.unassign_integration(scope, integration_id, workspace_id)

  defp assign_detail(socket) do
    user = socket.assigns.current_scope.user
    integration = AI.get_active(user, socket.assigns.provider)
    models = model_summaries(socket.assigns.provider, integration)

    card = %{
      integration_id: integration && integration.id,
      provider: socket.assigns.provider,
      name: socket.assigns.metadata.name,
      key_generation_url: socket.assigns.metadata.key_generation_url,
      docs_url: socket.assigns.metadata.docs_url,
      key_placeholder: socket.assigns.metadata.key_placeholder,
      capabilities: Enum.map(socket.assigns.metadata.capabilities, &Atom.to_string/1),
      status: if(integration, do: "connected", else: "not_connected"),
      account_email: integration && integration.account_email,
      account_display_name: integration && integration.account_display_name,
      key_last_four: integration && integration.key_last_four,
      connected_at: integration && integration.connected_at,
      last_validated_at: integration && integration.last_validated_at,
      catalog_status: catalog_status(integration),
      models: models,
      workspace_assignments: assignment_states(socket, integration),
      preference_impacts: preference_impacts(socket, integration)
    }

    assign(socket, :card, card)
  end

  defp assignment_states(_socket, nil), do: []

  defp assignment_states(socket, integration), do: AI.list_assignment_states(socket.assigns.current_scope, integration)

  defp preference_impacts(_socket, nil), do: []

  defp preference_impacts(socket, integration) do
    case AI.personal_preference_impacts(socket.assigns.current_scope, integration.id) do
      {:ok, impacts} -> impacts
      {:error, _reason} -> []
    end
  end

  defp model_summaries(provider, integration) do
    provider
    |> AI.models_for_provider()
    |> Enum.map(&Map.put(&1, :availability, model_availability(&1, integration)))
  end

  defp model_availability(%{deprecated: true}, _integration), do: "deprecated"
  defp model_availability(_model, nil), do: "unknown"
  defp model_availability(_model, %{available_models: nil}), do: "unknown"

  defp model_availability(%{model: model}, %{available_models: available_models}) when is_list(available_models) do
    if Enum.any?(available_models, &(String.replace_prefix(&1, "models/", "") == model)),
      do: "available",
      else: "unavailable"
  end

  defp model_availability(_model, _integration), do: "unavailable"

  defp catalog_status(nil), do: "not_connected"
  defp catalog_status(integration), do: Atom.to_string(AI.integration_model_status(integration))

  defp provider_metadata(provider) do
    with metadata when not is_nil(metadata) <-
           Enum.find(AI.provider_metadata(), &(Atom.to_string(&1.id) == provider)),
         [_first | _rest] <- AI.models_for_provider(provider) do
      {:ok, metadata}
    else
      _unsupported -> :error
    end
  end

  defp providers_path(socket) do
    UserAuth.with_sudo_grant(
      ~p"/users/settings/integrations",
      socket.assigns.sudo_grant
    )
  end

  defp with_sudo(socket, fun) do
    Sudo.authorize(socket, return_to(socket), fun)
  end

  defp return_to(socket), do: ~p"/users/settings/integrations/#{socket.assigns.provider}"

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(_value), do: ""

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _invalid -> {:error, :invalid_data}
    end
  end

  defp positive_integer(_value), do: {:error, :invalid_data}

  defp error_reply(reason), do: %{status: "error", error: error_code(reason)}

  defp error_code(:rate_limited), do: "rate_limited"
  defp error_code(:already_connected), do: "already_connected"
  defp error_code(:not_connected), do: "not_connected"
  defp error_code(:unknown_provider), do: "unknown_provider"
  defp error_code(:invalid_key), do: "invalid_key"
  defp error_code(:network_error), do: "network_error"
  defp error_code(:provider_error), do: "provider_error"
  defp error_code({:unexpected_status, _status}), do: "provider_error"
  defp error_code(:integration_changed), do: "integration_changed"
  defp error_code(:feature_disabled), do: "feature_disabled"
  defp error_code(:integration_unavailable), do: "integration_unavailable"
  defp error_code(:workspace_unavailable), do: "workspace_unavailable"
  defp error_code(:member_personal_ai_disabled), do: "workspace_policy_disabled"
  defp error_code(:provider_already_assigned), do: "provider_already_assigned"
  defp error_code(:assignment_not_found), do: "assignment_not_found"
  defp error_code(:invalid_data), do: "invalid_data"
  defp error_code(:unauthorized), do: "unauthorized"
  defp error_code(%Ecto.Changeset{}), do: "invalid_data"
  defp error_code(_unknown), do: "unknown_error"
end
