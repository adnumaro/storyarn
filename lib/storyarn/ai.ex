defmodule Storyarn.AI do
  @moduledoc """
  Facade for the AI Integrations context.

  External callers (LiveViews, controllers, other contexts) must go through
  this module and never call `Storyarn.AI.*` submodules directly.

  ## v1 scope

  BYOK only — users paste an API key from the provider's console. See
  `docs/features/ai-integrations/PROVIDERS.md` for the OAuth research that
  led to this decision, and `Storyarn.AI.Providers` for the current adapter
  list.
  """

  alias Storyarn.AI.IntegrationCrud
  alias Storyarn.AI.Providers
  alias Storyarn.AI.Runtime

  defdelegate list_active(user), to: IntegrationCrud
  defdelegate get_active(user, provider), to: IntegrationCrud
  defdelegate connect(user, provider, api_key), to: IntegrationCrud
  defdelegate revoke(integration), to: IntegrationCrud

  defdelegate provider_metadata(), to: Providers, as: :metadata_list
  defdelegate adapter_for(provider), to: Providers

  defdelegate with_integration(user, provider, fun), to: Runtime
end
