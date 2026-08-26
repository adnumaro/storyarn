defmodule Storyarn.AI.Integrations do
  @moduledoc """
  Public boundary for personal AI provider integrations.

  It owns credential connection lifecycle, workspace assignments, consent,
  personal provider preferences, provider-key validation and integration audit
  behavior. Callers outside this capability should use this facade.
  """

  alias Storyarn.AI.IntegrationAssignments
  alias Storyarn.AI.IntegrationCrud
  alias Storyarn.AI.Integrations.Queries.Integrations, as: IntegrationQueries
  alias Storyarn.AI.PersonalConsents
  alias Storyarn.AI.PersonalPreferences
  alias Storyarn.AI.PersonalProviders
  alias Storyarn.AI.Providers
  alias Storyarn.AI.Runtime

  @type actor :: %{required(:id) => integer(), optional(atom()) => term()}
  @type scope :: %{required(:user) => actor(), optional(atom()) => term()}

  # Connection lifecycle and provider SPI
  defdelegate list_active(user), to: IntegrationQueries
  defdelegate get_active(user, provider), to: IntegrationQueries
  defdelegate connect(user, provider, api_key), to: IntegrationCrud
  defdelegate replace_key(user, integration, api_key), to: IntegrationCrud
  defdelegate revalidate(user, integration), to: IntegrationCrud
  defdelegate revoke(user, integration), to: IntegrationCrud
  defdelegate revoke_active(integration, action), to: IntegrationCrud
  defdelegate provider_metadata(), to: Providers, as: :metadata_list
  defdelegate adapter_for(provider), to: Providers

  # Workspace assignment lifecycle
  defdelegate assign(scope, integration_id, workspace_id), to: IntegrationAssignments
  defdelegate unassign(scope, integration_id, workspace_id), to: IntegrationAssignments
  defdelegate list_assignment_states(scope, integration), to: IntegrationAssignments, as: :list_states

  defdelegate active_assignment(user_id, workspace_id, integration_id, opts \\ []),
    to: IntegrationAssignments,
    as: :active_for

  defdelegate authorize_assignment_route(user_id, workspace_id, integration, configuration, opts \\ []),
    to: IntegrationAssignments,
    as: :authorize_route

  defdelegate revoke_assignments_for_integration(integration_id, revoked_at),
    to: IntegrationAssignments,
    as: :revoke_for_integration

  # Personal preferences and provider routing material
  defdelegate preferences_overview(scope), to: PersonalPreferences, as: :overview
  defdelegate preferences(scope, workspace_id), to: PersonalPreferences, as: :summary
  defdelegate preference_impacts(scope, integration_id), to: PersonalPreferences, as: :impacts
  defdelegate put_preference(scope, workspace_id, slot, integration_id, model), to: PersonalPreferences, as: :put
  defdelegate delete_preference(scope, workspace_id, slot), to: PersonalPreferences, as: :delete
  defdelegate resolve_preference(user_id, workspace_id, task), to: PersonalPreferences, as: :resolve
  defdelegate public_preference_resolution(resolution), to: PersonalPreferences, as: :public_resolution
  defdelegate personal_provider(provider), to: PersonalProviders, as: :fetch
  defdelegate personal_provider(provider, model), to: PersonalProviders, as: :fetch
  defdelegate configurable_personal_provider(provider, model), to: PersonalProviders, as: :fetch_configurable
  defdelegate personal_providers_for(capability), to: PersonalProviders, as: :for_capability

  defdelegate configurable_personal_providers_for(capability),
    to: PersonalProviders,
    as: :configurable_for_capability

  defdelegate personal_model_status(config, integration), to: PersonalProviders, as: :model_status

  # Consent and execution-time credential lifecycle
  defdelegate consent_policy_text_version(), to: PersonalConsents, as: :policy_text_version
  defdelegate grant_consent(intent, integration_id, policy_text_version), to: PersonalConsents, as: :grant
  defdelegate revoke_consent(scope, consent_id), to: PersonalConsents, as: :revoke

  defdelegate active_consent(user_id, workspace_id, integration_id, task, opts \\ []),
    to: PersonalConsents,
    as: :active_for

  defdelegate authorize_operation_consent(operation, task, route, opts \\ []),
    to: PersonalConsents,
    as: :authorize_operation

  defdelegate checkout_operation(operation, task, route, opts \\ []), to: PersonalConsents

  defdelegate revoke_consents_for_integration(integration_id, revoked_at),
    to: PersonalConsents,
    as: :revoke_for_integration

  defdelegate with_personal_integration(user, provider, fun), to: Runtime

  @doc false
  defdelegate record_provider_outcome(integration_id, outcome), to: Runtime
end
