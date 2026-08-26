defmodule Storyarn.AI.Governance.Adapters.FeatureFlags do
  @moduledoc "Technical adapter for AI feature rollout checks."

  @spec ai_integrations_enabled?(term()) :: boolean()
  def ai_integrations_enabled?(actor) do
    FunWithFlags.enabled?(:ai_integrations, for: actor)
  end
end
