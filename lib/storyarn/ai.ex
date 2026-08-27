defmodule Storyarn.AI do
  @moduledoc """
  Public facade of the AI bounded context.

  External callers (LiveViews, controllers, other contexts) must go through
  this module and never call `Storyarn.AI.*` submodules directly.

  AI is organized into six internal capabilities: governance, integrations,
  context, routing, operations and managed spend. This facade exposes the
  bounded-context operations; Context's exact builder SPI remains an explicit
  contract for consumer-owned implementations. Private implementation roles
  stay behind their owning capability.
  """

  alias Storyarn.AI.Governance
  alias Storyarn.AI.Integrations
  alias Storyarn.AI.ManagedSpend
  alias Storyarn.AI.Operations
  alias Storyarn.AI.Routing

  defdelegate list_active(user), to: Integrations
  defdelegate check_integration_connect_rate(user_id), to: Integrations, as: :check_connect_rate
  defdelegate get_active(user, provider), to: Integrations
  defdelegate connect(user, provider, api_key), to: Integrations
  defdelegate replace_integration_key(user, integration, api_key), to: Integrations, as: :replace_key
  defdelegate revalidate_integration(user, integration), to: Integrations, as: :revalidate
  defdelegate revoke(user, integration), to: Integrations
  defdelegate assign_integration(scope, integration_id, workspace_id), to: Integrations, as: :assign
  defdelegate unassign_integration(scope, integration_id, workspace_id), to: Integrations, as: :unassign
  defdelegate list_assignment_states(scope, integration), to: Integrations
  defdelegate personal_preferences_overview(scope), to: Integrations, as: :preferences_overview
  defdelegate personal_preferences(scope, workspace_id), to: Integrations, as: :preferences
  defdelegate personal_preference_impacts(scope, integration_id), to: Integrations, as: :preference_impacts

  defdelegate put_personal_preference(scope, workspace_id, slot, integration_id, model),
    to: Integrations,
    as: :put_preference

  defdelegate delete_personal_preference(scope, workspace_id, slot),
    to: Integrations,
    as: :delete_preference

  defdelegate provider_metadata(), to: Integrations
  defdelegate adapter_for(provider), to: Integrations
  defdelegate model_catalog(), to: Routing
  defdelegate models_for_provider(provider), to: Routing
  defdelegate integration_model_status(integration), to: Routing

  defdelegate with_personal_integration(user, provider, fun), to: Integrations

  defdelegate new_intent(scope, attrs), to: Routing

  defdelegate resolve_route(intent), to: Routing, as: :preflight

  @doc "Resolves routes and builds the Slice-6 disclosure without creating an operation."
  defdelegate preflight(intent), to: Routing
  defdelegate execute(intent), to: Operations
  defdelegate cancel(scope, operation_id), to: Operations, as: :request_cancellation

  @doc """
  Gives up an operation the actor walked away from, but never one already paid for.

  Unlike `cancel/2` this never stamps a cancellation on a started provider
  attempt: it releases the reservation while nothing has been spent and
  otherwise leaves the run alone, reporting which of the two happened.
  """
  defdelegate release_if_unstarted(scope, operation_id), to: Operations

  @doc """
  Whether `route_ref` is the purchase decision that CREATED `operation_id`.

  Only the creating path consumes a route option, so a surface whose `execute`
  replayed an existing idempotency key leaves its own option unconsumed. That
  makes this the one reliable answer to "did I buy this operation, or attach to
  one that already existed" — a distinction a surface cannot infer on its own,
  because two panels can resolve preflight for the same unspent key and both
  call `execute/1`.
  """
  defdelegate created_operation?(scope, route_ref, operation_id), to: Routing

  defdelegate grant_personal_consent(intent, integration_id, policy_text_version),
    to: Integrations,
    as: :grant_consent

  defdelegate revoke_personal_consent(scope, consent_id), to: Integrations, as: :revoke_consent

  defdelegate get_operation(scope, operation_id), to: Operations
  defdelegate get_result(scope, operation_id), to: Operations

  @doc "Recovers a still-readable result by the idempotency key that produced it."
  defdelegate get_replayable_result(scope, task_id, idempotency_key),
    to: Operations

  @doc """
  The operations that spent any of these idempotency keys, keyed by key.

  Reports each one in whatever state it ended up, so a caller can tell a run
  still coming from a dead end, and an absent key from a spent one.
  """
  defdelegate get_operations_by_keys(scope, task_id, idempotency_keys),
    to: Operations

  @doc "Records that the actor saw a result. Never a disposition — see Results.record_view/2."
  defdelegate record_result_view(scope, operation_id), to: Operations

  defdelegate dismiss_result(scope, operation_id), to: Operations
  defdelegate apply_result(scope, operation_id, current_revision, apply_fun), to: Operations

  defdelegate get_workspace_policy(scope, workspace_id), to: Governance
  defdelegate update_workspace_policy(scope, workspace_id, lanes), to: Governance
  defdelegate allowance_summary(scope, workspace_id), to: ManagedSpend, as: :summary
  defdelegate managed_provenance(), to: Routing

  defdelegate registered_tasks(), to: Routing

  @doc "Fetches a registered task regardless of its operational switch."
  defdelegate get_task(task_id), to: Routing

  defdelegate ai_command_id?(command_id), to: Routing

  @doc false
  defdelegate run_execution_job(job), to: Operations

  @doc false
  defdelegate run_execution_job_with(job, recover, execute, terminalize), to: Operations

  @doc false
  defdelegate expire_results(), to: Operations

  @doc false
  defdelegate purge_expired_route_options(), to: Routing, as: :delete_expired_route_options

  @doc false
  defdelegate reconcile_reservations(args, sweep_started_at, batch_size, stale_after_seconds),
    to: Operations

  @doc false
  defdelegate grant_allowance(workspace_id, actor_id, attrs), to: ManagedSpend, as: :grant

  @doc false
  defdelegate managed_diagnostic_probe(), to: Routing
end
