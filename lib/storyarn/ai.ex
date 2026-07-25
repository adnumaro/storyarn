defmodule Storyarn.AI do
  @moduledoc """
  Facade for provider connections and the provider-neutral AI execution kernel.

  External callers (LiveViews, controllers, other contexts) must go through
  this module and never call `Storyarn.AI.*` submodules directly.

  Slice 0 owns personal provider connections. Slices 2–4 add registered tasks,
  workspace policy, opaque route preflight, durable operations, managed
  execution and personal BYOK. Slice 5.1 adds the central route-resolution,
  model-catalog and workspace-assignment boundaries. Slice 7.2a adds the
  flow-finding explanation seam — intent building, its replay key, and the reads
  a panel needs to recover or attach to an operation it already paid for.
  """

  alias Storyarn.Accounts.Scope
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
  alias Storyarn.AI.Tasks.FlowFindingExplanation

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

  @doc """
  Whether the flow-finding explanation task is registered at all.

  Ignores the operational switch: a disabled task still shows an honest blocked
  state, only an unregistered one (a deployment without it) hides the surface.
  """
  @spec flow_finding_explanation_registered?() :: boolean()
  def flow_finding_explanation_registered? do
    match?({:ok, _task}, get_task(FlowFindingExplanation.task_id()))
  end

  @doc """
  Builds the intent for explaining ONE authorized structural finding.

  The task's wire format — input shape, subject identity, idempotency key — stays
  inside this context. A caller supplies the finding it already authorized plus
  the attempt counter, so bumping `input_schema_version` cannot leave a LiveView
  silently behind: there is nothing to bump out there.

  `attempt` is what buys a second explanation of the same occurrence; 0 replays
  whatever the actor already paid for.
  """
  @spec flow_finding_explanation_intent(Scope.t(), map()) ::
          {:ok, ExecutionIntent.t()} | {:error, atom()}
  def flow_finding_explanation_intent(scope, %{} = params) do
    %{
      workspace_id: workspace_id,
      project_id: project_id,
      flow_id: flow_id,
      finding: finding,
      locale: locale
    } = params

    attrs = %{
      workspace_id: workspace_id,
      project_id: project_id,
      task_id: FlowFindingExplanation.task_id(),
      input: FlowFindingExplanation.input(finding, locale),
      subject: FlowFindingExplanation.subject(flow_id, finding)
    }

    attrs =
      case params do
        %{route_ref: route_ref, attempt: attempt} ->
          Map.merge(attrs, %{
            requested_route_ref: route_ref,
            idempotency_key: FlowFindingExplanation.idempotency_key(scope.user.id, finding, locale, attempt)
          })

        _preflight_only ->
          attrs
      end

    ExecutionIntent.new(scope, attrs)
  end

  @doc """
  The idempotency key an explanation attempt would use, for a replay probe.

  Takes the locale because the key includes it: probing without it would surface a
  narrative in the wrong language.
  """
  @spec flow_finding_explanation_key(Scope.t(), term(), String.t(), non_neg_integer()) :: String.t()
  def flow_finding_explanation_key(scope, finding, locale, attempt) do
    FlowFindingExplanation.idempotency_key(scope.user.id, finding, locale, attempt)
  end

  @doc "The registered id of the flow-finding explanation task."
  @spec flow_finding_explanation_task_id() :: String.t()
  defdelegate flow_finding_explanation_task_id(), to: FlowFindingExplanation, as: :task_id
  defdelegate resolve_route(intent), to: Execution, as: :preflight

  @doc "Resolves routes and builds the Slice-6 disclosure without creating an operation."
  defdelegate preflight(intent), to: Execution
  defdelegate execute(intent), to: Execution
  defdelegate cancel(scope, operation_id), to: Operations, as: :request_cancellation
  defdelegate grant_personal_consent(intent, integration_id, policy_text_version), to: PersonalConsents, as: :grant
  defdelegate revoke_personal_consent(scope, consent_id), to: PersonalConsents, as: :revoke

  defdelegate get_operation(scope, operation_id), to: Results
  defdelegate get_result(scope, operation_id), to: Results, as: :get

  @doc "Recovers a still-readable result by the idempotency key that produced it."
  defdelegate get_replayable_result(scope, task_id, idempotency_key),
    to: Results,
    as: :get_by_idempotency_key

  @doc "The operation that spent an idempotency key, in whatever state it ended up."
  defdelegate get_operation_by_key(scope, task_id, idempotency_key),
    to: Results,
    as: :get_operation_by_idempotency_key

  @doc "Records that the actor saw a result. Never a disposition — see Results.record_view/2."
  defdelegate record_result_view(scope, operation_id), to: Results, as: :record_view

  defdelegate dismiss_result(scope, operation_id), to: Results, as: :dismiss
  defdelegate apply_result(scope, operation_id, current_revision, apply_fun), to: Results, as: :apply

  defdelegate get_workspace_policy(scope, workspace_id), to: Policy, as: :get
  defdelegate update_workspace_policy(scope, workspace_id, lanes), to: Policy, as: :update
  defdelegate allowance_summary(scope, workspace_id), to: Allowance, as: :summary
  defdelegate managed_provenance(), to: RouteResolver

  defdelegate registered_tasks(), to: TaskRegistry, as: :all

  @doc "Fetches a registered task regardless of its operational switch."
  defdelegate get_task(task_id), to: TaskRegistry, as: :get

  defdelegate ai_command_id?(command_id), to: TaskRegistry, as: :command_id?
end
