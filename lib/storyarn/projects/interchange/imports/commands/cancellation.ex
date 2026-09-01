defmodule Storyarn.Projects.Imports.Cancellation do
  @moduledoc """
  Cancels a prepared import before it begins writing project content.

  Cancellation reauthorizes under the canonical Project lock order and locks
  an accepted Oban job before the import attempt. Cleanup and broadcasts run
  only after the durable cancellation transaction commits.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Imports.Expiration
  alias Storyarn.Projects.Imports.PlanCleanup
  alias Storyarn.Projects.Imports.ProjectImportAttempt
  alias Storyarn.Projects.Imports.Queue
  alias Storyarn.Projects.Imports.Replacement
  alias Storyarn.Projects.Memberships
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  @import_action :manage_project

  @doc """
  Cancels an import that has not begun writing.

  `ready` and `queued` attempts are cancellable; both reach `expired` and
  release their plan. `running` and `retrying` are not — they return
  `{:error, :import_not_cancellable}`, because that import is materializing and
  the caller must not be able to make it disappear from the UI while it writes.
  """
  @spec cancel_import(Scope.t(), pos_integer()) ::
          {:ok, ProjectImportAttempt.t()} | {:error, term()}
  def cancel_import(%{user: _} = scope, attempt_id) do
    cancel_import(scope, attempt_id, [])
  end

  @doc false
  def cancel_import(%{user: _} = scope, attempt_id, opts) when is_list(opts) do
    with %ProjectImportAttempt{} = attempt <- Repo.get(ProjectImportAttempt, attempt_id),
         {:ok, _project, _membership} <-
           Memberships.authorize(scope, attempt.project_id, @import_action),
         :ok <- authorize_attempt_owner(attempt, scope.user.id),
         :ok <- run_before_cancel_transaction(opts),
         {:ok, expired} <- cancel_attempt(attempt, scope.user.id, opts) do
      Replacement.cleanup_terminal_recovery_snapshot(expired)
      expired = Repo.get(ProjectImportAttempt, expired.id) || expired
      PlanCleanup.cleanup_plan(expired)
      Queue.broadcast(expired)
      {:ok, expired}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # Active attempts are operable only by the member who started them; terminal
  # attempts are ownerless Project records. The refusal is indistinguishable
  # from a missing attempt so an id probe learns nothing.
  defp authorize_attempt_owner(%ProjectImportAttempt{} = attempt, user_id) do
    if ProjectImportAttempt.owned_or_ownerless?(attempt, user_id),
      do: :ok,
      else: {:error, :not_found}
  end

  # Lock order is project, membership, job, attempt — the one global order
  # every import transaction follows: the worker takes project, membership,
  # attempt; resume and the expiry sweep take job, attempt. `Oban.cancel_job/1`
  # dispatches onto this connection inside this transaction, so the job row is
  # taken exclusively *before* the attempt: taking the attempt first inverted
  # the documented order (`Expiration`) and could deadlock against a concurrent
  # resume or sweep of the same attempt, crashing the resume side's mount.
  defp cancel_attempt(%ProjectImportAttempt{} = candidate, user_id, opts) do
    Repo.transact(fn ->
      with {:ok, :authorized} <-
             authorize_import_locked(Repo, candidate.project_id, user_id) do
        cancel_locked_attempt(candidate, opts)
      end
    end)
  end

  defp cancel_locked_attempt(candidate, opts) do
    Expiration.lock_import_job_state_for_update(candidate.oban_job_id)

    case lock_cancel_attempt(candidate.id, candidate.project_id) do
      %ProjectImportAttempt{} = attempt ->
        transition_cancelled_attempt(attempt, candidate.oban_job_id, opts)

      nil ->
        {:error, :not_found}
    end
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

  # A `ready` attempt has no job behind it. A `queued` one has a job that has
  # not started, so cancelling it destroys nothing: no content has been written.
  # This runs under the same `FOR UPDATE` row lock that
  # `materialize_locked_attempt/4` takes, so either the cancel lands first and
  # the worker then finds a terminal attempt, or the worker marks the attempt
  # `running` first and this reports it as no longer cancellable. There is no
  # interleaving where content is written into a project the user was told the
  # import had been dropped from.
  #
  # `running` and `retrying` are deliberately not cancellable: that import is
  # materializing, and letting the UI pretend otherwise is worse than showing it.
  #
  # The queued clause also requires the locked attempt to still carry the job id
  # read before the transaction — that is the row locked above. A binding that
  # moved in between (accepted in another tab, job replaced) means the held lock
  # is not this attempt's job, so cancelling would update a row the transaction
  # does not hold; refuse and let reconciliation own that state.
  defp transition_cancelled_attempt(%ProjectImportAttempt{status: "ready"} = attempt, _candidate_job_id, _opts) do
    expire_cancelled_attempt(attempt)
  end

  defp transition_cancelled_attempt(%ProjectImportAttempt{status: "queued", oban_job_id: job_id} = attempt, job_id, opts) do
    with :ok <- cancel_queued_import_job(attempt, opts) do
      expire_cancelled_attempt(attempt)
    end
  end

  defp transition_cancelled_attempt(%ProjectImportAttempt{}, _candidate_job_id, _opts),
    do: {:error, :import_not_cancellable}

  defp cancel_queued_import_job(%ProjectImportAttempt{oban_job_id: job_id}, opts) when is_integer(job_id) do
    job_cancel = Keyword.get(opts, :job_cancel, &Oban.cancel_job/1)
    Expiration.safely_cancel_import_job(job_cancel, job_id)
  end

  # Oban's pruner can have nilified the reference already. Nothing is left to
  # cancel, and the attempt still has to reach a terminal state.
  defp cancel_queued_import_job(%ProjectImportAttempt{}, _opts), do: :ok

  defp expire_cancelled_attempt(attempt) do
    with {:ok, expired} <-
           attempt
           |> ProjectImportAttempt.expired_changeset(
             TimeHelpers.now(),
             "import_cancelled"
           )
           |> Repo.update(),
         :ok <- PlanCleanup.mark_plan_cleanup_pending(expired.plan_storage_key) do
      {:ok, expired}
    end
  end

  defp authorize_import_locked(_repo, project_id, user_id) do
    case Memberships.authorize_locked(
           %{user: %{id: user_id}},
           project_id,
           @import_action,
           :share
         ) do
      {:ok, %Project{}, _membership} -> {:ok, :authorized}
      {:error, :not_found} -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
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
end
