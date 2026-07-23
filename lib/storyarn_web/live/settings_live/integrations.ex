defmodule StoryarnWeb.SettingsLive.Integrations do
  @moduledoc """
  Account-level catalog for personal AI provider connections.

  This screen is intentionally read-only. Selecting a provider navigates to
  `SettingsLive.IntegrationDetail`, where credential and workspace assignment
  mutations are isolated behind the same sudo boundary.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.AI
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

  defp assign_cards(socket) do
    user = socket.assigns.current_scope.user

    integrations_by_provider =
      user
      |> AI.list_active()
      |> Map.new(fn integration -> {integration.provider, integration} end)

    cards =
      Enum.flat_map(AI.provider_metadata(), fn metadata ->
        provider = Atom.to_string(metadata.id)
        integration = Map.get(integrations_by_provider, provider)
        models = AI.models_for_provider(provider)

        if models == [] do
          []
        else
          [
            %{
              provider: provider,
              name: metadata.name,
              docs_url: metadata.docs_url,
              status: if(integration, do: "connected", else: "not_connected"),
              account_email: integration && integration.account_email,
              account_display_name: integration && integration.account_display_name,
              key_last_four: integration && integration.key_last_four,
              workspace_count: assigned_workspace_count(socket, integration),
              compatible_model_count: compatible_model_count(integration, models),
              catalog_status: catalog_status(integration),
              detail_path:
                UserAuth.with_sudo_grant(
                  ~p"/users/settings/integrations/#{provider}",
                  socket.assigns.sudo_grant
                )
            }
          ]
        end
      end)

    assign(socket, :cards, cards)
  end

  defp assigned_workspace_count(_socket, nil), do: 0

  defp assigned_workspace_count(socket, integration) do
    socket.assigns.current_scope
    |> AI.list_assignment_states(integration)
    |> Enum.count(& &1.assigned)
  end

  defp compatible_model_count(nil, models), do: Enum.count(models, &(not &1.deprecated))

  defp compatible_model_count(%{available_models: nil}, models), do: Enum.count(models, &(not &1.deprecated))

  defp compatible_model_count(%{available_models: available_models}, models) when is_list(available_models) do
    available = MapSet.new(available_models, &String.replace_prefix(&1, "models/", ""))

    Enum.count(models, &(not &1.deprecated and MapSet.member?(available, &1.model)))
  end

  defp compatible_model_count(_integration, _models), do: 0

  defp catalog_status(nil), do: "not_connected"
  defp catalog_status(integration), do: Atom.to_string(AI.integration_model_status(integration))
end
