defmodule Storyarn.Imports do
  @moduledoc """
  The Imports context.

  Handles importing project data from external files. Supports parsing,
  previewing, conflict detection, and execution of imports.

  ## Import flow

  1. `parse_file/2` — Detect format from the uploaded filename and parse it
  2. `preview/2` — Generate preview with conflict detection
  3. `execute/3` — Run the import with a conflict strategy
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Storyarn.Accounts.Scope
  alias Storyarn.Collaboration
  alias Storyarn.Imports.Error
  alias Storyarn.Imports.ImportPlan
  alias Storyarn.Imports.Materializer
  alias Storyarn.Imports.ParserRegistry
  alias Storyarn.Imports.Parsers.Yarn.ReviewDecisions
  alias Storyarn.Imports.PlanCleanupRequest
  alias Storyarn.Imports.PlanStorage
  alias Storyarn.Imports.ProjectImportAttempt
  alias Storyarn.Imports.SourceBundle
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Workers.ImportProjectWorker

  @plan_retention_seconds 86_400
  @cleanup_tombstone_retention_seconds 604_800
  @cleanup_delete_lease_seconds 300
  @cleanup_retry_base_seconds 60
  @cleanup_retry_max_seconds 3_600
  @expiration_retry_backoff_seconds 300
  @absolute_plan_retention_seconds 172_800
  @plan_store_timeout 300_000
  @materialization_timeout 300_000
  @max_safe_import_attempt_id 9_007_199_254_740_991
  @executable_import_job_states ~w(available scheduled retryable executing)
  @terminal_import_job_states ~w(cancelled completed discarded)

  @doc """
  Parse an import file and detect its format.

  The filename is required: format selection is explicit, off the extension,
  never a heuristic on the contents. The arity-1 form existed only as a
  backwards-compatible entry point for the native Storyarn JSON format, which
  no longer exists.
  """
  @spec parse_file(String.t(), binary()) :: {:ok, ImportPlan.t()} | {:error, atom() | tuple()}
  def parse_file(filename, binary) when is_binary(filename) and is_binary(binary) do
    with {:ok, parser} <- ParserRegistry.parser_for(filename),
         {:ok, bundle} <- SourceBundle.open(filename, binary),
         {:ok, %ImportPlan{} = plan} <- parser.parse(bundle),
         false <- ImportPlan.error?(plan) do
      {:ok, plan}
    else
      true -> {:error, :import_plan_has_errors}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Preview what an import would do without executing it.

  Requires the complete `ImportPlan` so blocking parser issues cannot be
  discarded by passing only its native data map.

  Returns a preview struct with entity counts and detected conflicts.
  """
  def preview(project_id, %ImportPlan{data: parsed_data} = plan) do
    if ImportPlan.error?(plan) do
      {:error, :import_plan_has_errors}
    else
      case Materializer.preview(project_id, parsed_data) do
        {:ok, preview} ->
          {:ok, Map.put(preview, :issue_summary, import_issue_summary(plan))}

        error ->
          error
      end
    end
  end

  def preview(_project_id, parsed_data) when is_map(parsed_data), do: {:error, :import_plan_required}

  defp import_issue_summary(%ImportPlan{metadata: metadata}) do
    %{
      warning_count: non_negative_metadata_count(metadata, :warning_count),
      error_count: non_negative_metadata_count(metadata, :error_count),
      issue_count: non_negative_metadata_count(metadata, :issue_count),
      issues_truncated: Map.get(metadata, :issues_truncated) == true,
      counts_by_code:
        metadata
        |> Map.get(:issue_counts_by_code, %{})
        |> Enum.filter(fn {code, count} ->
          (is_atom(code) or is_binary(code)) and is_integer(count) and count > 0
        end)
        |> Map.new(fn {code, count} -> {to_string(code), count} end)
    }
  end

  defp non_negative_metadata_count(metadata, key) do
    case Map.get(metadata, key, 0) do
      count when is_integer(count) and count >= 0 -> count
      _invalid -> 0
    end
  end

  @doc """
  Execute an import into a project.

  ## Authorization

  Caller MUST verify the current user has `:edit_content` permission on the
  target project before calling this function. The Imports context does not
  enforce authorization — that responsibility belongs to the LiveView layer.

  ## Options

  - `:conflict_strategy` — `:skip` | `:overwrite` | `:rename` (default: `:skip`)

  Requires the complete `ImportPlan`; raw native maps are intentionally
  rejected so parser errors cannot be bypassed.

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  def execute(project, plan, opts \\ [])

  def execute(project, %ImportPlan{} = plan, opts) do
    cond do
      ImportPlan.error?(plan) ->
        {:error, :import_plan_has_errors}

      not ReviewDecisions.resolved?(plan) ->
        {:error, :invalid_import_review}

      true ->
        Materializer.execute(project, plan, opts)
    end
  end

  def execute(_project, parsed_data, _opts) when is_map(parsed_data), do: {:error, :import_plan_required}

  @doc """
  Parses, validates, previews, encrypts, and persists an import for later
  execution. The caller scope is authorized again here even when a LiveView
  has already checked its socket membership.
  """
  @spec prepare_import(Scope.t(), Project.t(), String.t(), binary()) ::
          {:ok, ProjectImportAttempt.t(), map()} | {:error, term()}
  def prepare_import(%Scope{} = scope, %Project{} = project, filename, binary) do
    prepare_import(scope, project, filename, binary, [])
  end

  @doc false
  def prepare_import(%Scope{} = scope, %Project{} = project, filename, binary, opts)
      when is_binary(filename) and is_binary(binary) and is_list(opts) do
    started_at = System.monotonic_time()
    initial_metadata = source_metadata(filename)

    try do
      with {:ok, _project, _membership} <- Projects.authorize(scope, project.id, :edit_content),
           {:ok, %ImportPlan{} = plan} <- parse_file(filename, binary),
           {:ok, preview} <- preview(project.id, plan),
           {:ok, attempt} <- persist_import_plan(scope, project, plan, preview, binary, opts) do
        emit_stop(:prepare, started_at, plan_metadata(plan, "completed", "none"))
        broadcast(attempt)
        {:ok, attempt, preview}
      else
        {:error, reason} ->
          report_prepare_error(reason, initial_metadata, started_at)
          {:error, reason}
      end
    rescue
      exception ->
        report_exception(:prepare, initial_metadata, exception, started_at)
        {:error, :unexpected_import_error}
    catch
      _kind, _reason ->
        report_prepare_error(:unexpected_import_error, initial_metadata, started_at)
        {:error, :unexpected_import_error}
    end
  end

  @doc """
  Persists an incomplete Yarn review inside the encrypted plan.

  The durable attempt row and telemetry remain content-free. Each revision is
  written to a new storage key and the attempt pointer is swapped only after
  authorization and state are revalidated under database locks.
  """
  @spec save_import_review(Scope.t(), pos_integer(), list()) ::
          {:ok, ProjectImportAttempt.t(), map()} | {:error, term()}
  def save_import_review(%Scope{} = scope, attempt_id, decisions) do
    save_import_review(scope, attempt_id, decisions, [])
  end

  @doc false
  def save_import_review(%Scope{} = scope, attempt_id, decisions, opts)
      when is_integer(attempt_id) and attempt_id > 0 and is_list(opts) do
    case revise_import_review(scope, attempt_id, opts, fn plan ->
           ReviewDecisions.save_draft(plan, decisions)
         end) do
      {:ok, attempt, preview, _revised_plan} -> {:ok, attempt, preview}
      error -> error
    end
  end

  def save_import_review(%Scope{}, _attempt_id, _decisions, _opts), do: {:error, :not_found}

  @doc """
  Applies every explicit Yarn review decision and returns the exact preview
  that can subsequently be queued.

  No import job is created here. The caller must present the returned
  confirmation fingerprint when enqueueing, which prevents a stale browser
  preview from accepting a different plan revision.
  """
  @spec resolve_import_review(Scope.t(), pos_integer(), boolean(), list()) ::
          {:ok, ProjectImportAttempt.t(), map(), String.t()} | {:error, term()}
  def resolve_import_review(%Scope{} = scope, attempt_id, acknowledged?, decisions) do
    resolve_import_review(scope, attempt_id, acknowledged?, decisions, [])
  end

  @doc false
  def resolve_import_review(%Scope{} = scope, attempt_id, acknowledged?, decisions, opts)
      when is_integer(attempt_id) and attempt_id > 0 and is_boolean(acknowledged?) and is_list(opts) do
    with {:ok, attempt, preview, plan} <-
           revise_import_review(scope, attempt_id, opts, fn plan ->
             ReviewDecisions.apply(plan, acknowledged?, decisions)
           end),
         {:ok, fingerprint} <- ReviewDecisions.confirmation_fingerprint(plan) do
      {:ok, attempt, preview, fingerprint}
    end
  end

  def resolve_import_review(%Scope{}, _attempt_id, _acknowledged?, _decisions, _opts), do: {:error, :not_found}

  @doc """
  Queues a ready import. The Oban payload contains only `attempt_id`.
  """
  @spec enqueue_import(Scope.t(), pos_integer(), String.t() | atom()) ::
          {:ok, ProjectImportAttempt.t()} | {:error, term()}
  def enqueue_import(%Scope{} = scope, attempt_id, strategy) do
    enqueue_import(scope, attempt_id, strategy, [])
  end

  @doc false
  def enqueue_import(%Scope{} = scope, attempt_id, strategy, opts) when is_list(opts) do
    with {:ok, strategy} <- normalize_strategy(strategy),
         %ProjectImportAttempt{} = attempt <- Repo.get(ProjectImportAttempt, attempt_id),
         {:ok, project, _membership} <- Projects.authorize(scope, attempt.project_id, :edit_content) do
      fn -> enqueue_locked_attempt(attempt.id, project.id, scope.user.id, strategy, opts) end
      |> Repo.transact()
      |> case do
        {:ok, {:queued, attempt}} ->
          wake_import_queue(attempt, opts)
          broadcast(attempt)
          {:ok, attempt}

        {:ok, {:rejected, attempt, reason}} ->
          cleanup_plan(attempt, opts)
          broadcast(attempt)
          {:error, reason}

        error ->
          error
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec perform_import(pos_integer(), keyword()) ::
          {:ok, ProjectImportAttempt.t() | :attempt_not_found} | {:error, term()}
  def perform_import(attempt_id, opts \\ []) do
    case get_attempt(attempt_id) do
      nil ->
        {:ok, :attempt_not_found}

      %ProjectImportAttempt{} = attempt ->
        case attempt.status do
          "completed" ->
            cleanup_plan_if_pending(attempt)
            replay_completed_side_effects(attempt)
            {:ok, attempt}

          status when status in ["failed", "expired"] ->
            cleanup_plan_if_pending(attempt)
            {:ok, attempt}

          "ready" ->
            {:error, :import_not_queued}

          _status ->
            run_import(attempt, opts)
        end
    end
  end

  @spec get_import_attempt(Scope.t(), pos_integer()) ::
          {:ok, ProjectImportAttempt.t()} | {:error, :not_found | :unauthorized}
  def get_import_attempt(%Scope{} = scope, attempt_id) do
    with %ProjectImportAttempt{} = attempt <- Repo.get(ProjectImportAttempt, attempt_id),
         {:ok, _project, _membership} <- Projects.authorize(scope, attempt.project_id, :view) do
      {:ok, attempt}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Recovers the newest active import owned by the current user in a project.

  The durable attempt lookup is scoped by both project and user. Authorization
  is checked before the lookup and is checked again by `resume_import/4` while
  the attempt is reconciled and, for ready attempts, its preview is rebuilt.
  """
  @spec resume_latest_active_import(Scope.t(), Project.t()) ::
          {:ok, ProjectImportAttempt.t(), map() | nil} | {:ok, nil} | {:error, term()}
  def resume_latest_active_import(%Scope{} = scope, %Project{} = project) do
    resume_latest_active_import(scope, project, [])
  end

  @doc false
  def resume_latest_active_import(%Scope{} = scope, %Project{} = project, opts) when is_list(opts) do
    case Projects.authorize(scope, project.id, :edit_content) do
      {:ok, _project, _membership} ->
        case latest_active_import_attempt(project.id, scope.user.id) do
          %ProjectImportAttempt{} = attempt ->
            resume_import(scope, project, attempt.id, opts)

          nil ->
            {:ok, nil}
        end

      _not_authorized ->
        {:error, :not_found}
    end
  end

  defp latest_active_import_attempt(project_id, user_id) do
    active_statuses = ProjectImportAttempt.active_statuses()

    Repo.one(
      from attempt in ProjectImportAttempt,
        where:
          attempt.project_id == ^project_id and attempt.user_id == ^user_id and
            attempt.status in ^active_statuses,
        order_by: [desc: attempt.inserted_at, desc: attempt.id],
        limit: 1
    )
  end

  @doc """
  Recovers the durable state for an import in the supplied project.

  Ready attempts rebuild their preview from the encrypted plan. Once an import
  has been accepted, its durable attempt is sufficient and the preview is no
  longer loaded.
  """
  @spec resume_import(Scope.t(), Project.t(), pos_integer()) ::
          {:ok, ProjectImportAttempt.t(), map() | nil} | {:error, term()}
  def resume_import(%Scope{} = scope, %Project{} = project, attempt_id) do
    resume_import(scope, project, attempt_id, [])
  end

  @doc false
  def resume_import(%Scope{} = scope, %Project{} = project, attempt_id, opts)
      when is_integer(attempt_id) and attempt_id > 0 and attempt_id <= @max_safe_import_attempt_id and is_list(opts) do
    case Projects.authorize(scope, project.id, :edit_content) do
      {:ok, _project, _membership} ->
        resume_authorized_import(scope, project, attempt_id, opts)

      _not_authorized ->
        {:error, :not_found}
    end
  end

  def resume_import(%Scope{}, %Project{}, _attempt_id, _opts), do: {:error, :not_found}

  defp resume_authorized_import(scope, project, attempt_id, opts) do
    with {:ok, attempt} <- reconcile_resumed_attempt(project.id, attempt_id, opts) do
      preview_result = resume_preview(project.id, attempt, opts)

      with {:ok, _project, _membership} <- Projects.authorize(scope, project.id, :edit_content),
           {:ok, current_attempt} <- reconcile_resumed_attempt(project.id, attempt_id, opts) do
        finish_resumed_import(attempt, current_attempt, preview_result, opts)
      else
        _not_authorized_or_missing -> {:error, :not_found}
      end
    end
  end

  defp resume_preview(project_id, %ProjectImportAttempt{status: "ready"} = attempt, opts) do
    plan_load = Keyword.get(opts, :plan_load, &PlanStorage.load/1)

    result =
      with {:ok, plan} <- safely_load_plan(plan_load, attempt.plan_storage_key) do
        safely_build_resumed_preview(project_id, plan)
      end

    report_resume_failure(attempt, result)
    result
  end

  defp resume_preview(_project_id, %ProjectImportAttempt{}, _opts), do: {:ok, nil}

  defp safely_build_resumed_preview(project_id, %ImportPlan{} = plan) do
    case preview(project_id, plan) do
      {:ok, preview} -> {:ok, preview}
      {:error, reason} -> {:error, reason}
      _unexpected -> {:error, :unexpected_import_error}
    end
  rescue
    _exception -> {:error, :unexpected_import_error}
  catch
    _kind, _reason -> {:error, :unexpected_import_error}
  end

  defp report_resume_failure(attempt, {:error, reason}) do
    {code, _message, _permanent?} = Error.classify(reason)

    Error.report(%{
      format: attempt.format,
      parser_version: attempt.parser_version,
      phase: "resume",
      error_code: code,
      exception_module: "none"
    })
  end

  defp report_resume_failure(_attempt, _result), do: :ok

  defp finish_resumed_import(
         %ProjectImportAttempt{status: "ready", plan_storage_key: storage_key},
         %ProjectImportAttempt{status: "ready", plan_storage_key: storage_key} = current_attempt,
         {:ok, preview},
         _opts
       ) do
    {:ok, current_attempt, preview}
  end

  defp finish_resumed_import(
         %ProjectImportAttempt{status: "ready", plan_storage_key: storage_key},
         %ProjectImportAttempt{status: "ready", plan_storage_key: storage_key},
         {:error, reason},
         _opts
       ) do
    {:error, reason}
  end

  defp finish_resumed_import(
         _initial_attempt,
         %ProjectImportAttempt{status: "completed"} = current_attempt,
         _preview_result,
         opts
       ) do
    cleanup_plan_if_pending(current_attempt, opts)
    replay_completed_side_effects(current_attempt)
    {:ok, current_attempt, nil}
  end

  defp finish_resumed_import(_initial_attempt, current_attempt, _preview_result, opts) do
    maybe_wake_resumed_import(current_attempt, opts)
    {:ok, current_attempt, nil}
  end

  defp reconcile_resumed_attempt(project_id, attempt_id, opts) do
    case Repo.get_by(ProjectImportAttempt, id: attempt_id, project_id: project_id) do
      %ProjectImportAttempt{status: status} = candidate
      when status in ["ready", "queued", "running", "retrying"] ->
        reconcile_active_resumed_attempt(candidate, project_id, attempt_id, opts)

      %ProjectImportAttempt{} = attempt ->
        {:ok, attempt}

      nil ->
        {:error, :not_found}
    end
  end

  defp reconcile_active_resumed_attempt(candidate, project_id, attempt_id, opts) do
    now = TimeHelpers.now()

    cond do
      absolute_plan_deadline_reached?(candidate, now) ->
        candidate
        |> expire_stale_attempt_safely(now, opts)
        |> finish_attempt_reconciliation(project_id, attempt_id, opts)

      candidate.status in ["queued", "running", "retrying"] ->
        candidate
        |> reconcile_accepted_attempt()
        |> finish_attempt_reconciliation(project_id, attempt_id, opts)

      DateTime.after?(candidate.expires_at, now) ->
        {:ok, candidate}

      true ->
        candidate
        |> expire_stale_attempt(now)
        |> finish_attempt_reconciliation(project_id, attempt_id, opts)
    end
  end

  defp reconcile_accepted_attempt(%ProjectImportAttempt{} = candidate) do
    Repo.transact(fn ->
      job_state = lock_import_job_state(candidate.oban_job_id)
      attempt = lock_active_import_attempt(candidate.id, candidate.project_id)

      cond do
        is_nil(attempt) ->
          {:ok, :changed}

        attempt.oban_job_id != candidate.oban_job_id ->
          {:ok, :changed}

        job_state in @executable_import_job_states ->
          {:ok, {:current, attempt}}

        job_state in @terminal_import_job_states or job_state == :absent ->
          expire_stale_attempt_record(attempt, TimeHelpers.now())

        true ->
          {:ok, {:current, attempt}}
      end
    end)
  end

  defp lock_active_import_attempt(attempt_id, project_id) do
    active_statuses = ProjectImportAttempt.active_statuses()

    ProjectImportAttempt
    |> where(
      [candidate],
      candidate.id == ^attempt_id and candidate.project_id == ^project_id and
        candidate.status in ^active_statuses
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp finish_attempt_reconciliation({:ok, {:expired, expired}}, _project_id, _attempt_id, opts) do
    cleanup_plan(expired, opts)
    broadcast(expired)
    {:ok, expired}
  end

  defp finish_attempt_reconciliation({:ok, {:current, current}}, _project_id, _attempt_id, _opts), do: {:ok, current}

  defp finish_attempt_reconciliation({:ok, :changed}, project_id, attempt_id, _opts) do
    case Repo.get_by(ProjectImportAttempt, id: attempt_id, project_id: project_id) do
      %ProjectImportAttempt{} = current -> {:ok, current}
      nil -> {:error, :not_found}
    end
  end

  defp finish_attempt_reconciliation({:error, reason}, _project_id, _attempt_id, _opts), do: {:error, reason}

  defp maybe_wake_resumed_import(%ProjectImportAttempt{status: status} = attempt, opts)
       when status in ["queued", "running", "retrying"] do
    if Keyword.get(opts, :wake_queue, false), do: wake_import_queue(attempt, opts), else: :ok
  end

  defp maybe_wake_resumed_import(%ProjectImportAttempt{}, _opts) do
    :ok
  end

  @spec cancel_import(Scope.t(), pos_integer()) ::
          {:ok, ProjectImportAttempt.t()} | {:error, term()}
  def cancel_import(%Scope{} = scope, attempt_id) do
    cancel_import(scope, attempt_id, [])
  end

  @doc false
  def cancel_import(%Scope{} = scope, attempt_id, opts) when is_list(opts) do
    with %ProjectImportAttempt{} = attempt <- Repo.get(ProjectImportAttempt, attempt_id),
         {:ok, _project, _membership} <- Projects.authorize(scope, attempt.project_id, :edit_content),
         :ok <- run_before_cancel_transaction(opts),
         {:ok, expired} <- cancel_ready_attempt(attempt.id, attempt.project_id, scope.user.id) do
      cleanup_plan(expired)
      broadcast(expired)
      {:ok, expired}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cancel_ready_attempt(attempt_id, project_id, user_id) do
    Repo.transact(fn ->
      with {:ok, :authorized} <- authorize_edit_locked(Repo, project_id, user_id),
           %ProjectImportAttempt{} = attempt <- lock_cancel_attempt(attempt_id, project_id) do
        transition_cancelled_attempt(attempt)
      else
        nil -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp lock_cancel_attempt(attempt_id, project_id) do
    ProjectImportAttempt
    |> where(
      [candidate],
      candidate.id == ^attempt_id and candidate.project_id == ^project_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp transition_cancelled_attempt(%ProjectImportAttempt{status: "ready"} = attempt) do
    with {:ok, expired} <-
           attempt
           |> ProjectImportAttempt.expired_changeset(TimeHelpers.now())
           |> Repo.update(),
         :ok <- mark_plan_cleanup_pending(expired.plan_storage_key) do
      {:ok, expired}
    end
  end

  defp transition_cancelled_attempt(%ProjectImportAttempt{}), do: {:error, :import_not_cancellable}

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
      Enum.reduce(attempts, {0, 0}, fn attempt, {expired_count, failure_count} ->
        case expire_stale_attempt_safely(attempt, now, opts) do
          {:ok, {:expired, expired}} ->
            broadcast(expired)

            cleanup_failure_count =
              expired
              |> cleanup_plan(opts)
              |> cleanup_failure_count()

            {expired_count + 1, failure_count + cleanup_failure_count}

          {:ok, {:executable, executable, "available"}} ->
            wake_import_queue(executable, opts)
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
      end)

    maybe_wake_stale_available_import(now, opts)
    cleanup_failure_count = retry_pending_plan_cleanup(opts)
    failure_count = failure_count + cleanup_failure_count

    {:ok,
     %{
       expired_count: expired_count,
       failure_count: failure_count,
       more?: expiration_work_remaining?(TimeHelpers.now())
     }}
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
    Repo.exists?(stale_expiration_candidates_query(now)) or plan_cleanup_work_remaining?(now)
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

    if attempt, do: wake_import_queue(attempt, opts), else: :ok
  end

  defp expire_stale_attempt_safely(attempt, now, opts) do
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
    if absolute_plan_deadline_reached?(attempt, now) do
      job_cancel = Keyword.get(opts, :job_cancel, &Oban.cancel_job/1)
      safely_cancel_import_job(job_cancel, job_id)
    else
      :ok
    end
  end

  defp cancel_import_job_after_absolute_deadline(%ProjectImportAttempt{}, _now, _opts), do: :ok

  defp safely_cancel_import_job(job_cancel, job_id) when is_function(job_cancel, 1) do
    case job_cancel.(job_id) do
      :ok -> :ok
      _unexpected -> {:error, :import_job_cancellation_failed}
    end
  rescue
    _exception -> {:error, :import_job_cancellation_failed}
  catch
    _kind, _reason -> {:error, :import_job_cancellation_failed}
  end

  defp safely_cancel_import_job(_invalid_job_cancel, _job_id), do: {:error, :import_job_cancellation_failed}

  # Oban's pruner can delete a job and then nilify `oban_job_id` through the
  # foreign key. Lock the job before the attempt to match that order and avoid
  # a job->attempt / attempt->job deadlock. The attempt and job id are rechecked
  # under lock; a concurrent replacement is conservatively left for the next
  # sweep.
  defp expire_stale_attempt(%ProjectImportAttempt{} = candidate, now) do
    Repo.transact(fn ->
      job_state = lock_import_job_state(candidate.oban_job_id)

      candidate.id
      |> lock_stale_attempt(now)
      |> classify_stale_attempt(
        candidate.oban_job_id,
        job_state,
        now,
        absolute_plan_deadline_reached?(candidate, now)
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

  defp classify_stale_attempt(nil, _candidate_job_id, _job_state, _now, _absolute_deadline?), do: {:ok, :not_stale}

  defp classify_stale_attempt(
         %ProjectImportAttempt{status: "ready", oban_job_id: nil} = attempt,
         _candidate_job_id,
         _job_state,
         now,
         _absolute_deadline?
       ) do
    expire_stale_attempt_record(attempt, now)
  end

  defp classify_stale_attempt(
         %ProjectImportAttempt{oban_job_id: job_id},
         candidate_job_id,
         _job_state,
         _now,
         _absolute_deadline?
       )
       when job_id != candidate_job_id do
    {:ok, :not_stale}
  end

  defp classify_stale_attempt(%ProjectImportAttempt{} = attempt, _candidate_job_id, job_state, now, absolute_deadline?) do
    case job_state do
      state when state in @executable_import_job_states and absolute_deadline? ->
        {:error, :import_job_cancellation_incomplete}

      state when state in @executable_import_job_states ->
        {:ok, {:executable, attempt, state}}

      state when state in @terminal_import_job_states or state == :absent ->
        expire_stale_attempt_record(attempt, now)

      _unknown_state when absolute_deadline? ->
        {:error, :import_job_cancellation_incomplete}

      _unknown_state ->
        # Preserve on an unknown state. Deleting a plan is irreversible, while
        # the next sweep can safely reconsider once Oban reports a known state.
        {:ok, :not_stale}
    end
  end

  defp expire_stale_attempt_record(attempt, now) do
    with {:ok, expired} <- attempt |> ProjectImportAttempt.expired_changeset(now) |> Repo.update(),
         :ok <- mark_plan_cleanup_pending(expired.plan_storage_key) do
      {:ok, {:expired, expired}}
    end
  end

  defp lock_import_job_state(nil), do: :absent

  defp lock_import_job_state(job_id) do
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

  defp report_expiration_error(attempt, reason) do
    {error_code, _message, _permanent?} = Error.classify(reason)

    Error.report(%{
      format: attempt.format,
      parser_version: attempt.parser_version,
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

  defp absolute_plan_deadline_reached?(%ProjectImportAttempt{} = attempt, now) do
    attempt
    |> absolute_plan_deadline()
    |> DateTime.compare(now)
    |> Kernel.in([:lt, :eq])
  end

  defp absolute_plan_deadline(%ProjectImportAttempt{inserted_at: inserted_at}) do
    DateTime.add(inserted_at, @absolute_plan_retention_seconds, :second)
  end

  defp bounded_plan_retention_deadline(%ProjectImportAttempt{} = attempt, now) do
    rolling_deadline = DateTime.add(now, @plan_retention_seconds, :second)
    absolute_deadline = absolute_plan_deadline(attempt)

    if DateTime.after?(rolling_deadline, absolute_deadline),
      do: absolute_deadline,
      else: rolling_deadline
  end

  defp revise_import_review(scope, attempt_id, opts, revision_fun) do
    plan_load = Keyword.get(opts, :plan_load, &PlanStorage.load/1)

    with %ProjectImportAttempt{status: "ready"} = attempt <-
           Repo.get(ProjectImportAttempt, attempt_id),
         {:ok, project, _membership} <-
           Projects.authorize(scope, attempt.project_id, :edit_content),
         false <- ready_plan_deadline_reached?(attempt, TimeHelpers.now()),
         {:ok, plan} <- safely_load_plan(plan_load, attempt.plan_storage_key),
         :ok <- validate_attempt_plan_binding(attempt, plan),
         {:ok, revised_plan} <- safely_revise_plan(revision_fun, plan),
         {:ok, preview} <- preview(project.id, revised_plan),
         {:ok, revised_attempt} <-
           persist_plan_revision(
             scope,
             project,
             attempt,
             revised_plan,
             preview,
             opts
           ) do
      broadcast(revised_attempt)
      {:ok, revised_attempt, preview, revised_plan}
    else
      nil -> {:error, :not_found}
      %ProjectImportAttempt{} -> {:error, :import_not_ready}
      true -> {:error, :import_expired}
      {:error, reason} -> {:error, reason}
    end
  end

  defp safely_revise_plan(revision_fun, plan) when is_function(revision_fun, 1) do
    case revision_fun.(plan) do
      {:ok, %ImportPlan{} = revised_plan} -> {:ok, revised_plan}
      {:error, reason} -> {:error, reason}
      _unexpected -> {:error, :invalid_import_review}
    end
  rescue
    _exception -> {:error, :invalid_import_review}
  catch
    _kind, _reason -> {:error, :invalid_import_review}
  end

  defp persist_plan_revision(scope, project, attempt, plan, preview, opts) do
    storage_key = PlanStorage.storage_key(project.id)
    cleanup_after = min_datetime(attempt.expires_at, absolute_plan_deadline(attempt))

    with {:ok, cleanup_request} <-
           reserve_plan_cleanup(project, plan, storage_key, cleanup_after) do
      persist_reserved_plan_revision(
        cleanup_request,
        scope,
        project,
        attempt,
        plan,
        preview,
        opts
      )
    end
  end

  defp persist_reserved_plan_revision(cleanup_request, scope, project, attempt, plan, preview, opts) do
    plan_store = Keyword.get(opts, :plan_store, &PlanStorage.store_at/2)
    storage_key = cleanup_request.plan_storage_key

    case safely_store_plan(plan_store, storage_key, plan, plan_store_timeout(opts)) do
      {:ok, ^storage_key} ->
        swap_stored_plan_revision(
          cleanup_request,
          scope,
          project,
          attempt,
          preview,
          opts
        )

      {:error, reason} ->
        defer_uncertain_plan_cleanup(cleanup_request)
        {:error, reason}
    end
  end

  defp swap_stored_plan_revision(cleanup_request, scope, project, attempt, preview, opts) do
    result =
      Repo.transact(fn ->
        with {:ok, :authorized} <-
               authorize_edit_locked(Repo, project.id, scope.user.id),
             %ProjectImportAttempt{} = locked <-
               lock_reviewable_attempt(attempt.id, project.id, scope.user.id),
             true <- locked.plan_storage_key == attempt.plan_storage_key,
             false <- ready_plan_deadline_reached?(locked, TimeHelpers.now()),
             {:ok, :retained} <- retain_reserved_plan(Repo, cleanup_request.id),
             :ok <- mark_plan_cleanup_pending(Repo, locked.plan_storage_key),
             {:ok, revised} <-
               locked
               |> ProjectImportAttempt.reviewed_changeset(%{
                 plan_storage_key: cleanup_request.plan_storage_key,
                 plan_cleanup_request_id: cleanup_request.id,
                 counts: stringify_keys(preview.counts)
               })
               |> Repo.update() do
          {:ok, revised}
        else
          nil -> {:error, :not_found}
          false -> {:error, :stale_import_review}
          true -> {:error, :import_expired}
          {:error, reason} -> {:error, reason}
        end
      end)

    case result do
      {:ok, revised_attempt} ->
        cleanup_superseded_plan(attempt.plan_cleanup_request_id, opts)
        {:ok, revised_attempt}

      {:error, reason} ->
        cleanup_reserved_plan(cleanup_request)
        {:error, reason}
    end
  end

  defp lock_reviewable_attempt(attempt_id, project_id, user_id) do
    ProjectImportAttempt
    |> where(
      [candidate],
      candidate.id == ^attempt_id and candidate.project_id == ^project_id and
        candidate.user_id == ^user_id and candidate.status == "ready"
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp cleanup_superseded_plan(cleanup_request_id, opts) do
    case Repo.get(PlanCleanupRequest, cleanup_request_id) do
      %PlanCleanupRequest{} = cleanup_request ->
        cleanup_request(cleanup_request, opts)

      nil ->
        :ok
    end
  end

  defp min_datetime(left, right) do
    if DateTime.after?(left, right), do: right, else: left
  end

  @spec subscribe_project_imports(Project.t()) :: :ok | {:error, term()}
  def subscribe_project_imports(%Project{id: project_id}) do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, project_topic(project_id))
  end

  defp persist_import_plan(scope, project, plan, preview, binary, opts) do
    storage_key = PlanStorage.storage_key(project.id)
    expires_at = DateTime.add(TimeHelpers.now(), @plan_retention_seconds, :second)

    with {:ok, cleanup_request} <-
           reserve_plan_cleanup(project, plan, storage_key, expires_at) do
      import = %{
        scope: scope,
        project: project,
        plan: plan,
        preview: preview,
        storage_key: storage_key,
        expires_at: expires_at,
        binary: binary,
        opts: opts
      }

      persist_reserved_plan(cleanup_request, import)
    end
  end

  defp persist_reserved_plan(cleanup_request, %{storage_key: storage_key, plan: plan, opts: opts} = import) do
    plan_store = Keyword.get(opts, :plan_store, &PlanStorage.store_at/2)

    case safely_store_plan(plan_store, storage_key, plan, plan_store_timeout(opts)) do
      {:ok, ^storage_key} ->
        persist_stored_plan(cleanup_request, import)

      {:error, reason} ->
        defer_uncertain_plan_cleanup(cleanup_request)
        {:error, reason}
    end
  end

  defp persist_stored_plan(cleanup_request, import) do
    %{scope: scope, project: project, plan: plan, preview: preview, expires_at: expires_at, binary: binary} = import

    scope
    |> insert_ready_attempt(project, plan, preview, cleanup_request, expires_at, binary)
    |> handle_stored_plan_result(cleanup_request)
  end

  defp handle_stored_plan_result({:ok, attempt}, _cleanup_request), do: {:ok, attempt}

  defp handle_stored_plan_result({:existing, attempt}, cleanup_request) do
    cleanup_reserved_plan(cleanup_request)
    {:ok, attempt}
  end

  defp handle_stored_plan_result({:error, reason}, cleanup_request) do
    cleanup_reserved_plan(cleanup_request)
    {:error, reason}
  end

  defp safely_store_plan(plan_store, storage_key, plan, timeout) do
    result =
      storage_key
      |> List.wrap()
      |> Task.async_stream(
        fn _key -> invoke_plan_store(plan_store, storage_key, plan) end,
        max_concurrency: 1,
        ordered: true,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.at(0)

    case result do
      {:ok, {:ok, ^storage_key}} -> {:ok, storage_key}
      {:ok, {:error, :import_plan_too_large}} -> {:error, :import_plan_too_large}
      _error -> {:error, :import_plan_storage_failed}
    end
  rescue
    _exception -> {:error, :import_plan_storage_failed}
  catch
    _kind, _reason -> {:error, :import_plan_storage_failed}
  end

  defp invoke_plan_store(plan_store, storage_key, plan) do
    plan_store.(storage_key, plan)
  rescue
    _exception -> {:error, :import_plan_storage_failed}
  catch
    _kind, _reason -> {:error, :import_plan_storage_failed}
  end

  defp plan_store_timeout(opts) do
    case Keyword.get(opts, :plan_store_timeout, @plan_store_timeout) do
      timeout when is_integer(timeout) and timeout > 0 -> min(timeout, @plan_store_timeout)
      _invalid -> @plan_store_timeout
    end
  end

  defp reserve_plan_cleanup(project, plan, storage_key, cleanup_after) do
    attrs = %{
      plan_storage_key: storage_key,
      format: to_string(plan.format),
      parser_version: plan.parser_version,
      state: "reserved",
      cleanup_after: cleanup_after
    }

    %PlanCleanupRequest{project_id: project.id}
    |> PlanCleanupRequest.reservation_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, request} -> {:ok, request}
      {:error, _changeset} -> {:error, :import_cleanup_reservation_failed}
    end
  end

  defp insert_ready_attempt(scope, project, plan, preview, cleanup_request, expires_at, binary) do
    attrs = %{
      status: "ready",
      stage: "parsed",
      format: to_string(plan.format),
      source_kind: to_string(plan.source_kind),
      parser_version: plan.parser_version,
      idempotency_key: idempotency_key(scope, project, plan, binary),
      plan_storage_key: cleanup_request.plan_storage_key,
      counts: stringify_keys(preview.counts),
      warning_codes: Enum.map(ImportPlan.warning_codes(plan), &to_string/1),
      expires_at: expires_at
    }

    attempt_changeset =
      ProjectImportAttempt.ready_changeset(
        %ProjectImportAttempt{
          project_id: project.id,
          user_id: scope.user.id,
          plan_cleanup_request_id: cleanup_request.id
        },
        attrs
      )

    Multi.new()
    |> Multi.run(:authorization, fn repo, _changes ->
      authorize_edit_locked(repo, project.id, scope.user.id)
    end)
    |> Multi.insert(:attempt, attempt_changeset)
    |> Multi.run(:retain_plan, fn repo, _changes ->
      retain_reserved_plan(repo, cleanup_request.id)
    end)
    |> Repo.transaction()
    |> normalize_ready_attempt_result(attrs.idempotency_key)
  end

  defp retain_reserved_plan(repo, cleanup_request_id) do
    case repo.update_all(
           from(request in PlanCleanupRequest,
             where: request.id == ^cleanup_request_id and request.state == "reserved"
           ),
           set: [state: "retained", cleanup_after: nil, updated_at: TimeHelpers.now()]
         ) do
      {1, _rows} -> {:ok, :retained}
      {_count, _rows} -> {:error, :import_cleanup_reservation_lost}
    end
  end

  defp normalize_ready_attempt_result({:ok, %{attempt: attempt}}, _idempotency_key), do: {:ok, attempt}

  defp normalize_ready_attempt_result({:error, :attempt, %Ecto.Changeset{} = changeset, _changes}, idempotency_key) do
    resolve_ready_attempt_conflict(changeset, idempotency_key)
  end

  defp normalize_ready_attempt_result({:error, :authorization, reason, _changes}, _idempotency_key) do
    {:error, reason}
  end

  defp normalize_ready_attempt_result({:error, _operation, _reason, _changes}, _idempotency_key) do
    {:error, :import_attempt_persistence_failed}
  end

  defp resolve_ready_attempt_conflict(changeset, idempotency_key) do
    if Keyword.has_key?(changeset.errors, :idempotency_key) do
      idempotency_key
      |> existing_ready_attempt()
      |> normalize_existing_ready_attempt()
    else
      {:error, :import_attempt_persistence_failed}
    end
  end

  defp normalize_existing_ready_attempt({:ok, attempt}), do: {:existing, attempt}
  defp normalize_existing_ready_attempt(error), do: error

  defp authorize_edit_locked(repo, project_id, user_id) do
    with %Project{} <-
           Project
           |> where([project], project.id == ^project_id and is_nil(project.deleted_at))
           |> lock("FOR SHARE")
           |> repo.one(),
         %ProjectMembership{} = membership <-
           ProjectMembership
           |> where(
             [candidate],
             candidate.project_id == ^project_id and candidate.user_id == ^user_id
           )
           |> lock("FOR SHARE")
           |> repo.one(),
         true <- ProjectMembership.can?(membership.role, :edit_content) do
      {:ok, :authorized}
    else
      nil -> {:error, :unauthorized}
      false -> {:error, :unauthorized}
    end
  end

  defp existing_ready_attempt(idempotency_key) do
    case Repo.one(
           from attempt in ProjectImportAttempt,
             where:
               attempt.idempotency_key == ^idempotency_key and
                 attempt.status in ^ProjectImportAttempt.active_statuses(),
             order_by: [desc: attempt.id],
             limit: 1
         ) do
      nil -> {:error, :import_attempt_persistence_failed}
      attempt -> {:ok, attempt}
    end
  end

  defp enqueue_locked_attempt(attempt_id, project_id, user_id, strategy, opts) do
    with {:ok, :authorized} <- authorize_edit_locked(Repo, project_id, user_id),
         %ProjectImportAttempt{} = attempt <-
           ProjectImportAttempt
           |> where(
             [candidate],
             candidate.id == ^attempt_id and candidate.project_id == ^project_id
           )
           |> lock("FOR UPDATE")
           |> Repo.one() do
      enqueue_locked_attempt_by_status(attempt, strategy, opts)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp enqueue_locked_attempt_by_status(%ProjectImportAttempt{status: "ready"} = attempt, strategy, opts) do
    if ready_plan_deadline_reached?(attempt, TimeHelpers.now()),
      do: reject_invalid_review_attempt(attempt, :import_expired),
      else: enqueue_ready_attempt(attempt, strategy, opts)
  end

  defp enqueue_locked_attempt_by_status(%ProjectImportAttempt{status: status} = attempt, _strategy, _opts)
       when status in ["queued", "running", "retrying"] do
    {:ok, {:queued, attempt}}
  end

  defp enqueue_locked_attempt_by_status(%ProjectImportAttempt{}, _strategy, _opts), do: {:error, :import_not_ready}

  defp enqueue_ready_attempt(attempt, strategy, opts) do
    plan_load = Keyword.get(opts, :plan_load, &PlanStorage.load/1)

    with {:ok, plan} <- safely_load_plan(plan_load, attempt.plan_storage_key),
         :ok <- validate_attempt_plan_binding(attempt, plan),
         true <- ReviewDecisions.resolved?(plan),
         :ok <-
           ReviewDecisions.confirm(
             plan,
             Keyword.get(opts, :review_confirmation_fingerprint)
           ) do
      queue_resolved_import(attempt, plan, strategy)
    else
      false ->
        reject_invalid_review_attempt(attempt, :invalid_import_review)

      {:error, :invalid_import_review_selection} ->
        {:error, :invalid_import_review_selection}

      {:error, reason}
      when reason in [
             :invalid_import_review,
             :import_review_too_large
           ] ->
        reject_invalid_review_attempt(attempt, reason)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp queue_resolved_import(attempt, plan, strategy) do
    with {:ok, preview} <- preview(attempt.project_id, plan),
         {:ok, job} <-
           %{"attempt_id" => attempt.id}
           |> ImportProjectWorker.new()
           |> Oban.insert(),
         {:ok, queued} <-
           attempt
           |> ProjectImportAttempt.queued_changeset(
             strategy,
             job.id,
             bounded_plan_retention_deadline(attempt, TimeHelpers.now())
           )
           |> Ecto.Changeset.put_change(:counts, stringify_keys(preview.counts))
           |> Repo.update() do
      {:ok, {:queued, queued}}
    end
  end

  defp reject_invalid_review_attempt(attempt, reason) do
    with {:ok, expired} <-
           attempt
           |> ProjectImportAttempt.expired_changeset(TimeHelpers.now())
           |> Repo.update(),
         :ok <- mark_plan_cleanup_pending(expired.plan_storage_key) do
      {:ok, {:rejected, expired, reason}}
    end
  end

  defp safely_load_plan(plan_load, storage_key) when is_function(plan_load, 1) do
    case plan_load.(storage_key) do
      {:ok, %ImportPlan{} = plan} -> {:ok, plan}
      _failure -> {:error, :import_plan_unavailable}
    end
  rescue
    _exception -> {:error, :import_plan_unavailable}
  catch
    _kind, _reason -> {:error, :import_plan_unavailable}
  end

  defp safely_load_plan(_invalid_plan_load, _storage_key), do: {:error, :import_plan_unavailable}

  defp validate_attempt_plan_binding(attempt, plan) do
    if attempt.format == to_string(plan.format) and
         attempt.parser_version == plan.parser_version and
         attempt.source_kind == to_string(plan.source_kind) do
      :ok
    else
      {:error, :invalid_import_review}
    end
  end

  defp ready_plan_deadline_reached?(%ProjectImportAttempt{} = attempt, now) do
    not DateTime.after?(attempt.expires_at, now) or
      absolute_plan_deadline_reached?(attempt, now)
  end

  # `Oban.insert/1` above runs inside the attempt transaction. The PG notifier
  # has no transactional delivery guarantee, so its insert signal can arrive
  # before the job is visible on another connection. Always send a second,
  # best-effort signal after the outer commit. The job remains durable even if
  # this signal fails; Oban's stager is the eventual fallback.
  defp wake_import_queue(attempt, opts) do
    notifier =
      Keyword.get(opts, :queue_notifier, fn payload ->
        Oban.Notifier.notify(Oban, :insert, payload)
      end)

    case safely_notify_import_queue(notifier) do
      :ok ->
        :ok

      :error ->
        Error.report(%{
          format: attempt.format,
          parser_version: attempt.parser_version,
          phase: "queue_wakeup",
          error_code: "queue_wakeup_failed",
          exception_module: "none"
        })
    end
  end

  defp safely_notify_import_queue(notifier) when is_function(notifier, 1) do
    case notifier.(%{queue: "imports"}) do
      :ok -> :ok
      _failure -> :error
    end
  rescue
    _exception -> :error
  catch
    _kind, _reason -> :error
  end

  defp safely_notify_import_queue(_invalid_notifier), do: :error

  defp run_import(attempt, opts) do
    started_at = System.monotonic_time()
    attempt_number = Keyword.get(opts, :attempt, 1)
    max_attempts = Keyword.get(opts, :max_attempts, 1)

    result =
      try do
        with {:ok, project, _membership} <- authorize_worker(attempt),
             {:ok, plan} <- PlanStorage.load(attempt.plan_storage_key),
             :ok <- validate_attempt_plan_binding(attempt, plan),
             true <- ReviewDecisions.resolved?(plan),
             :ok <- run_before_materialization_transaction(opts),
             {:ok, outcome} <- materialize_once(attempt, project, plan, opts) do
          {:materialized, outcome}
        else
          false ->
            handled_execution_error(attempt, :invalid_import_review, attempt_number, max_attempts, started_at, opts)

          {:error, reason} ->
            handled_execution_error(attempt, reason, attempt_number, max_attempts, started_at, opts)
        end
      rescue
        exception ->
          report_exception(:execute, attempt_metadata(attempt, "failed", "exception"), exception, started_at)

          handled_execution_error(
            attempt,
            :unexpected_import_error,
            attempt_number,
            max_attempts,
            started_at,
            opts
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
      {:handled, handled_result} -> handled_result
    end
  end

  defp authorize_worker(attempt) do
    Projects.authorize(Scope.for_user(attempt.user), attempt.project_id, :edit_content)
  end

  defp handled_execution_error(attempt, reason, attempt_number, max_attempts, started_at, opts) do
    {:handled, handle_execution_error(attempt, reason, attempt_number, max_attempts, started_at, opts)}
  end

  # Keep the lock order aligned with project deletion: project, membership,
  # then attempt. A permanent project delete takes the project row first and
  # reaches attempts through the foreign-key cascade, so taking the attempt
  # first here would allow the two transactions to deadlock.
  #
  # The attempt row remains locked for the rest of the materialization
  # transaction. Imported entities and the completed status therefore commit
  # together, and a concurrent delivery observes the completed state.
  defp materialize_once(attempt, project, plan, opts) do
    Repo.transact(
      fn ->
        with {:ok, authorized_project} <- authorize_worker_locked(attempt, attempt.user),
             true <- authorized_project.id == project.id,
             %ProjectImportAttempt{} = locked_attempt <-
               lock_import_attempt(attempt.id, authorized_project.id, attempt.user.id) do
          materialize_locked_attempt(locked_attempt, authorized_project, plan, opts)
        else
          nil -> {:error, :not_found}
          false -> {:error, :unauthorized}
          {:error, reason} -> {:error, reason}
        end
      end,
      timeout: @materialization_timeout
    )
  end

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

  defp materialize_locked_attempt(%{status: "completed"} = attempt, _project, _plan, _opts) do
    {:ok, {:already_completed, attempt}}
  end

  defp materialize_locked_attempt(%{status: status} = attempt, _project, _plan, _opts)
       when status in ["failed", "expired"] do
    {:ok, {:terminal, attempt}}
  end

  defp materialize_locked_attempt(%{status: status} = attempt, project, plan, opts)
       when status in ["queued", "running", "retrying"] do
    if absolute_plan_deadline_reached?(attempt, TimeHelpers.now()) do
      expire_locked_import_attempt(attempt)
    else
      with {:ok, running} <- mark_running(attempt),
           {:ok, result} <-
             Materializer.materialize_locked_project_in_transaction(project, plan,
               conflict_strategy: strategy_atom(running.conflict_strategy)
             ),
           :ok <- run_before_attempt_completion(opts),
           {:ok, completed} <- complete_attempt(running, result.counts),
           :ok <- mark_plan_cleanup_pending(completed.plan_storage_key) do
        {:ok, {:materialized, completed}}
      end
    end
  end

  defp materialize_locked_attempt(_attempt, _project, _plan, _opts), do: {:error, :import_not_queued}

  defp expire_locked_import_attempt(attempt) do
    with {:ok, expired} <-
           attempt
           |> ProjectImportAttempt.expired_changeset(TimeHelpers.now())
           |> Repo.update(),
         :ok <- mark_plan_cleanup_pending(expired.plan_storage_key) do
      {:ok, {:terminal, expired}}
    end
  end

  # Lock the project exclusively before the membership and attempt. Besides
  # preventing deletion, this serializes all imports into the same project and
  # avoids upgrading the project lock after the attempt row is held.
  defp authorize_worker_locked(attempt, user) do
    with %Project{} = project <-
           Project
           |> where([candidate], candidate.id == ^attempt.project_id and is_nil(candidate.deleted_at))
           |> lock("FOR UPDATE")
           |> Repo.one(),
         %ProjectMembership{} = locked_membership <-
           ProjectMembership
           |> where(
             [candidate],
             candidate.project_id == ^attempt.project_id and candidate.user_id == ^user.id
           )
           |> lock("FOR SHARE")
           |> Repo.one(),
         true <- ProjectMembership.can?(locked_membership.role, :edit_content) do
      {:ok, project}
    else
      nil -> {:error, :unauthorized}
      false -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp finish_import({:materialized, completed}, started_at, opts) do
    cleanup_plan(completed, opts)
    emit_stop(:execute, started_at, attempt_metadata(completed, "completed", "none"))
    replay_completed_side_effects(completed)
    {:ok, completed}
  end

  defp finish_import({:already_completed, completed}, _started_at, opts) do
    cleanup_plan_if_pending(completed, opts)
    replay_completed_side_effects(completed)
    {:ok, completed}
  end

  defp finish_import({:terminal, attempt}, _started_at, opts) do
    cleanup_plan_if_pending(attempt, opts)
    {:ok, attempt}
  end

  defp replay_completed_side_effects(completed) do
    Collaboration.broadcast_dashboard_change(completed.project_id, :all)
    broadcast(completed)
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

  defp run_before_cancel_transaction(opts) do
    case Keyword.get(opts, :before_cancel_transaction) do
      nil ->
        :ok

      callback when is_function(callback, 0) ->
        callback.()
        :ok
    end
  end

  defp complete_attempt(attempt, counts) do
    attempt
    |> ProjectImportAttempt.completed_changeset(TimeHelpers.now(), stringify_keys(counts))
    |> Repo.update()
  end

  defp handle_execution_error(attempt, reason, attempt_number, max_attempts, started_at, opts) do
    {code, message, permanent?} = Error.classify(reason)
    terminal? = permanent? or attempt_number >= max_attempts

    case persist_execution_error(attempt.id, code, message, attempt_number, max_attempts, terminal?) do
      {:ok, {:terminal, terminal_attempt}} ->
        cleanup_plan_if_pending(terminal_attempt, opts)
        replay_completed_recovery(terminal_attempt)
        {:ok, terminal_attempt}

      {:ok, {:failed, failed}} ->
        metadata = attempt_metadata(failed, "failed", code)
        Error.report(Map.merge(metadata, %{phase: "execute", error_code: code}))
        cleanup_plan(failed, opts)
        emit_stop(:execute, started_at, metadata)
        broadcast(failed)
        {:ok, failed}

      {:ok, {:retrying, retrying}} ->
        metadata = attempt_metadata(retrying, "retrying", code)
        Error.report(Map.merge(metadata, %{phase: "execute", error_code: code}))
        emit_stop(:execute, started_at, metadata)
        broadcast(retrying)
        {:error, :retryable_import_error}

      {:ok, :attempt_not_found} ->
        cleanup_plan(attempt, opts)

        emit_stop(
          :execute,
          started_at,
          attempt_metadata(attempt, "discarded", "attempt_not_found")
        )

        {:ok, :attempt_not_found}

      {:error, transition_reason} ->
        {:error, transition_reason}
    end
  end

  defp persist_execution_error(attempt_id, code, message, attempt_number, max_attempts, terminal?) do
    Repo.transact(fn ->
      locked_attempt =
        ProjectImportAttempt
        |> where([candidate], candidate.id == ^attempt_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      case locked_attempt do
        nil ->
          {:ok, :attempt_not_found}

        %ProjectImportAttempt{} = attempt ->
          transition_execution_error(attempt, code, message, attempt_number, max_attempts, terminal?)
      end
    end)
  end

  defp transition_execution_error(%{status: status} = attempt, _code, _message, _number, _max, _terminal?)
       when status in ["completed", "failed", "expired"] do
    {:ok, {:terminal, attempt}}
  end

  defp transition_execution_error(%{status: status} = attempt, code, message, number, max, true)
       when status in ["queued", "running", "retrying"] do
    attrs = %{
      status: "failed",
      stage: "failed",
      error_code: code,
      error_message: message,
      error_report: %{attempt: number, max_attempts: max},
      completed_at: TimeHelpers.now()
    }

    with {:ok, failed} <- attempt |> ProjectImportAttempt.failed_changeset(attrs) |> Repo.update(),
         :ok <- mark_plan_cleanup_pending(failed.plan_storage_key) do
      {:ok, {:failed, failed}}
    end
  end

  defp transition_execution_error(%{status: status} = attempt, code, _message, number, max, false)
       when status in ["queued", "running", "retrying"] do
    attrs = %{
      status: "retrying",
      stage: "retrying",
      error_code: code,
      error_message: "The import will be retried automatically.",
      error_report: %{attempt: number, max_attempts: max},
      started_at: attempt.started_at || TimeHelpers.now(),
      expires_at: bounded_plan_retention_deadline(attempt, TimeHelpers.now())
    }

    with {:ok, retrying} <- attempt |> ProjectImportAttempt.retrying_changeset(attrs) |> Repo.update() do
      {:ok, {:retrying, retrying}}
    end
  end

  defp transition_execution_error(_attempt, _code, _message, _number, _max, _terminal?) do
    {:error, :import_not_queued}
  end

  defp replay_completed_recovery(%ProjectImportAttempt{status: "completed"} = completed) do
    replay_completed_side_effects(completed)
  end

  defp replay_completed_recovery(%ProjectImportAttempt{}), do: :ok

  defp mark_plan_cleanup_pending(storage_key), do: mark_plan_cleanup_pending(Repo, storage_key)

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

  defp cleanup_reserved_plan(cleanup_request) do
    with {:ok, pending} <- force_plan_cleanup(cleanup_request.id) do
      cleanup_request(pending, [])
    end

    :ok
  end

  # A failed or timed-out PUT has an ambiguous remote outcome: object storage
  # may still commit it after the caller receives the error. Invalidate any
  # stale delete claim, then wait a full retention window before the scanner's
  # definitive delete instead of falsely declaring the key clean immediately.
  defp defer_uncertain_plan_cleanup(%PlanCleanupRequest{} = request) do
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

  defp cleanup_plan(attempt, opts \\ []) do
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

  defp cleanup_request(%PlanCleanupRequest{} = request, opts) do
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

  defp cleanup_plan_if_pending(%ProjectImportAttempt{} = attempt, opts \\ []) do
    cleanup_plan(attempt, opts)
  end

  defp retry_pending_plan_cleanup(opts) do
    terminal_failure_count = retry_terminal_attempt_cleanup(opts)
    due_failure_count = retry_due_plan_cleanup(opts)
    purge_completed_cleanup_tombstones()
    terminal_failure_count + due_failure_count
  end

  defp plan_cleanup_work_remaining?(now) do
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

  defp cleanup_failure_count(:ok), do: 0
  defp cleanup_failure_count({:error, _reason}), do: 1
  defp cleanup_failure_count(_unexpected), do: 1

  defp purge_completed_cleanup_tombstones do
    cutoff = DateTime.add(TimeHelpers.now(), -@cleanup_tombstone_retention_seconds, :second)

    Repo.delete_all(
      from(request in PlanCleanupRequest,
        where: request.state == "completed" and request.completed_at <= ^cutoff
      )
    )

    :ok
  end

  defp normalize_strategy(strategy) when is_atom(strategy), do: normalize_strategy(to_string(strategy))

  defp normalize_strategy(strategy) when strategy in ~w(skip overwrite rename), do: {:ok, strategy}
  defp normalize_strategy(_strategy), do: {:error, :invalid_conflict_strategy}

  defp strategy_atom("skip"), do: :skip
  defp strategy_atom("overwrite"), do: :overwrite
  defp strategy_atom("rename"), do: :rename

  defp get_attempt(attempt_id) do
    case Repo.get(ProjectImportAttempt, attempt_id) do
      nil -> nil
      %ProjectImportAttempt{} = attempt -> Repo.preload(attempt, [:user, :project])
    end
  end

  defp idempotency_key(scope, project, plan, binary) do
    source_digest = :crypto.hash(:sha256, binary)
    secret = Application.fetch_env!(:storyarn, :import_idempotency_secret)
    payload = :erlang.term_to_binary({scope.user.id, project.id, plan.format, plan.parser_version, source_digest})

    :hmac
    |> :crypto.mac(:sha256, secret, payload)
    |> Base.encode16(case: :lower)
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp source_metadata(filename) do
    extension = filename |> Path.extname() |> String.downcase()

    %{
      format: if(extension in [".yarn", ".zip"], do: "yarn", else: "unknown"),
      source_kind: if(extension == ".zip", do: "archive", else: "file"),
      parser_version: "unknown"
    }
  end

  defp plan_metadata(plan, status, error_code) do
    %{
      format: to_string(plan.format),
      source_kind: to_string(plan.source_kind),
      parser_version: plan.parser_version,
      status: status,
      error_code: error_code
    }
  end

  defp attempt_metadata(attempt, status, error_code) do
    %{
      format: attempt.format,
      source_kind: attempt.source_kind,
      parser_version: attempt.parser_version,
      status: status,
      error_code: error_code
    }
  end

  defp report_prepare_error(reason, metadata, started_at) do
    {code, _message, _permanent?} = Error.classify(reason)
    Error.report(Map.merge(metadata, %{phase: "prepare", error_code: code, exception_module: "none"}))
    emit_stop(:prepare, started_at, Map.merge(metadata, %{status: "failed", error_code: code}))
  end

  defp report_exception(phase, metadata, exception, started_at) do
    error_metadata = %{
      format: Map.get(metadata, :format, "unknown"),
      parser_version: Map.get(metadata, :parser_version, "unknown"),
      phase: to_string(phase),
      error_code: "exception",
      exception_module: inspect(exception.__struct__)
    }

    Error.report(error_metadata)
    emit_stop(phase, started_at, Map.merge(metadata, %{status: "failed", error_code: "exception"}))
  end

  defp emit_stop(phase, started_at, metadata) do
    :telemetry.execute(
      [:storyarn, :import, phase, :stop],
      %{count: 1, duration: System.monotonic_time() - started_at},
      metadata
    )
  end

  defp broadcast(attempt) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      project_topic(attempt.project_id),
      {:project_import_updated, attempt}
    )
  end

  defp project_topic(project_id), do: "project_imports:project:#{project_id}"
end
