defmodule Storyarn.AI.Operations do
  @moduledoc """
  Public capability boundary for durable AI operations and temporary results.

  Operations owns idempotent creation, provider-attempt lifecycle, settlement
  transitions, result visibility and recovery. Provider and credential modules
  remain technical contracts or adapters behind this boundary.
  """

  alias Storyarn.AI.Alerts
  alias Storyarn.AI.InferenceProviders
  alias Storyarn.AI.Operations.Commands.Execute
  alias Storyarn.AI.Operations.Commands.Lifecycle
  alias Storyarn.AI.Operations.Commands.ReconcileReservations
  alias Storyarn.AI.Operations.Execution.JobRunner
  alias Storyarn.AI.Results

  defdelegate execute(intent), to: Execute, as: :run
  defdelegate request_cancellation(scope, operation_id), to: Lifecycle
  defdelegate release_if_unstarted(scope, operation_id), to: Lifecycle

  defdelegate get_operation(scope, operation_id), to: Results
  defdelegate get_result(scope, operation_id), to: Results, as: :get
  defdelegate get_replayable_result(scope, task_id, idempotency_key), to: Results, as: :get_by_idempotency_key

  defdelegate get_operations_by_keys(scope, task_id, idempotency_keys),
    to: Results,
    as: :operations_by_idempotency_keys

  defdelegate record_result_view(scope, operation_id), to: Results, as: :record_view
  defdelegate dismiss_result(scope, operation_id), to: Results, as: :dismiss
  defdelegate apply_result(scope, operation_id, current_revision, apply_fun), to: Results, as: :apply

  @doc false
  defdelegate claim(operation_id), to: Lifecycle

  @doc false
  defdelegate start_attempt(operation, task, route), to: Lifecycle

  @doc false
  defdelegate fail_before_attempt(operation, reason), to: Lifecycle

  @doc false
  defdelegate finish_success(operation, usage, output, metrics), to: Lifecycle

  @doc false
  defdelegate finish_failure(operation, usage, reason, metrics \\ %{}), to: Lifecycle

  @doc false
  defdelegate finish_unknown(operation, usage, reason, metrics \\ %{}), to: Lifecycle

  @doc false
  defdelegate recover_interrupted(operation_id), to: Lifecycle

  @doc false
  defdelegate fail_queued_after_retries(operation_id, reason), to: Lifecycle

  @doc false
  defdelegate record_alert(attrs), to: Alerts, as: :record

  @doc false
  defdelegate run_execution_job(job), to: JobRunner, as: :run

  @doc false
  defdelegate run_execution_job_with(job, recover, execute, terminalize), to: JobRunner, as: :run_with

  @doc false
  defdelegate expire_results(), to: Results, as: :expire

  @doc false
  defdelegate purge_project_results(project_id), to: Results, as: :purge_project

  @doc false
  defdelegate reconcile_reservations(args, sweep_started_at, batch_size, stale_after_seconds),
    to: ReconcileReservations,
    as: :run

  @doc false
  defdelegate fetch_inference_provider(provider), to: InferenceProviders, as: :fetch
end
