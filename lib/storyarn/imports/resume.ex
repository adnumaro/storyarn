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
  alias Storyarn.Imports.PlanCleanup
  alias Storyarn.Imports.PlanStorage
  alias Storyarn.Imports.Preview
  alias Storyarn.Imports.ProjectImportAttempt
  alias Storyarn.Imports.Queue
  alias Storyarn.Imports.Shared
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @max_safe_import_attempt_id 9_007_199_254_740_991
  @executable_import_job_states ~w(available scheduled retryable executing)
  @terminal_import_job_states ~w(cancelled completed discarded)
  @import_action :manage_project

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
    case Projects.authorize(scope, project.id, @import_action) do
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
      preview_result = resume_preview(project.id, attempt, opts)

      with {:ok, _project, _membership} <- Projects.authorize(scope, project.id, @import_action),
           {:ok, current_attempt} <- reconcile_resumed_attempt(project.id, attempt_id, user_id, opts) do
        finish_resumed_import(attempt, current_attempt, preview_result, opts)
      else
        _not_authorized_or_missing -> {:error, :not_found}
      end
    end
  end

  defp resume_preview(project_id, %ProjectImportAttempt{status: "ready"} = attempt, opts) do
    plan_load = Keyword.get(opts, :plan_load, &PlanStorage.load/1)

    result =
      with {:ok, plan} <- Shared.safely_load_plan(plan_load, attempt.plan_storage_key) do
        safely_build_resumed_preview(project_id, plan)
      end

    report_resume_failure(attempt, result)
    result
  end

  defp resume_preview(_project_id, %ProjectImportAttempt{}, _opts), do: {:ok, nil}

  defp safely_build_resumed_preview(project_id, %ImportPlan{} = plan) do
    case Preview.preview(project_id, plan) do
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
    PlanCleanup.cleanup_plan_if_pending(current_attempt, opts)
    Execution.replay_completed_side_effects(current_attempt)
    {:ok, current_attempt, nil}
  end

  defp finish_resumed_import(_initial_attempt, current_attempt, _preview_result, opts) do
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
    Repo.transact(fn ->
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
          Expiration.expire_stale_attempt_record(attempt, TimeHelpers.now())

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

  defp finish_attempt_reconciliation({:ok, {:expired, expired}}, _project_id, _attempt_id, _user_id, opts) do
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
