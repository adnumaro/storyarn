defmodule Storyarn.AI.Routing do
  @moduledoc """
  Public capability boundary for AI task contracts, model catalog and routes.

  Routing resolves provider-neutral choices and opaque route references. It
  never performs inference or owns durable operation state.
  """

  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.ModelCatalog
  alias Storyarn.AI.RouteOptions
  alias Storyarn.AI.RouteResolver
  alias Storyarn.AI.Routing.Execution.Preflight
  alias Storyarn.AI.Routing.Rules.ModelLimits
  alias Storyarn.AI.TaskRegistry
  alias Storyarn.AI.Tasks.ManagedDiagnostic

  defdelegate new_intent(scope, attrs), to: ExecutionIntent, as: :new

  defdelegate model_catalog(), to: ModelCatalog, as: :all
  defdelegate models_for_provider(provider), to: ModelCatalog, as: :public_for_provider
  defdelegate integration_model_status(integration), to: ModelCatalog, as: :provider_status

  defdelegate registered_tasks(), to: TaskRegistry, as: :all
  defdelegate get_task(task_id), to: TaskRegistry, as: :get
  defdelegate ai_command_id?(command_id), to: TaskRegistry, as: :command_id?

  defdelegate preflight(intent), to: Preflight, as: :run
  defdelegate created_operation?(scope, route_ref, operation_id), to: RouteOptions
  defdelegate managed_provenance(), to: RouteResolver

  @doc false
  defdelegate fetch_task(task_id), to: TaskRegistry, as: :fetch

  @doc false
  defdelegate fetch_model(provider, model), to: ModelCatalog, as: :fetch

  @doc false
  defdelegate validate_provider_request(provider, request, body), to: ModelLimits

  @doc false
  defdelegate contextual_input?(input, context_policy), to: ModelLimits

  @doc false
  defdelegate models_for_capability(capability, opts \\ []), to: ModelCatalog, as: :for_capability

  @doc false
  defdelegate models_for_provider_entries(provider, opts \\ []), to: ModelCatalog, as: :for_provider

  @doc false
  defdelegate authorize_model(entry, integration), to: ModelCatalog, as: :authorize

  @doc false
  defdelegate model_public_summary(entry), to: ModelCatalog, as: :public_summary

  @doc false
  defdelegate preflight_options(decision, task), to: RouteResolver

  @doc false
  defdelegate route_current?(decision, task, route), to: RouteResolver, as: :current?

  @doc false
  defdelegate snapshot_route_option(intent, task), to: RouteOptions, as: :resolve_snapshot

  @doc false
  defdelegate lock_route_option(snapshot, intent, task), to: RouteOptions, as: :lock_snapshot

  @doc false
  defdelegate revalidate_route_option(option, snapshot, intent, task),
    to: RouteOptions,
    as: :revalidate_locked

  @doc false
  defdelegate consume_route_option(option, operation_id), to: RouteOptions, as: :consume_locked

  @doc false
  defdelegate delete_expired_route_options(), to: RouteOptions, as: :delete_expired

  @doc false
  defdelegate managed_diagnostic_probe(), to: ManagedDiagnostic, as: :probe
end
