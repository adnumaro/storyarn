defmodule Storyarn.Projects.Imports.PlanCleanup do
  @moduledoc """
  Lifecycle of the encrypted import plan in object storage.

  A plan outlives the request that stored it, so deletion is driven by a durable
  `PlanCleanupRequest` rather than by whoever happened to finish last. Every
  transition is idempotent and every failure is retried on a bounded schedule:
  the one outcome that must never happen is a plan that no row points at.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Imports.Error
  alias Storyarn.Projects.Imports.PlanCleanupRequest
  alias Storyarn.Projects.Imports.PlanStorage
  alias Storyarn.Projects.Imports.ProjectImportAttempt
  alias Storyarn.Repo

  @plan_retention_seconds 86_400
  @cleanup_tombstone_retention_seconds 604_800
  @cleanup_delete_lease_seconds 300
  @cleanup_retry_base_seconds 60
  @cleanup_retry_max_seconds 3_600

  @doc false
  def plan_retention_seconds, do: @plan_retention_seconds

  @absolute_plan_retention_seconds 172_800

  @doc """
  Deadlines that bound how long an encrypted plan may be retained.

  A ready preview expires on its own rolling window, but an accepted import must
  still not keep its plan forever, so every deadline is also clamped by an
  absolute bound measured from when the attempt was created.
  """

  def absolute_plan_deadline(%ProjectImportAttempt{inserted_at: inserted_at}) do
    DateTime.add(inserted_at, @absolute_plan_retention_seconds, :second)
  end

  def absolute_plan_deadline_reached?(%ProjectImportAttempt{} = attempt, now) do
    attempt
    |> absolute_plan_deadline()
    |> DateTime.compare(now)
    |> Kernel.in([:lt, :eq])
  end

  def bounded_plan_retention_deadline(%ProjectImportAttempt{} = attempt, now) do
    rolling_deadline = DateTime.add(now, @plan_retention_seconds, :second)
    absolute_deadline = absolute_plan_deadline(attempt)

    if DateTime.after?(rolling_deadline, absolute_deadline),
      do: absolute_deadline,
      else: rolling_deadline
  end

  @doc """
  Earliest moment a retained plan may be swept: whichever of the attempt's own
  expiry and the absolute retention bound comes first.
  """
  def plan_cleanup_deadline(attempt) do
    min_datetime(attempt.expires_at, absolute_plan_deadline(attempt))
  end

  defp min_datetime(left, right) do
    if DateTime.after?(left, right), do: right, else: left
  end

  def mark_plan_cleanup_pending(storage_key), do: mark_plan_cleanup_pending(Repo, storage_key)

  defp mark_plan_cleanup_pending(repo, storage_key) do
    now = TimeHelpers.now()

    case repo.update_all(
           from(request in PlanCleanupRequest,
             where:
               request.plan_storage_key == ^storage_key and
                 request.state in ["reserved", "retained", "pending"]
           ),
           set: [state: "pending", cleanup_after: now, updated_at: now]
         ) do
      {1, _rows} -> :ok
      {_count, _rows} -> {:error, :plan_cleanup_request_unavailable}
    end
  end

  def cleanup_reserved_plan(cleanup_request) do
    with {:ok, pending} <- force_plan_cleanup(cleanup_request.id) do
      cleanup_request(pending, [])
    end

    :ok
  end

  # A failed or timed-out PUT has an ambiguous remote outcome: object storage
  # may still commit it after the caller receives the error. Invalidate any
  # stale delete claim, then wait a full retention window before the scanner's
  # definitive delete instead of falsely declaring the key clean immediately.
  def defer_uncertain_plan_cleanup(%PlanCleanupRequest{} = request) do
    now = TimeHelpers.now()
    cleanup_after = DateTime.add(now, @plan_retention_seconds, :second)

    Repo.update_all(
      from(candidate in PlanCleanupRequest, where: candidate.id == ^request.id),
      set: [
        state: "pending",
        cleanup_after: cleanup_after,
        completed_at: nil,
        last_error_code: "upload_outcome_uncertain",
        updated_at: now
      ],
      inc: [generation: 1]
    )

    :ok
  end

  def cleanup_plan(attempt, opts \\ []) do
    with {:ok, cleanup_request} <- ensure_cleanup_request(attempt),
         {:ok, pending} <- request_plan_cleanup(cleanup_request) do
      cleanup_request(pending, opts)
    else
      _error ->
        report_cleanup_failure(attempt.format, attempt.parser_version)
        {:error, :plan_cleanup_failed}
    end
  end

  defp ensure_cleanup_request(attempt) do
    case Repo.get(PlanCleanupRequest, attempt.plan_cleanup_request_id) do
      %PlanCleanupRequest{plan_storage_key: storage_key} = request
      when storage_key == attempt.plan_storage_key ->
        {:ok, request}

      %PlanCleanupRequest{} ->
        {:error, :plan_cleanup_request_mismatch}

      nil ->
        ensure_legacy_cleanup_request(attempt)
    end
  end

  defp ensure_legacy_cleanup_request(attempt) do
    attrs = %{
      plan_storage_key: attempt.plan_storage_key,
      format: attempt.format,
      parser_version: attempt.parser_version,
      state: "pending",
      cleanup_after: TimeHelpers.now()
    }

    %PlanCleanupRequest{}
    |> PlanCleanupRequest.reservation_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, request} -> {:ok, request}
      {:error, _changeset} -> cleanup_request_after_insert_race(attempt.plan_storage_key)
    end
  end

  defp cleanup_request_after_insert_race(storage_key) do
    case Repo.get_by(PlanCleanupRequest, plan_storage_key: storage_key) do
      %PlanCleanupRequest{} = request -> {:ok, request}
      nil -> {:error, :plan_cleanup_request_unavailable}
    end
  end

  defp request_plan_cleanup(%PlanCleanupRequest{} = request) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(candidate in PlanCleanupRequest,
        where: candidate.id == ^request.id and candidate.state in ["reserved", "retained", "pending"]
      ),
      set: [state: "pending", cleanup_after: now, completed_at: nil, updated_at: now]
    )

    case Repo.get(PlanCleanupRequest, request.id) do
      %PlanCleanupRequest{} = pending -> {:ok, pending}
      nil -> {:error, :plan_cleanup_request_unavailable}
    end
  end

  defp force_plan_cleanup(request_id) do
    now = TimeHelpers.now()

    case Repo.update_all(
           from(candidate in PlanCleanupRequest, where: candidate.id == ^request_id),
           set: [
             state: "pending",
             cleanup_after: now,
             completed_at: nil,
             last_error_code: nil,
             updated_at: now
           ],
           inc: [generation: 1]
         ) do
      {1, _rows} ->
        {:ok, Repo.get!(PlanCleanupRequest, request_id)}

      {_count, _rows} ->
        {:error, :plan_cleanup_request_unavailable}
    end
  end

  def cleanup_request(%PlanCleanupRequest{} = request, opts) do
    with :ok <- run_before_cleanup_claim(opts, request),
         {:ok, claim} <- claim_plan_cleanup(request.id) do
      cleanup_claim(claim, opts)
    end
  end

  defp run_before_cleanup_claim(opts, request) do
    case Keyword.get(opts, :before_cleanup_claim) do
      nil ->
        :ok

      callback when is_function(callback, 1) ->
        callback.(request)
        :ok
    end
  end

  defp claim_plan_cleanup(request_id) do
    now = TimeHelpers.now()
    lease_until = DateTime.add(now, @cleanup_delete_lease_seconds, :second)

    Repo.transact(fn ->
      request =
        PlanCleanupRequest
        |> where([candidate], candidate.id == ^request_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      case request do
        %PlanCleanupRequest{} = request ->
          claim_locked_plan_cleanup(request, now, lease_until)

        nil ->
          {:error, :plan_cleanup_request_unavailable}
      end
    end)
  end

  defp claim_locked_plan_cleanup(request, now, lease_until) do
    cond do
      cleanup_claimable?(request, now) ->
        request
        |> Ecto.Changeset.change(
          state: "deleting",
          cleanup_after: lease_until,
          generation: request.generation + 1,
          updated_at: now
        )
        |> Repo.update()

      request.state == "completed" ->
        {:ok, :already_completed}

      request.state == "deleting" ->
        {:ok, :in_progress}

      true ->
        {:ok, :not_due}
    end
  end

  defp cleanup_claimable?(%PlanCleanupRequest{state: "retained", project_id: nil}, _now), do: true

  defp cleanup_claimable?(%PlanCleanupRequest{state: state, cleanup_after: cleanup_after}, now)
       when state in ["reserved", "pending", "deleting"] and not is_nil(cleanup_after) do
    DateTime.compare(cleanup_after, now) in [:lt, :eq]
  end

  defp cleanup_claimable?(_request, _now), do: false

  defp cleanup_claim(status, _opts) when status in [:already_completed, :in_progress, :not_due], do: :ok

  defp cleanup_claim(%PlanCleanupRequest{} = claim, opts) do
    delete_plan = Keyword.get(opts, :plan_delete, &PlanStorage.delete/1)

    case safely_delete_plan(delete_plan, claim.plan_storage_key) do
      :ok ->
        case complete_plan_cleanup(claim) do
          :ok ->
            :ok

          {:error, _reason} = error ->
            report_cleanup_failure(claim.format, claim.parser_version)
            error
        end

      {:error, _reason} ->
        record_plan_cleanup_failure(claim)
        report_cleanup_failure(claim.format, claim.parser_version)
        {:error, :plan_cleanup_failed}
    end
  end

  defp safely_delete_plan(delete_plan, storage_key) do
    case delete_plan.(storage_key) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      _other -> {:error, :unexpected_delete_result}
    end
  rescue
    _exception -> {:error, :delete_exception}
  catch
    _kind, _reason -> {:error, :delete_exception}
  end

  defp complete_plan_cleanup(request) do
    now = TimeHelpers.now()

    case Repo.update_all(
           from(candidate in PlanCleanupRequest,
             where:
               candidate.id == ^request.id and candidate.state == "deleting" and
                 candidate.generation == ^request.generation
           ),
           set: [
             state: "completed",
             project_id: nil,
             completed_at: now,
             cleanup_after: nil,
             last_error_code: nil,
             updated_at: now
           ]
         ) do
      {1, _rows} ->
        :ok

      {_count, _rows} ->
        case Repo.get(PlanCleanupRequest, request.id) do
          %PlanCleanupRequest{state: "completed"} -> :ok
          _missing_or_changed -> {:error, :plan_cleanup_request_update_failed}
        end
    end
  end

  defp record_plan_cleanup_failure(request) do
    now = TimeHelpers.now()
    retry_at = DateTime.add(now, cleanup_retry_delay(request.attempt_count), :second)

    Repo.update_all(
      from(candidate in PlanCleanupRequest,
        where:
          candidate.id == ^request.id and candidate.state == "deleting" and
            candidate.generation == ^request.generation
      ),
      set: [
        state: "pending",
        cleanup_after: retry_at,
        last_error_code: "plan_cleanup_failed",
        updated_at: now
      ],
      inc: [attempt_count: 1]
    )

    :ok
  end

  defp cleanup_retry_delay(attempt_count) do
    exponent = min(attempt_count, 6)
    min(@cleanup_retry_base_seconds * Integer.pow(2, exponent), @cleanup_retry_max_seconds)
  end

  defp report_cleanup_failure(format, parser_version) do
    Error.report(%{
      format: format,
      parser_version: parser_version,
      phase: "cleanup",
      error_code: "plan_cleanup_failed",
      exception_module: "none"
    })
  end

  def cleanup_plan_if_pending(%ProjectImportAttempt{} = attempt, opts \\ []) do
    cleanup_plan(attempt, opts)
  end

  def retry_pending_plan_cleanup(opts) do
    terminal_failure_count = retry_terminal_attempt_cleanup(opts)
    due_failure_count = retry_due_plan_cleanup(opts)
    purge_completed_cleanup_tombstones()
    terminal_failure_count + due_failure_count
  end

  def plan_cleanup_work_remaining?(now) do
    terminal_attempt_cleanup_remaining?() or due_plan_cleanup_remaining?(now)
  end

  defp terminal_attempt_cleanup_remaining? do
    ProjectImportAttempt
    |> join(:inner, [attempt], request in PlanCleanupRequest, on: request.id == attempt.plan_cleanup_request_id)
    |> where(
      [attempt, request],
      attempt.status in ["completed", "failed", "expired"] and request.state == "retained"
    )
    |> Repo.exists?()
  end

  defp due_plan_cleanup_remaining?(now) do
    PlanCleanupRequest
    |> where(
      [request],
      (request.state in ["reserved", "pending", "deleting"] and
         not is_nil(request.cleanup_after) and request.cleanup_after <= ^now) or
        (request.state == "retained" and is_nil(request.project_id))
    )
    |> Repo.exists?()
  end

  defp retry_terminal_attempt_cleanup(opts) do
    ProjectImportAttempt
    |> join(:inner, [attempt], request in PlanCleanupRequest, on: request.id == attempt.plan_cleanup_request_id)
    |> where(
      [attempt, request],
      attempt.status in ["completed", "failed", "expired"] and request.state == "retained"
    )
    |> order_by([attempt], asc: attempt.id)
    |> limit(100)
    |> Repo.all()
    |> Enum.reduce(0, fn attempt, failure_count ->
      failure_count + cleanup_failure_count(cleanup_plan(attempt, opts))
    end)
  end

  defp retry_due_plan_cleanup(opts) do
    now = TimeHelpers.now()

    PlanCleanupRequest
    |> where(
      [request],
      (request.state in ["reserved", "pending", "deleting"] and
         not is_nil(request.cleanup_after) and request.cleanup_after <= ^now) or
        (request.state == "retained" and is_nil(request.project_id))
    )
    |> order_by([request], asc_nulls_first: request.cleanup_after, asc: request.id)
    |> limit(100)
    |> Repo.all()
    |> Enum.reduce(0, fn request, failure_count ->
      failure_count + cleanup_failure_count(cleanup_request(request, opts))
    end)
  end

  def cleanup_failure_count(:ok), do: 0
  def cleanup_failure_count({:error, _reason}), do: 1
  def cleanup_failure_count(_unexpected), do: 1

  defp purge_completed_cleanup_tombstones do
    cutoff = DateTime.add(TimeHelpers.now(), -@cleanup_tombstone_retention_seconds, :second)

    Repo.delete_all(
      from(request in PlanCleanupRequest,
        where: request.state == "completed" and request.completed_at <= ^cutoff
      )
    )

    :ok
  end
end
