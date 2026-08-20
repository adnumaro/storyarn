defmodule Storyarn.Imports.Execution do
  @moduledoc """
  Running an accepted import to a terminal state.

  The `running` transition commits before materialization starts, so a returning
  page can observe progress without waiting for the write transaction. Project
  content and the terminal `completed` transition still happen atomically in a
  second transaction under the workspace-first storage-accounting lock order.
  Every exit is idempotent — a replayed job observes `completed` and re-emits
  its side effects rather than importing twice.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Imports.Error
  alias Storyarn.Imports.Materializer
  alias Storyarn.Imports.NotificationDelivery
  alias Storyarn.Imports.Parsers.Yarn.ReviewDecisions
  alias Storyarn.Imports.PlanCleanup
  alias Storyarn.Imports.PlanStorage
  alias Storyarn.Imports.ProjectImportAttempt
  alias Storyarn.Imports.Queue
  alias Storyarn.Imports.Replacement
  alias Storyarn.Imports.Shared
  alias Storyarn.Imports.Telemetry
  alias Storyarn.Notifications
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @materialization_timeout 300_000
  @import_action :manage_project

  @doc false
  @spec perform_import(pos_integer(), keyword()) ::
          {:ok, ProjectImportAttempt.t() | :attempt_not_found}
          | {:snooze, pos_integer()}
          | {:error, term()}
  def perform_import(attempt_id, opts \\ []) do
    case Shared.get_attempt(attempt_id) do
      nil ->
        {:ok, :attempt_not_found}

      %ProjectImportAttempt{} = attempt ->
        case attempt.status do
          "completed" ->
            PlanCleanup.cleanup_plan_if_pending(attempt)
            replay_completed_side_effects(attempt)
            {:ok, attempt}

          status when status in ["failed", "expired"] ->
            PlanCleanup.cleanup_plan_if_pending(attempt)
            {:ok, attempt}

          "ready" ->
            {:error, :import_not_queued}

          _status ->
            run_import(attempt, opts)
        end
    end
  end

  defp run_import(attempt, opts) do
    started_at = System.monotonic_time()
    attempt_number = Keyword.get(opts, :attempt, 1)
    max_attempts = Keyword.get(opts, :max_attempts, 1)
    plan_load = Keyword.get(opts, :plan_load, &PlanStorage.load/1)

    result =
      try do
        execute_import_attempt(
          attempt,
          opts,
          plan_load,
          attempt_number,
          max_attempts,
          started_at
        )
      rescue
        exception ->
          handled_execution_error(
            attempt,
            :unexpected_import_error,
            attempt_number,
            max_attempts,
            started_at,
            opts,
            inspect(exception.__struct__)
          )
      catch
        _kind, _reason ->
          handled_execution_error(
            attempt,
            :unexpected_import_error,
            attempt_number,
            max_attempts,
            started_at,
            opts
          )
      end

    case result do
      {:materialized, outcome} -> finish_import(outcome, started_at, opts)
      {:waiting, seconds} -> {:snooze, seconds}
      {:handled, handled_result} -> handled_result
    end
  end

  defp execute_import_attempt(attempt, opts, plan_load, attempt_number, max_attempts, started_at) do
    with {:ok, project, _membership} <- authorize_worker(attempt),
         {:ok, plan} <- Shared.safely_load_plan(plan_load, attempt.plan_storage_key),
         :ok <- Shared.validate_attempt_plan_binding(attempt, plan),
         true <- ReviewDecisions.resolved?(plan) do
      continue_import_with_snapshot(attempt, project, plan, opts, attempt_number, max_attempts, started_at)
    else
      false ->
        handled_execution_error(attempt, :invalid_import_review, attempt_number, max_attempts, started_at, opts)

      {:error, reason} ->
        handled_execution_error(attempt, reason, attempt_number, max_attempts, started_at, opts)
    end
  end

  defp continue_import_with_snapshot(attempt, project, plan, opts, attempt_number, max_attempts, started_at) do
    case Replacement.ensure_snapshot_ready(attempt, project, opts) do
      {:ok, ready_attempt} ->
        materialize_ready_import(ready_attempt, project, plan, opts, attempt_number, max_attempts, started_at)

      {:snooze, seconds} ->
        {:waiting, seconds}

      {:error, reason} ->
        handled_execution_error(attempt, reason, attempt_number, max_attempts, started_at, opts)
    end
  end

  defp materialize_ready_import(attempt, project, plan, opts, attempt_number, max_attempts, started_at) do
    case begin_and_materialize(attempt, project, plan, opts) do
      {:ok, outcome} ->
        {:materialized, outcome}

      {:error, reason} ->
        handled_execution_error(attempt, reason, attempt_number, max_attempts, started_at, opts)
    end
  end

  defp authorize_worker(attempt) do
    Projects.authorize(Scope.for_user(attempt.user), attempt.project_id, @import_action)
  end

  defp handled_execution_error(
         attempt,
         reason,
         attempt_number,
         max_attempts,
         started_at,
         opts,
         exception_module \\ "none"
       ) do
    {:handled,
     handle_execution_error(
       attempt,
       reason,
       attempt_number,
       max_attempts,
       started_at,
       opts,
       exception_module
     )}
  end

  defp begin_and_materialize(attempt, project, plan, opts) do
    case begin_materialization(attempt, project) do
      {:ok, {:started, running}} ->
        # The transition is durable before it is announced. A page returning
        # during a long materialization can now recover `running` immediately.
        Queue.broadcast(running)
        materialize_running_attempt(running, project, plan, opts)

      {:ok, {:running, running}} ->
        materialize_running_attempt(running, project, plan, opts)

      {:ok, outcome} ->
        {:ok, outcome}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp materialize_running_attempt(attempt, project, plan, opts) do
    with :ok <- run_before_materialization_transaction(opts) do
      materialize_once(attempt, project, plan, opts)
    end
  end

  # The short first transaction publishes `running` without touching storage
  # accounting. The second takes the common workspace lock before project,
  # requester, membership, and attempt, and keeps all imported entities and
  # `completed` atomic.
  defp begin_materialization(attempt, project) do
    Repo.transact(fn ->
      with {:ok, authorized_project, notification_context} <-
             authorize_worker_locked(attempt, attempt.user_id),
           true <- authorized_project.id == project.id,
           :ok <- Replacement.prelock_snapshot_in_transaction(attempt),
           %ProjectImportAttempt{} = locked_attempt <-
             lock_import_attempt(attempt.id, authorized_project.id, attempt.user_id) do
        begin_locked_attempt(locked_attempt, notification_context)
      else
        nil -> {:error, :not_found}
        false -> {:error, :unauthorized}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp begin_locked_attempt(%{status: "completed"} = attempt, _notification_context),
    do: {:ok, {:already_completed, attempt}}

  defp begin_locked_attempt(%{status: status} = attempt, _notification_context) when status in ["failed", "expired"],
    do: {:ok, {:terminal, attempt}}

  defp begin_locked_attempt(%{status: status} = attempt, notification_context)
       when status in ["queued", "running", "retrying"] do
    if PlanCleanup.absolute_plan_deadline_reached?(attempt, TimeHelpers.now()) do
      expire_locked_import_attempt(attempt, notification_context)
    else
      case status do
        "running" -> {:ok, {:running, attempt}}
        _accepted -> attempt |> mark_running() |> tag_started_attempt()
      end
    end
  end

  defp begin_locked_attempt(_attempt, _notification_context), do: {:error, :import_not_queued}

  defp tag_started_attempt({:ok, running}), do: {:ok, {:started, running}}
  defp tag_started_attempt({:error, reason}), do: {:error, reason}

  defp materialize_once(attempt, project, plan, opts) do
    Billing.transact_with_workspace_lock(
      project.workspace_id,
      fn _workspace ->
        with_result =
          with {:ok, authorized_project, notification_context} <-
                 authorize_worker_locked(attempt, attempt.user_id),
               true <- authorized_project.id == project.id,
               :ok <- Replacement.prelock_snapshot_in_transaction(attempt),
               %ProjectImportAttempt{} = locked_attempt <-
                 lock_import_attempt(attempt.id, authorized_project.id, attempt.user_id) do
            materialize_locked_attempt(
              locked_attempt,
              authorized_project,
              notification_context,
              plan,
              opts
            )
          else
            nil -> {:error, :not_found}
            false -> {:error, :unauthorized}
            {:error, reason} -> {:error, reason}
          end

        normalize_materialization_transaction_result(with_result)
      end,
      timeout: @materialization_timeout
    )
  end

  defp normalize_materialization_transaction_result({:error, reason, details}), do: {:error, {reason, details}}

  defp normalize_materialization_transaction_result(result), do: result

  defp lock_import_attempt(attempt_id, project_id, user_id) do
    ProjectImportAttempt
    |> where(
      [candidate],
      candidate.id == ^attempt_id and candidate.project_id == ^project_id and
        candidate.user_id == ^user_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp materialize_locked_attempt(%{status: "completed"} = attempt, _project, _notification_context, _plan, _opts) do
    {:ok, {:already_completed, attempt}}
  end

  defp materialize_locked_attempt(%{status: status} = attempt, _project, _notification_context, _plan, _opts)
       when status in ["failed", "expired"] do
    {:ok, {:terminal, attempt}}
  end

  defp materialize_locked_attempt(%{status: status} = attempt, project, notification_context, plan, opts)
       when status in ["queued", "running", "retrying"] do
    if PlanCleanup.absolute_plan_deadline_reached?(attempt, TimeHelpers.now()) do
      expire_locked_import_attempt(attempt, notification_context)
    else
      with {:ok, result} <-
             prepare_and_materialize_project(attempt, project, plan),
           {:ok, notification_outcome} <-
             NotificationDelivery.deliver(attempt, notification_context, "success"),
           :ok <- run_before_attempt_completion(opts),
           {:ok, completed} <- complete_attempt(attempt, result.counts),
           :ok <- PlanCleanup.mark_plan_cleanup_pending(completed.plan_storage_key) do
        {:ok, {:materialized, completed, notification_outcome}}
      end
    end
  end

  defp materialize_locked_attempt(_attempt, _project, _notification_context, _plan, _opts),
    do: {:error, :import_not_queued}

  defp prepare_and_materialize_project(attempt, project, plan) do
    with :ok <- Replacement.prepare_project_in_transaction(attempt, project) do
      Materializer.materialize_locked_project_in_transaction(project, plan,
        conflict_strategy: Shared.strategy_atom(attempt.conflict_strategy)
      )
    end
  end

  defp expire_locked_import_attempt(attempt, notification_context) do
    # Only accepted statuses reach here, and an accepted import that ran out
    # of retention is a real outcome, not a preview that aged out: without the
    # code the UI reports "preview expired, upload again" about an import the
    # user had already started.
    with {:ok, notification_outcome} <-
           NotificationDelivery.deliver(attempt, notification_context, "failure"),
         {:ok, expired} <-
           attempt
           |> ProjectImportAttempt.expired_changeset(TimeHelpers.now(), "import_expired")
           |> Repo.update(),
         :ok <- PlanCleanup.mark_plan_cleanup_pending(expired.plan_storage_key) do
      {:ok, {:expired, expired, notification_outcome}}
    end
  end

  # Lock the project exclusively before the requester, membership, and attempt.
  # Besides preventing deletion, this serializes all imports into the same
  # project and avoids acquiring notification FK parent locks after the attempt
  # row is held.
  defp authorize_worker_locked(attempt, user_id) do
    with %Project{} = project <-
           Project
           |> where([candidate], candidate.id == ^attempt.project_id and is_nil(candidate.deleted_at))
           |> lock("FOR UPDATE")
           |> Repo.one(),
         notification_context = NotificationDelivery.lock_context(attempt, project),
         %ProjectMembership{} = locked_membership <-
           ProjectMembership
           |> where(
             [candidate],
             candidate.project_id == ^attempt.project_id and candidate.user_id == ^user_id
           )
           |> lock("FOR SHARE")
           |> Repo.one(),
         true <- ProjectMembership.can?(locked_membership.role, @import_action) do
      {:ok, project, notification_context}
    else
      nil -> {:error, :unauthorized}
      false -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp finish_import({:materialized, completed, notification_outcome}, started_at, opts) do
    Notifications.publish_committed(notification_outcome)
    PlanCleanup.cleanup_plan(completed, opts)
    Telemetry.emit_stop(:execute, started_at, Telemetry.attempt_metadata(completed, "completed", "none"))
    replay_completed_side_effects(completed)
    {:ok, completed}
  end

  defp finish_import({:already_completed, completed}, _started_at, opts) do
    PlanCleanup.cleanup_plan_if_pending(completed, opts)
    replay_completed_side_effects(completed)
    {:ok, completed}
  end

  defp finish_import({:expired, attempt, notification_outcome}, started_at, opts) do
    Notifications.publish_committed(notification_outcome)
    PlanCleanup.cleanup_plan_if_pending(attempt, opts)

    Telemetry.emit_stop(
      :execute,
      started_at,
      Telemetry.attempt_metadata(attempt, "expired", attempt.error_code || "import_expired")
    )

    # Every terminal transition announces itself. This one covers the worker
    # expiring an attempt at the absolute deadline — without it, an open page
    # kept showing "queued" until its polling backstop noticed.
    Queue.broadcast(attempt)
    {:ok, attempt}
  end

  defp finish_import({:terminal, attempt}, _started_at, opts) do
    PlanCleanup.cleanup_plan_if_pending(attempt, opts)
    {:ok, attempt}
  end

  def replay_completed_side_effects(completed) do
    Collaboration.broadcast_dashboard_change(completed.project_id, :all)
    Queue.broadcast(completed)
  end

  defp mark_running(attempt) do
    attempt
    |> ProjectImportAttempt.running_changeset(TimeHelpers.now())
    |> Repo.update()
  end

  defp run_before_attempt_completion(opts) do
    case Keyword.get(opts, :before_attempt_completion) do
      nil ->
        :ok

      callback when is_function(callback, 0) ->
        callback.()
        :ok
    end
  end

  defp run_before_materialization_transaction(opts) do
    case Keyword.get(opts, :before_materialization_transaction) do
      nil ->
        :ok

      callback when is_function(callback, 0) ->
        callback.()
        :ok
    end
  end

  defp complete_attempt(attempt, counts) do
    attempt
    |> ProjectImportAttempt.completed_changeset(TimeHelpers.now(), Shared.stringify_keys(counts))
    |> Repo.update()
  end

  defp handle_execution_error(attempt, reason, attempt_number, max_attempts, started_at, opts, exception_module) do
    {code, message, permanent?} = Error.classify(reason)
    terminal? = permanent? or attempt_number >= max_attempts

    case persist_execution_error(attempt, code, message, attempt_number, max_attempts, terminal?) do
      {:ok, {:terminal, terminal_attempt}} ->
        PlanCleanup.cleanup_plan_if_pending(terminal_attempt, opts)
        replay_completed_recovery(terminal_attempt)
        {:ok, terminal_attempt}

      {:ok, {:failed, failed, notification_outcome}} ->
        Notifications.publish_committed(notification_outcome)
        metadata = Telemetry.attempt_metadata(failed, "failed", code)
        Error.report(Map.merge(metadata, %{phase: "execute", error_code: code, exception_module: exception_module}))
        PlanCleanup.cleanup_plan(failed, opts)
        Telemetry.emit_stop(:execute, started_at, metadata)
        Queue.broadcast(failed)
        {:ok, failed}

      {:ok, {:retrying, retrying}} ->
        metadata = Telemetry.attempt_metadata(retrying, "retrying", code)
        Error.report(Map.merge(metadata, %{phase: "execute", error_code: code, exception_module: exception_module}))
        Telemetry.emit_stop(:execute, started_at, metadata)
        Queue.broadcast(retrying)
        {:error, :retryable_import_error}

      {:ok, :attempt_not_found} ->
        PlanCleanup.cleanup_plan(attempt, opts)

        Telemetry.emit_stop(
          :execute,
          started_at,
          Telemetry.attempt_metadata(attempt, "discarded", "attempt_not_found")
        )

        {:ok, :attempt_not_found}

      {:error, transition_reason} ->
        {:error, transition_reason}
    end
  end

  defp persist_execution_error(attempt_hint, code, message, attempt_number, max_attempts, terminal?) do
    Repo.transact(fn ->
      notification_context = NotificationDelivery.lock_context(attempt_hint)

      locked_attempt =
        ProjectImportAttempt
        |> where([candidate], candidate.id == ^attempt_hint.id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      case locked_attempt do
        nil ->
          {:ok, :attempt_not_found}

        %ProjectImportAttempt{} = attempt ->
          transition_execution_error(
            attempt,
            notification_context,
            code,
            message,
            attempt_number,
            max_attempts,
            terminal?
          )
      end
    end)
  end

  defp transition_execution_error(
         %{status: status} = attempt,
         _notification_context,
         _code,
         _message,
         _number,
         _max,
         _terminal?
       )
       when status in ["completed", "failed", "expired"] do
    {:ok, {:terminal, attempt}}
  end

  defp transition_execution_error(%{status: status} = attempt, notification_context, code, _message, number, max, true)
       when status in ["queued", "running", "retrying"] do
    attrs = %{
      status: "failed",
      stage: "failed",
      error_code: code,
      error_message: nil,
      error_report: %{attempt: number, max_attempts: max},
      completed_at: TimeHelpers.now()
    }

    with {:ok, notification_outcome} <-
           NotificationDelivery.deliver(attempt, notification_context, "failure"),
         {:ok, failed} <- attempt |> ProjectImportAttempt.failed_changeset(attrs) |> Repo.update(),
         :ok <- PlanCleanup.mark_plan_cleanup_pending(failed.plan_storage_key) do
      {:ok, {:failed, failed, notification_outcome}}
    end
  end

  # Before replacement reaches materialization, no project content has been
  # touched. Keep it queued and cancellable across transient plan/snapshot
  # failures; Oban's durable error list still owns the bounded retry budget.
  defp transition_execution_error(
         %{status: "queued", import_mode: "replace_project"} = attempt,
         _notification_context,
         code,
         _message,
         number,
         max,
         false
       ) do
    attrs = %{
      error_code: code,
      error_message: nil,
      error_report: %{attempt: number, max_attempts: max},
      expires_at: PlanCleanup.bounded_plan_retention_deadline(attempt, TimeHelpers.now())
    }

    with {:ok, queued} <- attempt |> ProjectImportAttempt.queued_retry_changeset(attrs) |> Repo.update() do
      {:ok, {:retrying, queued}}
    end
  end

  defp transition_execution_error(%{status: status} = attempt, _notification_context, code, _message, number, max, false)
       when status in ["queued", "running", "retrying"] do
    attrs = %{
      status: "retrying",
      stage: "retrying",
      error_code: code,
      error_message: nil,
      error_report: %{attempt: number, max_attempts: max},
      started_at: attempt.started_at || TimeHelpers.now(),
      expires_at: PlanCleanup.bounded_plan_retention_deadline(attempt, TimeHelpers.now())
    }

    with {:ok, retrying} <- attempt |> ProjectImportAttempt.retrying_changeset(attrs) |> Repo.update() do
      {:ok, {:retrying, retrying}}
    end
  end

  defp transition_execution_error(_attempt, _notification_context, _code, _message, _number, _max, _terminal?) do
    {:error, :import_not_queued}
  end

  defp replay_completed_recovery(%ProjectImportAttempt{status: "completed"} = completed) do
    replay_completed_side_effects(completed)
  end

  defp replay_completed_recovery(%ProjectImportAttempt{}), do: :ok
end
