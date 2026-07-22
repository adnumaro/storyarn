defmodule StoryarnWeb.FeatureFlagHelpers do
  @moduledoc false

  alias Storyarn.FeatureFlags

  @doc "Serializes actor-resolved feature flags for authenticated Vue layout boundaries."
  def client_flags(%{user: user}) when not is_nil(user) do
    %{aiIntegrations: FeatureFlags.enabled?(:ai_integrations, for: user)}
  end

  def client_flags(_scope), do: %{aiIntegrations: false}
end
