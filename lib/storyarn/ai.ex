defmodule Storyarn.AI do
  @moduledoc """
  Facade for provider connections and the provider-neutral AI execution kernel.

  External callers (LiveViews, controllers, other contexts) must go through
  this module and never call `Storyarn.AI.*` submodules directly.

  Slice 0 owns personal provider connections. Slices 2–4 add registered tasks,
  workspace policy, opaque route preflight, durable operations, managed
  execution and personal BYOK. Slice 5.1 adds the central route-resolution,
  model-catalog and workspace-assignment boundaries.
  """

  alias Storyarn.AI.Allowance
  alias Storyarn.AI.Execution
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.IntegrationAssignments
  alias Storyarn.AI.IntegrationCrud
  alias Storyarn.AI.ModelCatalog
  alias Storyarn.AI.Operations
  alias Storyarn.AI.PersonalConsents
  alias Storyarn.AI.PersonalPreferences
  alias Storyarn.AI.Policy
  alias Storyarn.AI.Providers
  alias Storyarn.AI.Results
  alias Storyarn.AI.RouteResolver
  alias Storyarn.AI.Runtime
  alias Storyarn.AI.TaskRegistry

  defdelegate list_active(user), to: IntegrationCrud
  defdelegate get_active(user, provider), to: IntegrationCrud
  defdelegate connect(user, provider, api_key), to: IntegrationCrud
  defdelegate replace_integration_key(user, integration, api_key), to: IntegrationCrud, as: :replace_key
  defdelegate revalidate_integration(user, integration), to: IntegrationCrud, as: :revalidate
  defdelegate revoke(user, integration), to: IntegrationCrud
  defdelegate assign_integration(scope, integration_id, workspace_id), to: IntegrationAssignments, as: :assign
  defdelegate unassign_integration(scope, integration_id, workspace_id), to: IntegrationAssignments, as: :unassign
  defdelegate list_assignment_states(scope, integration), to: IntegrationAssignments, as: :list_states
  defdelegate personal_preferences_overview(scope), to: PersonalPreferences, as: :overview
  defdelegate personal_preferences(scope, workspace_id), to: PersonalPreferences, as: :summary
  defdelegate personal_preference_impacts(scope, integration_id), to: PersonalPreferences, as: :impacts

  defdelegate put_personal_preference(scope, workspace_id, slot, integration_id, model),
    to: PersonalPreferences,
    as: :put

  defdelegate delete_personal_preference(scope, workspace_id, slot),
    to: PersonalPreferences,
    as: :delete

  defdelegate provider_metadata(), to: Providers, as: :metadata_list
  defdelegate adapter_for(provider), to: Providers
  defdelegate model_catalog(), to: ModelCatalog, as: :all
  defdelegate models_for_provider(provider), to: ModelCatalog, as: :public_for_provider
  defdelegate integration_model_status(integration), to: ModelCatalog, as: :provider_status

  defdelegate with_personal_integration(user, provider, fun), to: Runtime

  defdelegate new_intent(scope, attrs), to: ExecutionIntent, as: :new
  defdelegate resolve_route(intent), to: Execution, as: :preflight

  @doc "Backward-compatible name for route resolution; prefer `resolve_route/1` in new consumers."
  defdelegate preflight(intent), to: Execution
  defdelegate execute(intent), to: Execution
  defdelegate cancel(scope, operation_id), to: Operations, as: :request_cancellation
  defdelegate grant_personal_consent(intent, integration_id, policy_text_version), to: PersonalConsents, as: :grant
  defdelegate revoke_personal_consent(scope, consent_id), to: PersonalConsents, as: :revoke

  defdelegate get_operation(scope, operation_id), to: Results
  defdelegate get_result(scope, operation_id), to: Results, as: :get
  defdelegate dismiss_result(scope, operation_id), to: Results, as: :dismiss
  defdelegate apply_result(scope, operation_id, current_revision, apply_fun), to: Results, as: :apply

  defdelegate get_workspace_policy(scope, workspace_id), to: Policy, as: :get
  defdelegate update_workspace_policy(scope, workspace_id, lanes), to: Policy, as: :update
  defdelegate allowance_summary(scope, workspace_id), to: Allowance, as: :summary
  defdelegate managed_provenance(), to: RouteResolver

  defdelegate registered_tasks(), to: TaskRegistry, as: :all
  defdelegate ai_command_id?(command_id), to: TaskRegistry, as: :command_id?
end
