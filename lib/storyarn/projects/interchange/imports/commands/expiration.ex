defmodule Storyarn.Projects.Imports.Expiration do
  @moduledoc """
  Reconciling import attempts that stopped moving.

  Two things end up here: previews nobody accepted, and accepted imports whose
  Oban job vanished or overran the absolute retention bound. Both are decided
  under a row lock taken in the same order the worker takes it, so a sweep can
  never terminalize an attempt that is materializing.

  The sweep is also a late safety net for a lost queue notification — but only
  for attempts already past the rolling retention window, which is what the
  candidate query selects. A fresh import whose wake-up was lost is claimed by
  Oban's stager interval, not by this sweep.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Imports.Error
  alias Storyarn.Projects.Imports.NotificationDelivery
  alias Storyarn.Projects.Imports.PlanCleanup
  alias Storyarn.Projects.Imports.ProjectImportAttempt
  alias Storyarn.Projects.Imports.Queue
  alias Storyarn.Projects.Imports.Replacement
  alias Storyarn.Repo

  @absolute_plan_retention_seconds 172_800
  @expiration_retry_backoff_seconds 300
  @executable_import_job_states ~w(available scheduled retryable executing)
  @terminal_import_job_states ~w(cancelled completed discarded)
  @observable_formats ~w(yarn storyarn)

  @doc false
  @spec expire_stale_imports() ::
          {:ok, non_neg_integer()} | {:ok, non_neg_integer(), pos_integer()}
  def expire_stale_imports do
    expire_stale_imports([])
  end

  @doc false
  @spec expire_stale_imports(keyword()) ::
          {:ok, non_neg_integer()} | {:ok, non_neg_integer(), pos_integer()}
  def expire_stale_imports(opts) when is_list(opts) do
    {:ok, %{expired_count: expired_count, failure_count: failure_count}} =
      expire_stale_imports_batch(opts)

    if failure_count == 0,
      do: {:ok, expired_count},
      else: {:ok, expired_count, failure_count}
  end

  @doc false
  @spec expire_stale_imports_batch() ::
          {:ok,
           %{
             expired_count: non_neg_integer(),
             failure_count: non_neg_integer(),
             more?: boolean()
           }}
  def expire_stale_imports_batch do
    expire_stale_imports_batch([])
  end

  @doc false
  @spec expire_stale_imports_batch(keyword()) ::
          {:ok,
           %{
             expired_count: non_neg_integer(),
             failure_count: non_neg_integer(),
             more?: boolean()
           }}
  def expire_stale_imports_batch(opts) when is_list(opts) do
    now = TimeHelpers.now()
    attempts = stale_expiration_candidates(now, stale_batch_size(opts))

    {expired_count, failure_count} =
      Enum.reduce(attempts, {0, 0}, &reconcile_expiration_candidate(&1, now, opts, &2))

    maybe_wake_stale_available_import(now, opts)
    cleanup_failure_count = PlanCleanup.retry_pending_plan_cleanup(opts)
    snapshot_cleanup = Replacement.cleanup_terminal_recovery_snapshots(opts)
    failure_count = failure_count + cleanup_failure_count + snapshot_cleanup.failure_count

    {:ok,
     %{
       expired_count: expired_count,
       failure_count: failure_count,
       more?: expiration_work_remaining?(TimeHelpers.now()) or snapshot_cleanup.more?
     }}
  end

  defp reconcile_expiration_candidate(attempt, now, opts, {expired_count, failure_count}) do
    case expire_stale_attempt_safely(attempt, now, opts) do
      {:ok, {:expired, expired, notification_outcome}} ->
        finish_expired_attempt(expired, notification_outcome, opts, expired_count, failure_count)

      {:ok, {:executable, executable, "available"}} ->
        Queue.wake(executable, opts)
        {expired_count, failure_count}

      {:ok, {:executable, _executable, _job_state}} ->
        {expired_count, failure_count}

      {:ok, :not_stale} ->
        {expired_count, failure_count}

      {:error, reason} ->
        report_expiration_error(attempt, reason)
        defer_failed_expiration(attempt.id, now)
        {expired_count, failure_count + 1}
    end
  end

  defp finish_expired_attempt(expired, notification_outcome, opts, expired_count, failure_count) do
    Platform.publish_notification_delivery(notification_outcome)
    snapshot_cleanup_failure_count = snapshot_cleanup_failure_count(expired)
    expired = Repo.get(ProjectImportAttempt, expired.id) || expired
    emit_expiration_outcome(expired)
    Queue.broadcast(expired)

    plan_cleanup_failure_count =
      expired
      |> PlanCleanup.cleanup_plan(opts)
      |> PlanCleanup.cleanup_failure_count()

    {expired_count + 1, failure_count + plan_cleanup_failure_count + snapshot_cleanup_failure_count}
  end

  defp emit_expiration_outcome(expired) do
    format = if expired.format in @observable_formats, do: expired.format, else: "unknown"
    disposition = if expired.error_code == "import_expired", do: "accepted", else: "preview"

    :telemetry.execute(
      [:storyarn, :import, :expiration, :terminal],
      %{count: 1},
      %{format: format, disposition: disposition}
    )
  end

  defp snapshot_cleanup_failure_count(expired) do
    case Replacement.cleanup_terminal_recovery_snapshot(expired) do
      {:error, _reason} -> 1
      {:ok, _outcome} -> 0
    end
  end

  defp stale_batch_size(opts) do
    case Keyword.get(opts, :stale_batch_size, 100) do
      size when is_integer(size) and size > 0 -> min(size, 100)
      _invalid -> 100
    end
  end

  # Executable jobs are protected during the rolling retention window, but
  # accepted imports also have a hard upper bound. The `updated_at` gate gives
  # an overdue row a bounded retry delay when cancellation or transition fails,
  # so one poison row cannot monopolize every bounded sweep.
  defp stale_expiration_candidates(now, limit) do
    now
    |> stale_expiration_candidates_query()
    |> limit(^limit)
    |> Repo.all()
  end

  defp stale_expiration_candidates_query(now) do
    active_statuses = ProjectImportAttempt.active_statuses()
    absolute_cutoff = DateTime.add(now, -@absolute_plan_retention_seconds, :second)
    retry_cutoff = DateTime.add(now, -@expiration_retry_backoff_seconds, :second)

    from attempt in ProjectImportAttempt,
      left_join: job in Oban.Job,
      on: job.id == attempt.oban_job_id,
      where:
        attempt.status in ^active_statuses and
          ((attempt.expires_at <= ^now and attempt.updated_at <= ^retry_cutoff and
              (attempt.status == "ready" or is_nil(job.id) or
                 job.state in ^@terminal_import_job_states)) or
             (attempt.status != "ready" and attempt.inserted_at <= ^absolute_cutoff and
                attempt.updated_at <= ^retry_cutoff)),
      order_by: [asc: attempt.expires_at, asc: attempt.id],
      select: attempt
  end

  defp expiration_work_remaining?(now) do
    Repo.exists?(stale_expiration_candidates_query(now)) or PlanCleanup.plan_cleanup_work_remaining?(now)
  end

  # Oban notifications are queue-wide, so one wake-up is sufficient even when
  # many stale attempts are still available.
  defp maybe_wake_stale_available_import(now, opts) do
    active_statuses = ProjectImportAttempt.active_statuses()
    absolute_cutoff = DateTime.add(now, -@absolute_plan_retention_seconds, :second)

    attempt =
      Repo.one(
        from attempt in ProjectImportAttempt,
          join: job in Oban.Job,
          on: job.id == attempt.oban_job_id,
          where:
            attempt.status in ^active_statuses and attempt.expires_at <= ^now and
              attempt.inserted_at > ^absolute_cutoff and
              job.state == "available",
          order_by: [asc: attempt.expires_at, asc: attempt.id],
          limit: 1,
          select: attempt
      )

    if attempt, do: Queue.wake(attempt, opts), else: :ok
  end

  def expire_stale_attempt_safely(attempt, now, opts) do
    with :ok <- cancel_import_job_after_absolute_deadline(attempt, now, opts) do
      expire_stale_attempt(attempt, now)
    end
  end

  defp cancel_import_job_after_absolute_deadline(
         %ProjectImportAttempt{status: status, oban_job_id: job_id} = attempt,
         now,
         opts
       )
       when status in ["queued", "running", "retrying"] and is_integer(job_id) do
    if PlanCleanup.absolute_plan_deadline_reached?(attempt, now) do
      job_cancel = Keyword.get(opts, :job_cancel, &Oban.cancel_job/1)
      safely_cancel_import_job(job_cancel, job_id)
    else
      :ok
    end
  end

  defp cancel_import_job_after_absolute_deadline(%ProjectImportAttempt{}, _now, _opts), do: :ok

  def safely_cancel_import_job(job_cancel, job_id) when is_function(job_cancel, 1) do
    case job_cancel.(job_id) do
      :ok -> :ok
      _unexpected -> {:error, :import_job_cancellation_failed}
    end
  rescue
    _exception -> {:error, :import_job_cancellation_failed}
  catch
    _kind, _reason -> {:error, :import_job_cancellation_failed}
  end

  def safely_cancel_import_job(_invalid_job_cancel, _job_id), do: {:error, :import_job_cancellation_failed}

  # Project and requester are notification FK parents, while Oban's pruner can
  # delete a job and then nilify `oban_job_id`. Lock those parents before the
  # job and attempt so project/user deletion and pruning all use one order. The
  # attempt and job id are rechecked under lock; a concurrent replacement is
  # conservatively left for the next sweep.
  def expire_stale_attempt(%ProjectImportAttempt{} = candidate, now) do
    Repo.transact(fn ->
      notification_context = NotificationDelivery.lock_context(candidate)
      job_state = lock_import_job_state(candidate.oban_job_id)

      candidate.id
      |> lock_stale_attempt(now)
      |> classify_stale_attempt(
        notification_context,
        candidate.oban_job_id,
        job_state,
        now,
        PlanCleanup.absolute_plan_deadline_reached?(candidate, now)
      )
    end)
  end

  defp lock_stale_attempt(attempt_id, now) do
    active_statuses = ProjectImportAttempt.active_statuses()
    absolute_cutoff = DateTime.add(now, -@absolute_plan_retention_seconds, :second)

    ProjectImportAttempt
    |> where(
      [candidate],
      candidate.id == ^attempt_id and candidate.status in ^active_statuses and
        (candidate.expires_at <= ^now or candidate.inserted_at <= ^absolute_cutoff)
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp classify_stale_attempt(nil, _notification_context, _candidate_job_id, _job_state, _now, _absolute_deadline?),
    do: {:ok, :not_stale}

  defp classify_stale_attempt(
         %ProjectImportAttempt{status: "ready", oban_job_id: nil} = attempt,
         notification_context,
         _candidate_job_id,
         _job_state,
         now,
         _absolute_deadline?
       ) do
    expire_stale_attempt_record(attempt, notification_context, now)
  end

  defp classify_stale_attempt(
         %ProjectImportAttempt{oban_job_id: job_id},
         _notification_context,
         candidate_job_id,
         _job_state,
         _now,
         _absolute_deadline?
       )
       when job_id != candidate_job_id do
    {:ok, :not_stale}
  end

  defp classify_stale_attempt(
         %ProjectImportAttempt{} = attempt,
         notification_context,
         _candidate_job_id,
         job_state,
         now,
         absolute_deadline?
       ) do
    case job_state do
      state when state in @executable_import_job_states and absolute_deadline? ->
        {:error, :import_job_cancellation_incomplete}

      state when state in @executable_import_job_states ->
        {:ok, {:executable, attempt, state}}

      state when state in @terminal_import_job_states or state == :absent ->
        expire_stale_attempt_record(attempt, notification_context, now)

      _unknown_state when absolute_deadline? ->
        {:error, :import_job_cancellation_incomplete}

      _unknown_state ->
        # Preserve on an unknown state. Deleting a plan is irreversible, while
        # the next sweep can safely reconsider once Oban reports a known state.
        {:ok, :not_stale}
    end
  end

  # An accepted import expiring is a real outcome the user must be told about;
  # a `ready` preview aging out carries no code and reads as exactly that.
  def expire_stale_attempt_record(attempt, notification_context, now) do
    error_code = if attempt.status in ~w(queued running retrying), do: "import_expired"
    notification_status = if error_code, do: "failure"

    with {:ok, notification_outcome} <-
           deliver_expiration_result(attempt, notification_context, notification_status),
         {:ok, expired} <- attempt |> ProjectImportAttempt.expired_changeset(now, error_code) |> Repo.update(),
         :ok <- PlanCleanup.mark_plan_cleanup_pending(expired.plan_storage_key) do
      {:ok, {:expired, expired, notification_outcome}}
    end
  end

  defp deliver_expiration_result(_attempt, _notification_context, nil), do: {:ok, :suppressed}

  defp deliver_expiration_result(attempt, notification_context, status),
    do: NotificationDelivery.deliver(attempt, notification_context, status)

  def lock_import_job_state(nil), do: :absent

  def lock_import_job_state(job_id) do
    job =
      Oban.Job
      |> where([job], job.id == ^job_id)
      |> lock("FOR SHARE")
      |> Repo.one()

    case job do
      %Oban.Job{state: state} -> state
      nil -> :absent
    end
  end

  @doc false
  def import_job_state(nil), do: :absent

  def import_job_state(job_id) do
    case Repo.get(Oban.Job, job_id) do
      %Oban.Job{state: state} -> state
      nil -> :absent
    end
  end

  # Exclusive variant for the caller that goes on to update the job row in the
  # same transaction (`cancel_import` — `Oban.cancel_job/1` dispatches onto the
  # caller's connection inside an open transaction). Taken `FOR SHARE` the later
  # update would upgrade the lock, and two concurrent cancels of the same
  # attempt could deadlock each other on the upgrade.
  def lock_import_job_state_for_update(nil), do: :absent

  def lock_import_job_state_for_update(job_id) do
    job =
      Oban.Job
      |> where([job], job.id == ^job_id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    case job do
      %Oban.Job{state: state} -> state
      nil -> :absent
    end
  end

  defp report_expiration_error(attempt, reason) do
    {error_code, _message, _permanent?} = Error.classify(reason, attempt.format)

    Error.report(%{
      format: attempt.format,
      parser_version: attempt.parser_version,
      import_mode: attempt.import_mode,
      phase: "expiration",
      error_code: error_code,
      exception_module: "none"
    })
  end

  defp defer_failed_expiration(attempt_id, now) do
    active_statuses = ProjectImportAttempt.active_statuses()

    Repo.update_all(
      from(attempt in ProjectImportAttempt,
        where: attempt.id == ^attempt_id and attempt.status in ^active_statuses
      ),
      set: [updated_at: now]
    )

    :ok
  end
end
