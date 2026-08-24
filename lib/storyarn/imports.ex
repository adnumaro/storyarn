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
  alias Storyarn.Imports.Execution
  alias Storyarn.Imports.Expiration
  alias Storyarn.Imports.ImportPlan
  alias Storyarn.Imports.Materializer
  alias Storyarn.Imports.ParserRegistry
  alias Storyarn.Imports.Parsers.Yarn.ReviewDecisions
  alias Storyarn.Imports.PlanCleanup
  alias Storyarn.Imports.PlanCleanupRequest
  alias Storyarn.Imports.PlanStorage
  alias Storyarn.Imports.Preview
  alias Storyarn.Imports.ProjectImportAttempt
  alias Storyarn.Imports.Queue
  alias Storyarn.Imports.Replacement
  alias Storyarn.Imports.Resume
  alias Storyarn.Imports.Shared
  alias Storyarn.Imports.SourceBundle
  alias Storyarn.Imports.Telemetry
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo
  alias Storyarn.Workers.ImportProjectWorker

  @plan_retention_seconds 86_400
  @plan_store_timeout 300_000

  # Importing replaces and rewrites project content wholesale, so it is an
  # owner-level action rather than a content edit. This is the single place that
  # decides it: the web layer restricted imports to owners while the context
  # still accepted any editor, so the rule was only enforced where the UI
  # happened to check it.
  @import_action :manage_project

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

  defdelegate preview(project_id, plan), to: Preview

  @doc """
  Execute an import into a project.

  ## Authorization

  Caller MUST verify the current user has `:manage_project` permission on the
  target project before calling this function. This entry point takes a plan
  that is already authorized and materializes it, so it enforces nothing
  itself. Every other entry point in this module authorizes for itself.

  ## Options

  - `:conflict_strategy` — `:skip` | `:overwrite` | `:rename` (default: `:rename`)

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
          {:ok, ProjectImportAttempt.t(), map() | nil} | {:error, term()}
  def prepare_import(%{user: _} = scope, %Project{} = project, filename, binary) do
    prepare_import(scope, project, filename, binary, [])
  end

  @doc false
  def prepare_import(%{user: _} = scope, %Project{} = project, filename, binary, opts)
      when is_binary(filename) and is_binary(binary) and is_list(opts) do
    started_at = System.monotonic_time()
    initial_metadata = Telemetry.source_metadata(filename)

    try do
      with {:ok, _project, _membership} <- Projects.authorize(scope, project.id, @import_action),
           {:ok, %ImportPlan{} = plan} <- parse_file(filename, binary),
           {:ok, preview} <- preview(project.id, plan),
           {:ok, attempt, persisted_preview} <-
             persist_import_plan(scope, project, plan, preview, binary, opts) do
        Telemetry.emit_stop(:prepare, started_at, Telemetry.plan_metadata(plan, "completed", "none"))
        Queue.broadcast(attempt)
        {:ok, attempt, persisted_preview}
      else
        {:error, reason} ->
          Telemetry.report_prepare_error(reason, initial_metadata, started_at)
          {:error, reason}
      end
    rescue
      exception ->
        Telemetry.report_exception(:prepare, initial_metadata, exception, started_at)
        {:error, :unexpected_import_error}
    catch
      _kind, _reason ->
        Telemetry.report_prepare_error(:unexpected_import_error, initial_metadata, started_at)
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
  def save_import_review(%{user: _} = scope, attempt_id, decisions) do
    save_import_review(scope, attempt_id, decisions, [])
  end

  @doc false
  def save_import_review(%{user: _} = scope, attempt_id, decisions, opts)
      when is_integer(attempt_id) and attempt_id > 0 and is_list(opts) do
    case revise_import_review(scope, attempt_id, opts, fn plan ->
           ReviewDecisions.save_draft(plan, decisions)
         end) do
      {:ok, attempt, preview, _revised_plan} -> {:ok, attempt, preview}
      error -> error
    end
  end

  def save_import_review(%{user: _}, _attempt_id, _decisions, _opts), do: {:error, :not_found}

  @doc """
  Applies every explicit Yarn review decision and returns the exact preview
  that can subsequently be queued.

  No import job is created here. The caller must present the returned
  confirmation fingerprint when enqueueing, which prevents a stale browser
  preview from accepting a different plan revision.
  """
  @spec resolve_import_review(Scope.t(), pos_integer(), boolean(), list()) ::
          {:ok, ProjectImportAttempt.t(), map(), String.t()} | {:error, term()}
  def resolve_import_review(%{user: _} = scope, attempt_id, acknowledged?, decisions) do
    resolve_import_review(scope, attempt_id, acknowledged?, decisions, [])
  end

  @doc false
  def resolve_import_review(%{user: _} = scope, attempt_id, acknowledged?, decisions, opts)
      when is_integer(attempt_id) and attempt_id > 0 and is_boolean(acknowledged?) and is_list(opts) do
    with {:ok, attempt, preview, plan} <-
           revise_import_review(scope, attempt_id, opts, fn plan ->
             ReviewDecisions.apply(plan, acknowledged?, decisions)
           end),
         {:ok, fingerprint} <- ReviewDecisions.confirmation_fingerprint(plan) do
      {:ok, attempt, preview, fingerprint}
    end
  end

  def resolve_import_review(%{user: _}, _attempt_id, _acknowledged?, _decisions, _opts), do: {:error, :not_found}

  @doc """
  Persists the conflict strategy selected for a ready import preview.

  This makes navigation and cross-tab recovery restore the user's selection
  before the import has been accepted by the queue.
  """
  @spec update_import_strategy(Scope.t(), pos_integer(), String.t() | atom()) ::
          {:ok, ProjectImportAttempt.t()} | {:error, term()}
  def update_import_strategy(%{user: _} = scope, attempt_id, strategy) when is_integer(attempt_id) and attempt_id > 0 do
    with {:ok, strategy} <- normalize_strategy(strategy),
         %ProjectImportAttempt{} = attempt <- Repo.get(ProjectImportAttempt, attempt_id),
         {:ok, _project, _membership} <- Projects.authorize(scope, attempt.project_id, @import_action),
         :ok <- authorize_attempt_owner(attempt, scope.user.id),
         {:ok, updated} <- persist_import_strategy(attempt, scope.user.id, strategy) do
      Queue.broadcast(updated)
      {:ok, updated}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def update_import_strategy(%{user: _}, _attempt_id, _strategy), do: {:error, :not_found}

  @doc "Persists the explicit additive or snapshot-backed replacement mode for a ready import."
  @spec update_import_mode(Scope.t(), pos_integer(), String.t() | atom()) ::
          {:ok, ProjectImportAttempt.t()} | {:error, term()}
  def update_import_mode(%{user: _} = scope, attempt_id, mode) when is_integer(attempt_id) and attempt_id > 0 do
    with {:ok, mode} <- normalize_import_mode(mode),
         %ProjectImportAttempt{} = attempt <- Repo.get(ProjectImportAttempt, attempt_id),
         {:ok, _project, _membership} <- Projects.authorize(scope, attempt.project_id, @import_action),
         :ok <- authorize_attempt_owner(attempt, scope.user.id),
         :ok <- ensure_import_mode_available(attempt, mode),
         {:ok, updated} <- persist_import_mode(attempt, scope.user.id, mode) do
      Queue.broadcast(updated)
      {:ok, updated}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def update_import_mode(%{user: _}, _attempt_id, _mode), do: {:error, :not_found}

  @doc """
  Returns the opaque browser-storage key for one user's import in one project.

  The HMAC prevents raw project and user identifiers from being persisted in
  `localStorage`; the key is a namespace only and grants no server access.
  """
  @spec resume_storage_key(Scope.t(), Project.t()) :: String.t()
  def resume_storage_key(%{user: %{id: user_id}}, %Project{id: project_id}) do
    secret = Application.fetch_env!(:storyarn, :import_idempotency_secret)
    payload = :erlang.term_to_binary({:project_import_resume, project_id, user_id})
    digest = :crypto.mac(:hmac, :sha256, secret, payload)

    "storyarn:project-import:" <> Base.url_encode64(digest, padding: false)
  end

  @doc """
  Queues a ready import. The Oban payload contains only `attempt_id`.
  """
  @spec enqueue_import(Scope.t(), pos_integer(), String.t() | atom()) ::
          {:ok, ProjectImportAttempt.t()} | {:error, term()}
  def enqueue_import(%{user: _} = scope, attempt_id, strategy) do
    enqueue_import(scope, attempt_id, strategy, [])
  end

  @doc false
  def enqueue_import(%{user: _} = scope, attempt_id, strategy, opts) when is_list(opts) do
    with {:ok, strategy} <- normalize_strategy(strategy),
         %ProjectImportAttempt{} = attempt <- Repo.get(ProjectImportAttempt, attempt_id),
         {:ok, project, _membership} <- Projects.authorize(scope, attempt.project_id, @import_action),
         :ok <- authorize_attempt_owner(attempt, scope.user.id) do
      fn -> enqueue_locked_attempt(attempt.id, project.id, scope.user.id, strategy, opts) end
      |> Repo.transact()
      |> case do
        {:ok, {:queued, attempt}} ->
          Queue.wake(attempt, opts)
          Queue.broadcast(attempt)
          {:ok, attempt}

        {:ok, {:rejected, attempt, reason}} ->
          PlanCleanup.cleanup_plan(attempt, opts)
          Queue.broadcast(attempt)
          {:error, reason}

        error ->
          error
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get_import_attempt(Scope.t(), pos_integer()) ::
          {:ok, ProjectImportAttempt.t()} | {:error, :not_found | :unauthorized}
  def get_import_attempt(%{user: _} = scope, attempt_id) do
    with %ProjectImportAttempt{} = attempt <- Repo.get(ProjectImportAttempt, attempt_id),
         {:ok, _project, _membership} <- Projects.authorize(scope, attempt.project_id, :view),
         :ok <- authorize_attempt_owner(attempt, scope.user.id) do
      {:ok, attempt}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # See `ProjectImportAttempt.owned_or_ownerless?/2`: active attempts are
  # operable only by the member who started them; terminal attempts are
  # ownerless project records. The refusal is indistinguishable from a missing
  # attempt so an id probe learns nothing.
  defp authorize_attempt_owner(%ProjectImportAttempt{} = attempt, user_id) do
    if ProjectImportAttempt.owned_or_ownerless?(attempt, user_id), do: :ok, else: {:error, :not_found}
  end

  @doc """
  Restores the durable state of an import after navigation or reload.
  """
  defdelegate resume_latest_active_import(scope, project), to: Resume
  defdelegate resume_latest_active_import(scope, project, opts), to: Resume
  defdelegate resume_import(scope, project, attempt_id), to: Resume
  defdelegate resume_import(scope, project, attempt_id, opts), to: Resume

  @doc """
  Runs an accepted import to a terminal state. Driven by `ImportProjectWorker`.
  """
  defdelegate perform_import(attempt_id), to: Execution
  defdelegate perform_import(attempt_id, opts), to: Execution

  @doc """
  Reconciles stale attempts. Driven by `ExpireProjectImportsWorker`.
  """
  defdelegate expire_stale_imports(), to: Expiration
  defdelegate expire_stale_imports(opts), to: Expiration
  defdelegate expire_stale_imports_batch(), to: Expiration
  defdelegate expire_stale_imports_batch(opts), to: Expiration

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
         {:ok, _project, _membership} <- Projects.authorize(scope, attempt.project_id, @import_action),
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

  # Lock order is project, membership, job, attempt — the one global order
  # every import transaction follows: the worker takes project, membership,
  # attempt; resume and the expiry sweep take job, attempt. `Oban.cancel_job/1`
  # dispatches onto this connection inside this transaction, so the job row is
  # taken exclusively *before* the attempt: taking the attempt first inverted
  # the documented order (`Expiration`) and could deadlock against a concurrent
  # resume or sweep of the same attempt, crashing the resume side's mount.
  defp cancel_attempt(%ProjectImportAttempt{} = candidate, user_id, opts) do
    Repo.transact(fn ->
      with {:ok, :authorized} <- authorize_import_locked(Repo, candidate.project_id, user_id) do
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
           |> ProjectImportAttempt.expired_changeset(TimeHelpers.now(), "import_cancelled")
           |> Repo.update(),
         :ok <- PlanCleanup.mark_plan_cleanup_pending(expired.plan_storage_key) do
      {:ok, expired}
    end
  end

  defp revise_import_review(scope, attempt_id, opts, revision_fun) do
    plan_load = Keyword.get(opts, :plan_load, &PlanStorage.load/1)

    with %ProjectImportAttempt{} = attempt <- Repo.get(ProjectImportAttempt, attempt_id),
         {:ok, project, _membership} <-
           Projects.authorize(scope, attempt.project_id, @import_action),
         # Before the status is even distinguished, let alone a plan decrypted
         # or a revision object written: a non-owner must be refused here,
         # indistinguishably from a missing attempt — the review lock's user
         # filter only catches them after the work, and the not-ready error
         # would otherwise be a state oracle for other members' attempts.
         :ok <- authorize_attempt_owner(attempt, scope.user.id),
         :ok <- ensure_attempt_ready_for_review(attempt),
         false <- ready_plan_deadline_reached?(attempt, TimeHelpers.now()),
         {:ok, plan} <- Shared.safely_load_plan(plan_load, attempt.plan_storage_key),
         :ok <- Shared.validate_attempt_plan_binding(attempt, plan),
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
      Queue.broadcast(revised_attempt)
      {:ok, revised_attempt, preview, revised_plan}
    else
      nil -> {:error, :not_found}
      true -> {:error, :import_expired}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_attempt_ready_for_review(%ProjectImportAttempt{status: "ready"}), do: :ok
  defp ensure_attempt_ready_for_review(%ProjectImportAttempt{}), do: {:error, :import_not_ready}

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
    cleanup_after = PlanCleanup.plan_cleanup_deadline(attempt)

    with {:ok, plan} <- Shared.bind_plan_to_attempt(plan, storage_key),
         {:ok, cleanup_request} <-
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
        PlanCleanup.defer_uncertain_plan_cleanup(cleanup_request)
        {:error, reason}
    end
  end

  defp swap_stored_plan_revision(cleanup_request, scope, project, attempt, preview, opts) do
    result =
      Repo.transact(fn ->
        with {:ok, :authorized} <-
               authorize_import_locked(Repo, project.id, scope.user.id),
             %ProjectImportAttempt{} = locked <-
               lock_reviewable_attempt(attempt.id, project.id, scope.user.id),
             true <- locked.plan_storage_key == attempt.plan_storage_key,
             false <- ready_plan_deadline_reached?(locked, TimeHelpers.now()),
             {:ok, :retained} <- retain_reserved_plan(Repo, cleanup_request.id),
             :ok <- PlanCleanup.mark_plan_cleanup_pending(Repo, locked.plan_storage_key),
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
        PlanCleanup.cleanup_reserved_plan(cleanup_request)
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
        PlanCleanup.cleanup_request(cleanup_request, opts)

      nil ->
        :ok
    end
  end

  @spec subscribe_project_imports(Project.t()) :: :ok | {:error, term()}
  def subscribe_project_imports(%Project{id: project_id}), do: Queue.subscribe(project_id)

  defp persist_import_plan(scope, project, plan, preview, binary, opts) do
    storage_key = PlanStorage.storage_key(project.id)
    expires_at = DateTime.add(TimeHelpers.now(), @plan_retention_seconds, :second)
    idempotency_key = idempotency_key(scope, project, plan, binary)

    with {:ok, plan} <- Shared.bind_plan_to_attempt(plan, storage_key),
         {:ok, cleanup_request} <-
           reserve_plan_cleanup(project, plan, storage_key, expires_at) do
      import = %{
        scope: scope,
        project: project,
        plan: plan,
        preview: preview,
        storage_key: storage_key,
        expires_at: expires_at,
        idempotency_key: idempotency_key,
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
        PlanCleanup.defer_uncertain_plan_cleanup(cleanup_request)
        {:error, reason}
    end
  end

  defp persist_stored_plan(cleanup_request, import) do
    %{
      scope: scope,
      project: project,
      plan: plan,
      preview: preview,
      expires_at: expires_at,
      idempotency_key: idempotency_key
    } = import

    scope
    |> insert_ready_attempt(project, plan, preview, cleanup_request, expires_at, idempotency_key)
    |> handle_stored_plan_result(cleanup_request, import)
  end

  defp handle_stored_plan_result({:ok, attempt}, _cleanup_request, %{preview: preview}), do: {:ok, attempt, preview}

  defp handle_stored_plan_result({:existing, attempt}, cleanup_request, %{scope: scope, project: project, opts: opts}) do
    PlanCleanup.cleanup_reserved_plan(cleanup_request)

    # The idempotency key deliberately survives review revisions. Returning
    # the newly parsed preview beside the existing attempt would pair two
    # different plans and let a subsequent draft overwrite the durable review.
    # Recovery also re-reads the row after loading its plan, so a concurrent
    # review revision cannot pair K1's preview with the attempt now pointing at
    # K2. Accepted attempts intentionally return no preview.
    Resume.resume_import(scope, project, attempt.id, opts)
  end

  defp handle_stored_plan_result({:error, reason}, cleanup_request, _import) do
    PlanCleanup.cleanup_reserved_plan(cleanup_request)
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

  defp insert_ready_attempt(scope, project, plan, preview, cleanup_request, expires_at, idempotency_key) do
    attrs = %{
      status: "ready",
      stage: "parsed",
      format: to_string(plan.format),
      source_kind: to_string(plan.source_kind),
      parser_version: plan.parser_version,
      replace_eligible: plan.replace_eligible == true,
      idempotency_key: idempotency_key,
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
      authorize_import_locked(repo, project.id, scope.user.id)
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

  defp authorize_import_locked(repo, project_id, user_id) do
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
         true <- ProjectMembership.can?(membership.role, @import_action) do
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

  defp persist_import_strategy(attempt, user_id, strategy) do
    Repo.transact(fn ->
      with {:ok, :authorized} <- authorize_import_locked(Repo, attempt.project_id, user_id),
           %ProjectImportAttempt{} = locked_attempt <-
             ProjectImportAttempt
             |> where(
               [candidate],
               candidate.id == ^attempt.id and candidate.project_id == ^attempt.project_id and
                 candidate.user_id == ^user_id
             )
             |> lock("FOR UPDATE")
             |> Repo.one() do
        update_locked_import_strategy(locked_attempt, strategy)
      else
        nil -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp update_locked_import_strategy(%ProjectImportAttempt{status: "ready"} = attempt, strategy) do
    attempt
    |> ProjectImportAttempt.conflict_strategy_changeset(strategy)
    |> Repo.update()
  end

  defp update_locked_import_strategy(%ProjectImportAttempt{}, _strategy), do: {:error, :import_not_ready}

  defp persist_import_mode(attempt, user_id, mode) do
    Repo.transact(fn ->
      with {:ok, :authorized} <- authorize_import_locked(Repo, attempt.project_id, user_id),
           %ProjectImportAttempt{} = locked_attempt <-
             ProjectImportAttempt
             |> where(
               [candidate],
               candidate.id == ^attempt.id and candidate.project_id == ^attempt.project_id and
                 candidate.user_id == ^user_id
             )
             |> lock("FOR UPDATE")
             |> Repo.one(),
           :ok <- ensure_import_mode_available(locked_attempt, mode) do
        update_locked_import_mode(locked_attempt, mode)
      else
        nil -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp update_locked_import_mode(%ProjectImportAttempt{status: "ready"} = attempt, mode) do
    attempt
    |> ProjectImportAttempt.import_mode_changeset(mode)
    |> Repo.update()
  end

  defp update_locked_import_mode(%ProjectImportAttempt{}, _mode), do: {:error, :import_not_ready}

  defp ensure_import_mode_available(%ProjectImportAttempt{}, "additive"), do: :ok

  defp ensure_import_mode_available(%ProjectImportAttempt{replace_eligible: true}, "replace_project"), do: :ok

  defp ensure_import_mode_available(%ProjectImportAttempt{}, "replace_project"),
    do: {:error, :import_replace_not_eligible}

  defp enqueue_locked_attempt(attempt_id, project_id, user_id, strategy, opts) do
    with {:ok, :authorized} <- authorize_import_locked(Repo, project_id, user_id),
         %ProjectImportAttempt{} = attempt <-
           ProjectImportAttempt
           |> where(
             [candidate],
             candidate.id == ^attempt_id and candidate.project_id == ^project_id and
               candidate.user_id == ^user_id
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
    if ready_plan_deadline_reached?(attempt, TimeHelpers.now()) do
      reject_invalid_review_attempt(attempt, :import_expired)
    else
      with :ok <- preflight_recovery_snapshot(attempt, opts) do
        enqueue_ready_attempt(attempt, strategy, opts)
      end
    end
  end

  defp enqueue_locked_attempt_by_status(%ProjectImportAttempt{status: status} = attempt, _strategy, _opts)
       when status in ["queued", "running", "retrying"] do
    {:ok, {:queued, attempt}}
  end

  defp enqueue_locked_attempt_by_status(%ProjectImportAttempt{}, _strategy, _opts), do: {:error, :import_not_ready}

  defp enqueue_ready_attempt(attempt, strategy, opts) do
    plan_load = Keyword.get(opts, :plan_load, &PlanStorage.load/1)

    with {:ok, plan} <- Shared.safely_load_plan(plan_load, attempt.plan_storage_key),
         :ok <- Shared.validate_attempt_plan_binding(attempt, plan),
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
           |> queued_import_changeset(
             strategy,
             job.id,
             PlanCleanup.bounded_plan_retention_deadline(attempt, TimeHelpers.now())
           )
           |> Ecto.Changeset.put_change(:counts, stringify_keys(preview.counts))
           |> Repo.update() do
      {:ok, {:queued, queued}}
    end
  end

  defp queued_import_changeset(%ProjectImportAttempt{import_mode: "additive"} = attempt, strategy, job_id, expires_at) do
    ProjectImportAttempt.queued_changeset(attempt, strategy, job_id, expires_at)
  end

  defp queued_import_changeset(
         %ProjectImportAttempt{import_mode: "replace_project"} = attempt,
         strategy,
         job_id,
         expires_at
       ) do
    ProjectImportAttempt.awaiting_snapshot_changeset(attempt, strategy, job_id, expires_at)
  end

  # Carries the reason as the attempt's `error_code` so a resumed attempt can be
  # told apart from a preview that merely aged out. Both land on `expired`.
  defp reject_invalid_review_attempt(attempt, reason) do
    with {:ok, expired} <-
           attempt
           |> ProjectImportAttempt.expired_changeset(TimeHelpers.now(), to_string(reason))
           |> Repo.update(),
         :ok <- PlanCleanup.mark_plan_cleanup_pending(expired.plan_storage_key) do
      {:ok, {:rejected, expired, reason}}
    end
  end

  defp ready_plan_deadline_reached?(%ProjectImportAttempt{} = attempt, now) do
    not DateTime.after?(attempt.expires_at, now) or
      PlanCleanup.absolute_plan_deadline_reached?(attempt, now)
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

  defp normalize_strategy(strategy) when is_atom(strategy), do: normalize_strategy(to_string(strategy))

  defp normalize_strategy(strategy) when strategy in ~w(skip overwrite rename), do: {:ok, strategy}
  defp normalize_strategy(_strategy), do: {:error, :invalid_conflict_strategy}

  defp normalize_import_mode(mode) when is_atom(mode), do: normalize_import_mode(to_string(mode))

  defp normalize_import_mode(mode) when mode in ~w(additive replace_project), do: {:ok, mode}
  defp normalize_import_mode(_mode), do: {:error, :invalid_import_mode}

  defp preflight_recovery_snapshot(%ProjectImportAttempt{import_mode: "additive"}, opts) do
    validate_enqueue_import_mode("additive", opts)
  end

  defp preflight_recovery_snapshot(%ProjectImportAttempt{import_mode: "replace_project"} = attempt, opts) do
    with :ok <- ensure_import_mode_available(attempt, "replace_project"),
         :ok <- validate_enqueue_import_mode("replace_project", opts),
         :ok <- require_replace_acknowledgement(opts),
         request_key when is_binary(request_key) <- attempt.snapshot_request_key do
      :ok
    else
      nil -> {:error, :invalid_import_snapshot_request}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_import_snapshot_request}
    end
  end

  defp preflight_recovery_snapshot(%ProjectImportAttempt{}, _opts), do: {:error, :invalid_import_mode}

  defp validate_enqueue_import_mode(expected_mode, opts) do
    case normalize_import_mode(Keyword.get(opts, :import_mode, "additive")) do
      {:ok, ^expected_mode} -> :ok
      {:ok, _other_mode} -> {:error, :stale_import_mode}
      {:error, _reason} -> {:error, :invalid_import_mode}
    end
  end

  defp require_replace_acknowledgement(opts) do
    if Keyword.get(opts, :replace_acknowledged, false) == true,
      do: :ok,
      else: {:error, :replace_import_confirmation_required}
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
end
