defmodule Storyarn.AI do
  @moduledoc """
  Facade for provider connections and the provider-neutral AI execution kernel.

  External callers (LiveViews, controllers, other contexts) must go through
  this module and never call `Storyarn.AI.*` submodules directly.

  Slice 0 owns personal provider connections. Slice 2 adds registered tasks,
  workspace policy, opaque route preflight, durable operations and temporary
  actor-private results. Production inference routes remain unconfigured until
  later slices.
  """

  alias Storyarn.AI.Execution
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.IntegrationCrud
  alias Storyarn.AI.Operations
  alias Storyarn.AI.Policy
  alias Storyarn.AI.Providers
  alias Storyarn.AI.Results
  alias Storyarn.AI.Runtime
  alias Storyarn.AI.TaskRegistry

  defdelegate list_active(user), to: IntegrationCrud
  defdelegate get_active(user, provider), to: IntegrationCrud
  defdelegate connect(user, provider, api_key), to: IntegrationCrud
  defdelegate revoke(integration), to: IntegrationCrud

  defdelegate provider_metadata(), to: Providers, as: :metadata_list
  defdelegate adapter_for(provider), to: Providers

  defdelegate with_integration(user, provider, fun), to: Runtime

  defdelegate new_intent(scope, attrs), to: ExecutionIntent, as: :new
  defdelegate preflight(intent), to: Execution
  defdelegate execute(intent), to: Execution
  defdelegate cancel(scope, operation_id), to: Operations, as: :request_cancellation

  defdelegate get_operation(scope, operation_id), to: Results
  defdelegate get_result(scope, operation_id), to: Results, as: :get
  defdelegate dismiss_result(scope, operation_id), to: Results, as: :dismiss
  defdelegate apply_result(scope, operation_id, current_revision, apply_fun), to: Results, as: :apply

  defdelegate get_workspace_policy(scope, workspace_id), to: Policy, as: :get
  defdelegate update_workspace_policy(scope, workspace_id, lanes), to: Policy, as: :update

  defdelegate registered_tasks(), to: TaskRegistry, as: :all
  defdelegate ai_command_id?(command_id), to: TaskRegistry, as: :command_id?
end
