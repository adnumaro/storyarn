defmodule Storyarn.Imports.Resume do
  @moduledoc """
  Restoring an import after the page that started it went away.

  PubSub delivery is ephemeral, so the durable attempt row — not a broadcast —
  is what a returning LiveView reads. Authorization is rechecked on the way in
  and again after the preview is rebuilt, because rebuilding it takes long
  enough for access to be revoked in between.

  Resuming is also a reconciliation point: an attempt whose job died or overran
  its retention bound is terminalized here rather than being handed back to the
  page as still running.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Imports.Error
  alias Storyarn.Imports.Execution
  alias Storyarn.Imports.Expiration
  alias Storyarn.Imports.ImportPlan
  alias Storyarn.Imports.NotificationDelivery
  alias Storyarn.Imports.PlanCleanup
  alias Storyarn.Imports.PlanStorage
  alias Storyarn.Imports.Preview
  alias Storyarn.Imports.ProjectImportAttempt
  alias Storyarn.Imports.Queue
  alias Storyarn.Imports.Shared
  alias Storyarn.Notifications
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @max_safe_import_attempt_id 9_007_199_254_740_991
  @executable_import_job_states ~w(available scheduled retryable executing)
  @terminal_import_job_states ~w(cancelled completed discarded)
  @import_action :manage_project
  @max_ready_preview_rebuilds 2

  @doc """
  Recovers the newest active import owned by the current user in a project.

  The durable attempt lookup is scoped by both project and user. Authorization
  is checked before the lookup and is checked again by `resume_import/4` while
  the attempt is reconciled and, for ready attempts, its preview is rebuilt.
  """
  @spec resume_latest_active_import(Scope.t(), Project.t()) ::
          {:ok, ProjectImportAttempt.t(), map() | nil}
          | {:ok, nil}
          | {:error, term()}
          | {:error, term(), ProjectImportAttempt.t()}
  def resume_latest_active_import(%Scope{} = scope, %Project{} = project) do
    resume_latest_active_import(scope, project, [])
  end

  @doc false
  def resume_latest_active_import(%Scope{} = scope, %Project{} = project, opts) when is_list(opts) do
    case Projects.authorize(scope, project.id, @import_action) do
      {:ok, _project, _membership} ->
        case latest_active_import_attempt(project.id, scope.user.id) do
          %ProjectImportAttempt{} = attempt ->
            resume_found_import(scope, project, attempt, opts)

          nil ->
            {:ok, nil}
        end

      _not_authorized ->
        {:error, :not_found}
    end
  end

  # A rebuild failure keeps the attempt in the return so the page can show it
  # as an error with a working Reset, instead of a silently empty uploader
  # that resurrects the same failure on every mount. An attempt that vanished
  # mid-flight is simply nothing to restore.
  defp resume_found_import(scope, project, attempt, opts) do
    case resume_import(scope, project, attempt.id, opts) do
      {:ok, _attempt, _preview} = resumed -> resumed
      {:error, :not_found} -> {:ok, nil}
      {:error, reason} -> {:error, reason, attempt}
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
    case Projects.authorize(scope, project.id, @import_action) do
      {:ok, _project, _membership} ->
        resume_authorized_import(scope, project, attempt_id, opts)

      _not_authorized ->
        {:error, :not_found}
    end
  end

  def resume_import(%Scope{}, %Project{}, _attempt_id, _opts), do: {:error, :not_found}

  defp resume_authorized_import(scope, project, attempt_id, opts) do
    user_id = scope.user.id

    with {:ok, attempt} <- reconcile_resumed_attempt(project.id, attempt_id, user_id, opts) do
      resume_consistent_attempt(
        scope,
        project,
        attempt_id,
        user_id,
        attempt,
        opts,
        @max_ready_preview_rebuilds
      )
    end
  end

  defp resume_consistent_attempt(scope, project, attempt_id, user_id, attempt, opts, rebuilds_left) do
    preview_result = resume_preview(project.id, attempt, opts)

    with {:ok, _project, _membership} <- Projects.authorize(scope, project.id, @import_action),
         {:ok, current_attempt} <- reconcile_resumed_attempt(project.id, attempt_id, user_id, opts) do
      finish_resumed_import(
        {scope, project, attempt_id, user_id},
        attempt,
        current_attempt,
        preview_result,
        opts,
        rebuilds_left
      )
    else
      _not_authorized_or_missing -> {:error, :not_found}
    end
  end

  defp resume_preview(project_id, %ProjectImportAttempt{status: "ready"} = attempt, opts) do
    plan_load = Keyword.get(opts, :plan_load, &PlanStorage.load/1)

    result =
      with {:ok, plan} <- Shared.safely_load_plan(plan_load, attempt.plan_storage_key),
           # The same binding check enqueue and the worker enforce: a valid
           # plan that is not THIS attempt's plan must never be shown as its
           # resumed preview — the user would review the wrong data and only
           # find out when enqueue rejects it.
           :ok <- Shared.validate_attempt_plan_binding(attempt, plan) do
        safely_build_resumed_preview(project_id, plan)
      end

    result
  end

  defp resume_preview(_project_id, %ProjectImportAttempt{}, _opts), do: {:ok, nil}

  defp safely_build_resumed_preview(project_id, %ImportPlan{} = plan) do
    case Preview.preview(project_id, plan) do
      {:ok, preview} when is_map(preview) -> {:ok, preview}
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
         _resume_context,
         %ProjectImportAttempt{status: "ready", plan_storage_key: storage_key},
         %ProjectImportAttempt{status: "ready", plan_storage_key: storage_key} = current_attempt,
         {:ok, preview},
         _opts,
         _rebuilds_left
       ) do
    {:ok, current_attempt, preview}
  end

  defp finish_resumed_import(
         _resume_context,
         %ProjectImportAttempt{status: "ready", plan_storage_key: storage_key},
         %ProjectImportAttempt{status: "ready", plan_storage_key: storage_key} = current_attempt,
         {:error, reason},
         _opts,
         _rebuilds_left
       ) do
    report_resume_failure(current_attempt, {:error, reason})
    {:error, reason}
  end

  defp finish_resumed_import(
         {scope, project, attempt_id, user_id},
         _initial_attempt,
         %ProjectImportAttempt{status: "ready"} = current_attempt,
         _preview_result,
         opts,
         rebuilds_left
       )
       when rebuilds_left > 0 do
    # Review saves replace the encrypted plan with a newly bound revision. If
    # that happens while this process is rebuilding the preview, the preview
    # just built belongs to the old key. Rebuild from the durable current key
    # and re-check authorization/state again before returning it.
    resume_consistent_attempt(
      scope,
      project,
      attempt_id,
      user_id,
      current_attempt,
      opts,
      rebuilds_left - 1
    )
  end

  defp finish_resumed_import(
         _resume_context,
         _initial_attempt,
         %ProjectImportAttempt{status: "ready"},
         _preview_result,
         _opts,
         0
       ) do
    # A tab that keeps replacing the review revision cannot make us return a
    # ready attempt without its matching preview. The client treats this as a
    # transient reconciliation failure and can retry from the latest key.
    {:error, :import_state_changed}
  end

  defp finish_resumed_import(
         _resume_context,
         _initial_attempt,
         %ProjectImportAttempt{status: "completed"} = current_attempt,
         _preview_result,
         opts,
         _rebuilds_left
       ) do
    PlanCleanup.cleanup_plan_if_pending(current_attempt, opts)
    Execution.replay_completed_side_effects(current_attempt)
    {:ok, current_attempt, nil}
  end

  defp finish_resumed_import(_resume_context, _initial_attempt, current_attempt, _preview_result, opts, _rebuilds_left) do
    maybe_wake_resumed_import(current_attempt, opts)
    {:ok, current_attempt, nil}
  end

  defp reconcile_resumed_attempt(project_id, attempt_id, user_id, opts) do
    case Repo.get_by(ProjectImportAttempt, id: attempt_id, project_id: project_id) do
      %ProjectImportAttempt{} = candidate ->
        cond do
          not ProjectImportAttempt.owned_or_ownerless?(candidate, user_id) ->
            {:error, :not_found}

          candidate.status in ["ready", "queued", "running", "retrying"] ->
            reconcile_active_resumed_attempt(candidate, project_id, attempt_id, user_id, opts)

          true ->
            {:ok, candidate}
        end

      nil ->
        {:error, :not_found}
    end
  end

  defp reconcile_active_resumed_attempt(candidate, project_id, attempt_id, user_id, opts) do
    now = TimeHelpers.now()

    cond do
      PlanCleanup.absolute_plan_deadline_reached?(candidate, now) ->
        candidate
        |> Expiration.expire_stale_attempt_safely(now, opts)
        |> finish_attempt_reconciliation(project_id, attempt_id, user_id, opts)

      candidate.status in ["queued", "running", "retrying"] ->
        candidate
        |> reconcile_accepted_attempt()
        |> finish_attempt_reconciliation(project_id, attempt_id, user_id, opts)

      DateTime.after?(candidate.expires_at, now) ->
        {:ok, candidate}

      true ->
        candidate
        |> Expiration.expire_stale_attempt(now)
        |> finish_attempt_reconciliation(project_id, attempt_id, user_id, opts)
    end
  end

  defp reconcile_accepted_attempt(%ProjectImportAttempt{} = candidate) do
    case Expiration.import_job_state(candidate.oban_job_id) do
      state when state in @executable_import_job_states ->
        # The worker commits `running` before taking the long materialization
        # locks. Returning that snapshot is deliberately non-blocking: the next
        # PubSub update or reconciliation will observe a concurrent completion.
        {:ok, {:current, candidate}}

      _terminal_or_unknown ->
        reconcile_non_executable_attempt(candidate)
    end
  end

  defp reconcile_non_executable_attempt(candidate) do
    Repo.transact(fn ->
      notification_context = NotificationDelivery.lock_context(candidate)
      job_state = Expiration.lock_import_job_state(candidate.oban_job_id)
      attempt = lock_active_import_attempt(candidate.id, candidate.project_id, candidate.user_id)

      cond do
        is_nil(attempt) ->
          {:ok, :changed}

        attempt.oban_job_id != candidate.oban_job_id ->
          {:ok, :changed}

        job_state in @executable_import_job_states ->
          {:ok, {:current, attempt}}

        job_state in @terminal_import_job_states or job_state == :absent ->
          Expiration.expire_stale_attempt_record(attempt, notification_context, TimeHelpers.now())

        true ->
          {:ok, {:current, attempt}}
      end
    end)
  end

  defp lock_active_import_attempt(attempt_id, project_id, user_id) do
    active_statuses = ProjectImportAttempt.active_statuses()

    ProjectImportAttempt
    |> where(
      [candidate],
      candidate.id == ^attempt_id and candidate.project_id == ^project_id and
        candidate.user_id == ^user_id and candidate.status in ^active_statuses
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp finish_attempt_reconciliation(
         {:ok, {:expired, expired, notification_outcome}},
         _project_id,
         _attempt_id,
         _user_id,
         opts
       ) do
    Notifications.publish_committed(notification_outcome)
    PlanCleanup.cleanup_plan(expired, opts)
    Queue.broadcast(expired)
    {:ok, expired}
  end

  defp finish_attempt_reconciliation({:ok, {:current, current}}, _project_id, _attempt_id, _user_id, _opts),
    do: {:ok, current}

  defp finish_attempt_reconciliation({:ok, :changed}, project_id, attempt_id, user_id, _opts) do
    case Repo.get_by(ProjectImportAttempt, id: attempt_id, project_id: project_id) do
      %ProjectImportAttempt{} = current ->
        if ProjectImportAttempt.owned_or_ownerless?(current, user_id), do: {:ok, current}, else: {:error, :not_found}

      nil ->
        {:error, :not_found}
    end
  end

  defp finish_attempt_reconciliation({:error, reason}, _project_id, _attempt_id, _user_id, _opts), do: {:error, reason}

  defp maybe_wake_resumed_import(%ProjectImportAttempt{status: status} = attempt, opts)
       when status in ["queued", "running", "retrying"] do
    if Keyword.get(opts, :wake_queue, false), do: Queue.wake(attempt, opts), else: :ok
  end

  defp maybe_wake_resumed_import(%ProjectImportAttempt{}, _opts) do
    :ok
  end
end
