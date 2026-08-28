defmodule Storyarn.Projects.Imports.Replacement do
  @moduledoc """
  Snapshot gate and transactional cleanup for an explicit project replacement.

  The snapshot is a normal user-visible full project snapshot. Nothing is
  removed until it is ready, verified, still matches its durable import
  binding, and a freshly rebuilt canonical project checksum matches the state
  captured by that snapshot.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.FlowProjectTrash
  alias Storyarn.Projects.Imports.Error
  alias Storyarn.Projects.Imports.ProjectImportAttempt
  alias Storyarn.Projects.Imports.Telemetry
  alias Storyarn.Projects.Persistence.FlowRecord, as: Flow
  alias Storyarn.Projects.Persistence.LocalizedTextRecord, as: LocalizedText
  alias Storyarn.Projects.Persistence.ProjectLanguageRecord, as: ProjectLanguage
  alias Storyarn.Projects.Persistence.SceneRecord, as: Scene
  alias Storyarn.Projects.Persistence.SheetRecord, as: Sheet
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.SceneProjectTrash
  alias Storyarn.Projects.SheetProjectTrash
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.Builders.AssetHashResolver
  alias Storyarn.Projects.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Projects.Versioning.ProjectSnapshot
  alias Storyarn.Projects.Versioning.SnapshotArchiveStorage
  alias Storyarn.Projects.Versioning.SnapshotCleanupIntent
  alias Storyarn.Repo

  @terminal_cleanup_batch_size 50
  @terminal_cleanup_retry_seconds 300
  @terminal_attempt_statuses ~w(failed expired)
  @active_snapshot_states ~w(pending building verifying)
  @deletable_snapshot_states ~w(ready failed cancelled)
  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  @type readiness_result ::
          {:ok, ProjectImportAttempt.t()} | {:snooze, pos_integer()} | {:error, term()}

  @doc "Binds the exact ready snapshot identity, or asks Oban to wait without consuming an import retry."
  @spec ensure_snapshot_ready(ProjectImportAttempt.t(), Project.t(), keyword()) :: readiness_result()
  def ensure_snapshot_ready(attempt, project, opts \\ [])

  def ensure_snapshot_ready(%ProjectImportAttempt{import_mode: "additive"} = attempt, %Project{}, _opts),
    do: {:ok, attempt}

  def ensure_snapshot_ready(%ProjectImportAttempt{import_mode: "replace_project"} = attempt, %Project{} = project, opts)
      when is_list(opts) do
    snapshot_previously_bound? = is_integer(attempt.pre_import_snapshot_id)

    with {:ok, bound_attempt} <- ensure_snapshot_requested(attempt, project, opts) do
      result =
        bound_attempt
        |> inspect_snapshot_state(project)
        |> normalize_readiness_transaction()

      emit_snapshot_transition(bound_attempt, result, snapshot_previously_bound?)
      result
    end
  end

  def ensure_snapshot_ready(%ProjectImportAttempt{}, %Project{}, _opts), do: {:error, :invalid_import_mode}

  @doc "Locks the bound recovery snapshot before the import-attempt row in the final transaction."
  @spec prelock_snapshot_in_transaction(ProjectImportAttempt.t()) :: :ok | {:error, term()}
  def prelock_snapshot_in_transaction(%ProjectImportAttempt{import_mode: "additive"}), do: :ok

  def prelock_snapshot_in_transaction(%ProjectImportAttempt{
        import_mode: "replace_project",
        pre_import_snapshot_id: snapshot_id
      }) do
    cond do
      not Repo.in_transaction?() ->
        {:error, :import_transaction_required}

      match?(%ProjectSnapshot{}, lock_snapshot(snapshot_id)) ->
        :ok

      true ->
        {:error, :pre_import_snapshot_unavailable}
    end
  end

  def prelock_snapshot_in_transaction(%ProjectImportAttempt{}), do: {:error, :invalid_import_mode}

  @doc "Verifies the recovery fence and trashes only replaceable narrative state inside the final import transaction."
  @spec prepare_project_in_transaction(ProjectImportAttempt.t(), Project.t()) ::
          :ok | {:error, term()}
  def prepare_project_in_transaction(%ProjectImportAttempt{import_mode: "additive"}, %Project{}), do: :ok

  def prepare_project_in_transaction(
        %ProjectImportAttempt{import_mode: "replace_project"} = attempt,
        %Project{} = project
      ) do
    cond do
      not Repo.in_transaction?() ->
        {:error, :import_transaction_required}

      not Platform.workspace_lock_held?(project.workspace_id) ->
        {:error, :storage_accounting_lock_required}

      true ->
        verify_and_prepare_project(attempt, project)
    end
  end

  def prepare_project_in_transaction(%ProjectImportAttempt{}, %Project{}), do: {:error, :invalid_import_mode}

  @doc false
  @spec cleanup_terminal_recovery_snapshot(ProjectImportAttempt.t()) ::
          {:ok, :cleaned | :deferred | :not_found | :not_terminal} | {:error, atom()}
  def cleanup_terminal_recovery_snapshot(%ProjectImportAttempt{import_mode: mode}) when mode != "replace_project",
    do: {:ok, :not_terminal}

  def cleanup_terminal_recovery_snapshot(%ProjectImportAttempt{status: status})
      when status not in @terminal_attempt_statuses, do: {:ok, :not_terminal}

  def cleanup_terminal_recovery_snapshot(%ProjectImportAttempt{} = attempt) do
    attempt
    |> do_cleanup_terminal_recovery_snapshot()
    |> handle_cleanup_result(attempt)
  rescue
    exception ->
      report_snapshot_cleanup_failure(attempt, inspect(exception.__struct__))
      defer_snapshot_cleanup_retry(attempt.id)
      {:error, :pre_import_snapshot_cleanup_failed}
  catch
    _kind, _reason ->
      report_snapshot_cleanup_failure(attempt, "none")
      defer_snapshot_cleanup_retry(attempt.id)
      {:error, :pre_import_snapshot_cleanup_failed}
  end

  @doc false
  @spec cleanup_terminal_recovery_snapshots(keyword()) :: %{
          cleaned_count: non_neg_integer(),
          failure_count: non_neg_integer(),
          more?: boolean()
        }
  def cleanup_terminal_recovery_snapshots(opts \\ []) when is_list(opts) do
    cutoff = DateTime.add(TimeHelpers.now(), -@terminal_cleanup_retry_seconds, :second)
    limit = terminal_cleanup_batch_size(opts)

    {cleaned_count, failure_count} =
      cutoff
      |> terminal_cleanup_candidates(limit)
      |> Enum.reduce({0, 0}, fn attempt, {cleaned_count, failure_count} ->
        case cleanup_terminal_recovery_snapshot(attempt) do
          {:ok, :cleaned} -> {cleaned_count + 1, failure_count}
          {:ok, _outcome} -> {cleaned_count, failure_count}
          {:error, _reason} -> {cleaned_count, failure_count + 1}
        end
      end)

    %{
      cleaned_count: cleaned_count,
      failure_count: failure_count,
      more?: terminal_cleanup_candidates_exist?(cutoff)
    }
  end

  defp do_cleanup_terminal_recovery_snapshot(%ProjectImportAttempt{} = attempt_hint) do
    case Repo.get(Project, attempt_hint.project_id) do
      %Project{deleted_at: nil} = project ->
        result =
          Platform.transact_with_workspace_lock(project.workspace_id, fn _workspace ->
            cleanup_terminal_recovery_snapshot_locked(attempt_hint, project)
          end)

        publish_cleanup_transition(result)

      _missing_or_deleted ->
        {:ok, :not_found}
    end
  end

  # The global order is workspace, project, snapshot, attempt. Snapshot comes
  # before the attempt because deleting it nilifies the attempt FK.
  defp cleanup_terminal_recovery_snapshot_locked(attempt_hint, project_hint) do
    with %Project{} = project <- lock_active_project(project_hint),
         snapshot = lock_terminal_cleanup_snapshot(attempt_hint, project),
         %ProjectImportAttempt{} = attempt <- lock_terminal_cleanup_attempt(attempt_hint, project),
         :ok <- validate_terminal_cleanup_attempt(attempt),
         :ok <- validate_terminal_cleanup_snapshot(attempt, project, snapshot) do
      cleanup_snapshot_by_state(snapshot, project.workspace_id)
    else
      nil -> {:ok, :not_found}
      {:error, :not_terminal} -> {:ok, :not_terminal}
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_import_snapshot_identity}
    end
  end

  defp cleanup_snapshot_by_state(nil, _workspace_id), do: {:ok, :not_found}

  defp cleanup_snapshot_by_state(%ProjectSnapshot{lifecycle_state: state} = snapshot, workspace_id)
       when state in @active_snapshot_states do
    case Versioning.request_import_recovery_snapshot_cancellation_in_transaction(snapshot, workspace_id) do
      {:ok, %ProjectSnapshot{lifecycle_state: terminal_state} = terminal_snapshot}
      when terminal_state in @deletable_snapshot_states ->
        prepare_terminal_snapshot_cleanup(terminal_snapshot, workspace_id)

      {:ok, %ProjectSnapshot{} = cancellation_requested} ->
        {:ok, {:cancellation_requested, cancellation_requested}}

      {:error, :snapshot_finalization_in_progress} ->
        {:ok, :deferred}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cleanup_snapshot_by_state(%ProjectSnapshot{lifecycle_state: state} = snapshot, workspace_id)
       when state in @deletable_snapshot_states do
    prepare_terminal_snapshot_cleanup(snapshot, workspace_id)
  end

  defp cleanup_snapshot_by_state(%ProjectSnapshot{}, _workspace_id), do: {:ok, :deferred}

  defp prepare_terminal_snapshot_cleanup(snapshot, workspace_id) do
    case Versioning.prepare_abandoned_import_snapshot_cleanup_in_transaction(snapshot, workspace_id) do
      {:ok, %SnapshotCleanupIntent{} = intent} -> {:ok, {:cleanup_intent, intent}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp publish_cleanup_transition({:ok, {:cleanup_intent, %SnapshotCleanupIntent{} = intent}}) do
    Versioning.publish_committed_snapshot_cleanup_intents([intent])
    {:ok, :cleaned}
  end

  defp publish_cleanup_transition({:ok, {:cancellation_requested, %ProjectSnapshot{} = snapshot}}) do
    Versioning.publish_committed_import_recovery_snapshot_cancellation(snapshot)
    {:ok, :deferred}
  end

  defp publish_cleanup_transition({:ok, outcome}) when outcome in [:deferred, :not_found, :not_terminal],
    do: {:ok, outcome}

  defp publish_cleanup_transition({:error, reason}), do: {:error, reason}

  defp handle_cleanup_result({:ok, outcome}, _attempt) when outcome in [:cleaned, :not_found, :not_terminal],
    do: {:ok, outcome}

  defp handle_cleanup_result({:ok, :deferred}, attempt) do
    defer_snapshot_cleanup_retry(attempt.id)
    {:ok, :deferred}
  end

  defp handle_cleanup_result({:error, _reason}, attempt) do
    report_snapshot_cleanup_failure(attempt, "none")
    defer_snapshot_cleanup_retry(attempt.id)
    {:error, :pre_import_snapshot_cleanup_failed}
  end

  defp terminal_cleanup_candidates(cutoff, limit) do
    cutoff
    |> terminal_cleanup_candidate_query()
    |> order_by([attempt, _snapshot, _project], asc: attempt.id)
    |> limit(^limit)
    |> select([attempt, _snapshot, _project], attempt)
    |> Repo.all()
  end

  defp terminal_cleanup_candidates_exist?(cutoff) do
    cutoff
    |> terminal_cleanup_candidate_query()
    |> Repo.exists?()
  end

  defp terminal_cleanup_candidate_query(cutoff) do
    from attempt in ProjectImportAttempt,
      join: snapshot in ProjectSnapshot,
      on:
        snapshot.project_id == attempt.project_id and
          ((not is_nil(attempt.pre_import_snapshot_id) and
              snapshot.id == attempt.pre_import_snapshot_id) or
             (is_nil(attempt.pre_import_snapshot_id) and
                snapshot.idempotency_key == fragment("?::text", attempt.snapshot_request_key))),
      join: project in Project,
      on: project.id == attempt.project_id and is_nil(project.deleted_at),
      where:
        attempt.import_mode == "replace_project" and
          attempt.status in ^@terminal_attempt_statuses and
          attempt.updated_at <= ^cutoff
  end

  defp terminal_cleanup_batch_size(opts) do
    case Keyword.get(opts, :snapshot_cleanup_batch_size, @terminal_cleanup_batch_size) do
      size when is_integer(size) and size > 0 -> min(size, @terminal_cleanup_batch_size)
      _invalid -> @terminal_cleanup_batch_size
    end
  end

  defp lock_terminal_cleanup_snapshot(%ProjectImportAttempt{pre_import_snapshot_id: snapshot_id}, %Project{id: project_id})
       when is_integer(snapshot_id) and snapshot_id > 0 do
    Repo.one(
      from snapshot in ProjectSnapshot,
        where: snapshot.id == ^snapshot_id and snapshot.project_id == ^project_id,
        lock: "FOR UPDATE"
    )
  end

  defp lock_terminal_cleanup_snapshot(
         %ProjectImportAttempt{pre_import_snapshot_id: nil, snapshot_request_key: request_key},
         %Project{id: project_id}
       )
       when is_binary(request_key) do
    Repo.one(
      from snapshot in ProjectSnapshot,
        where:
          snapshot.project_id == ^project_id and
            snapshot.idempotency_key == ^request_key,
        lock: "FOR UPDATE"
    )
  end

  defp lock_terminal_cleanup_snapshot(%ProjectImportAttempt{}, %Project{}), do: nil

  defp lock_terminal_cleanup_attempt(attempt_hint, project) do
    Repo.one(
      from attempt in ProjectImportAttempt,
        where: attempt.id == ^attempt_hint.id and attempt.project_id == ^project.id,
        lock: "FOR UPDATE"
    )
  end

  defp validate_terminal_cleanup_attempt(attempt) do
    if attempt.import_mode == "replace_project" and attempt.replace_eligible == true and
         attempt.status in @terminal_attempt_statuses and is_nil(attempt.replacement_prepared_at) do
      :ok
    else
      {:error, :not_terminal}
    end
  end

  defp validate_terminal_cleanup_snapshot(_attempt, _project, nil), do: :ok

  defp validate_terminal_cleanup_snapshot(attempt, project, snapshot) do
    valid_reference? =
      case attempt.pre_import_snapshot_id do
        snapshot_id when is_integer(snapshot_id) -> snapshot.id == snapshot_id
        nil -> is_nil(attempt.snapshot_reference_bound_at)
      end

    valid? =
      Enum.all?([
        valid_reference?,
        snapshot.project_id == project.id,
        snapshot.idempotency_key == attempt.snapshot_request_key,
        snapshot.mode == "full",
        snapshot.origin == "user",
        snapshot.is_auto == false
      ])

    if valid?, do: :ok, else: {:error, :invalid_import_snapshot_identity}
  end

  defp defer_snapshot_cleanup_retry(attempt_id) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(attempt in ProjectImportAttempt,
        where:
          attempt.id == ^attempt_id and attempt.import_mode == "replace_project" and
            attempt.status in ^@terminal_attempt_statuses
      ),
      set: [updated_at: now]
    )

    :ok
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp report_snapshot_cleanup_failure(attempt, exception_module) do
    Error.report(%{
      format: attempt.format,
      parser_version: attempt.parser_version,
      import_mode: attempt.import_mode,
      phase: "snapshot_cleanup",
      error_code: "pre_import_snapshot_cleanup_failed",
      exception_module: exception_module
    })
  end

  defp ensure_snapshot_requested(
         %ProjectImportAttempt{pre_import_snapshot_id: snapshot_id, snapshot_reference_bound_at: %DateTime{}} = attempt,
         %Project{},
         _opts
       )
       when is_integer(snapshot_id) and snapshot_id > 0, do: {:ok, attempt}

  defp ensure_snapshot_requested(%ProjectImportAttempt{pre_import_snapshot_id: snapshot_id}, %Project{}, _opts)
       when is_integer(snapshot_id) and snapshot_id > 0, do: {:error, :invalid_import_snapshot_identity}

  defp ensure_snapshot_requested(
         %ProjectImportAttempt{pre_import_snapshot_id: nil, snapshot_reference_bound_at: %DateTime{}},
         %Project{},
         _opts
       ), do: {:error, :pre_import_snapshot_unavailable}

  defp ensure_snapshot_requested(
         %ProjectImportAttempt{pre_import_snapshot_id: nil, snapshot_capture_digest: digest},
         %Project{},
         _opts
       )
       when is_binary(digest), do: {:error, :pre_import_snapshot_unavailable}

  defp ensure_snapshot_requested(%ProjectImportAttempt{} = attempt, %Project{} = project, opts) do
    with {:ok, snapshot} <- request_recovery_snapshot(attempt, project, opts) do
      bind_requested_snapshot(attempt, project, snapshot)
    end
  end

  defp request_recovery_snapshot(attempt, project, opts) do
    request = Keyword.get(opts, :snapshot_request, &Versioning.request_full_project_snapshot/3)

    attrs = %{
      mode: "full",
      idempotency_key: attempt.snapshot_request_key,
      title: "Before Yarn project replacement",
      description: "Recovery point created before replacing narrative project content."
    }

    case request.(%{user: attempt.user}, project, attrs) do
      {:ok, %ProjectSnapshot{} = snapshot} -> {:ok, snapshot}
      {:error, reason} -> {:error, normalize_snapshot_request_error(reason)}
      {:error, reason, _details} -> {:error, normalize_snapshot_request_error(reason)}
      _invalid -> {:error, :pre_import_snapshot_request_failed}
    end
  rescue
    exception ->
      {:error, {:pre_import_snapshot_request_failed, inspect(exception.__struct__)}}
  catch
    kind, _reason when kind in [:throw, :exit, :error] ->
      {:error, {:pre_import_snapshot_request_failed, Atom.to_string(kind)}}
  end

  defp bind_requested_snapshot(attempt_hint, project_hint, snapshot_hint) do
    Repo.transact(fn ->
      with %Project{} = project <- lock_active_project(project_hint),
           %ProjectSnapshot{} = snapshot <- lock_snapshot(snapshot_hint.id),
           %ProjectImportAttempt{} = attempt <- lock_attempt(attempt_hint, project),
           true <- attempt.status == "queued" and attempt.stage == "awaiting_snapshot",
           :ok <- validate_unbound_snapshot_request_identity(attempt, project, snapshot),
           {:ok, bound_attempt} <- persist_snapshot_reference(attempt, snapshot.id) do
        {:ok, bound_attempt}
      else
        nil -> {:error, :pre_import_snapshot_unavailable}
        false -> {:error, :import_not_queued}
        {:error, reason} -> {:error, reason}
        _invalid -> {:error, :invalid_import_snapshot_identity}
      end
    end)
  end

  defp persist_snapshot_reference(%ProjectImportAttempt{pre_import_snapshot_id: nil} = attempt, snapshot_id) do
    attempt
    |> Ecto.Changeset.change(
      pre_import_snapshot_id: snapshot_id,
      snapshot_reference_bound_at: TimeHelpers.now(),
      error_code: nil,
      error_message: nil,
      error_report: %{}
    )
    |> Repo.update()
  end

  defp persist_snapshot_reference(
         %ProjectImportAttempt{pre_import_snapshot_id: snapshot_id, snapshot_reference_bound_at: %DateTime{}} = attempt,
         snapshot_id
       ), do: {:ok, attempt}

  defp persist_snapshot_reference(%ProjectImportAttempt{}, _snapshot_id), do: {:error, :invalid_import_snapshot_identity}

  defp inspect_snapshot_state(attempt_hint, project_hint) do
    Repo.transact(fn ->
      with %Project{} = project <- lock_active_project(project_hint),
           %ProjectSnapshot{} = snapshot <- lock_snapshot(attempt_hint.pre_import_snapshot_id),
           %ProjectImportAttempt{} = attempt <- lock_attempt(attempt_hint, project),
           true <- attempt.pre_import_snapshot_id == snapshot.id,
           true <- attempt.status in ["queued", "running", "retrying"],
           :ok <- validate_snapshot_request_identity(attempt, project, snapshot) do
        bind_snapshot_by_state(attempt, snapshot)
      else
        nil -> {:error, :pre_import_snapshot_unavailable}
        false -> {:error, :import_not_queued}
        {:error, reason} -> {:error, reason}
        _invalid -> {:error, :invalid_import_snapshot_identity}
      end
    end)
  end

  defp bind_snapshot_by_state(attempt, %ProjectSnapshot{lifecycle_state: state})
       when state in ["pending", "building", "verifying"] do
    if attempt.status == "queued" and attempt.stage == "awaiting_snapshot" and
         is_nil(attempt.snapshot_capture_digest) do
      case attempt |> ProjectImportAttempt.snapshot_waiting_changeset() |> Repo.update() do
        {:ok, waiting} -> {:ok, {:snooze, snapshot_wait_seconds(waiting), waiting}}
        {:error, _changeset} -> {:error, :invalid_import_snapshot_identity}
      end
    else
      {:error, :invalid_import_snapshot_identity}
    end
  end

  defp bind_snapshot_by_state(attempt, %ProjectSnapshot{lifecycle_state: "ready"} = snapshot) do
    with :ok <- validate_ready_snapshot(snapshot),
         :ok <- validate_or_bind_snapshot_identity(attempt, snapshot) do
      {:ok, {:ready, current_attempt(attempt.id)}}
    end
  end

  defp bind_snapshot_by_state(_attempt, %ProjectSnapshot{}), do: {:error, :pre_import_snapshot_unavailable}

  defp validate_or_bind_snapshot_identity(%ProjectImportAttempt{snapshot_capture_digest: nil} = attempt, snapshot) do
    if attempt.status == "queued" and attempt.stage == "awaiting_snapshot" do
      case attempt
           |> ProjectImportAttempt.snapshot_ready_changeset(snapshot)
           |> Repo.update() do
        {:ok, _updated} -> :ok
        {:error, _changeset} -> {:error, :invalid_import_snapshot_identity}
      end
    else
      {:error, :invalid_import_snapshot_identity}
    end
  end

  defp validate_or_bind_snapshot_identity(%ProjectImportAttempt{} = attempt, snapshot) do
    if bound_snapshot_identity_matches?(attempt, snapshot), do: :ok, else: {:error, :invalid_import_snapshot_identity}
  end

  defp normalize_readiness_transaction({:ok, {:ready, attempt}}), do: {:ok, attempt}
  defp normalize_readiness_transaction({:ok, {:snooze, seconds, _attempt}}), do: {:snooze, seconds}
  defp normalize_readiness_transaction({:error, reason}), do: {:error, reason}

  defp snapshot_wait_seconds(attempt) do
    anchor = attempt.snapshot_reference_bound_at || attempt.inserted_at
    age_seconds = DateTime.diff(TimeHelpers.now(), anchor, :second)

    cond do
      age_seconds < 30 -> 5
      age_seconds < 120 -> 15
      age_seconds < 600 -> 60
      true -> 300
    end
  end

  defp emit_snapshot_transition(attempt, {:snooze, _seconds}, false),
    do: Telemetry.emit_snapshot_transition(attempt, "awaiting_snapshot")

  defp emit_snapshot_transition(
         %ProjectImportAttempt{stage: "awaiting_snapshot"},
         {:ok, %ProjectImportAttempt{stage: "queued"} = ready_attempt},
         _previously_bound
       ), do: Telemetry.emit_snapshot_transition(ready_attempt, "ready")

  defp emit_snapshot_transition(_attempt, _result, _previously_bound), do: :ok

  defp verify_and_prepare_project(attempt, project) do
    with %ProjectSnapshot{} = snapshot <- lock_snapshot(attempt.pre_import_snapshot_id),
         :ok <- validate_snapshot_request_identity(attempt, project, snapshot),
         :ok <- validate_ready_snapshot(snapshot),
         true <- bound_snapshot_identity_matches?(attempt, snapshot),
         {:ok, checksum} <- current_project_checksum(project),
         true <- Plug.Crypto.secure_compare(checksum, snapshot.project_checksum),
         {:ok, roots} <- active_roots(project.id),
         :ok <- trash_active_graph(roots),
         :ok <- archive_active_localization(project.id) do
      :ok
    else
      nil -> {:error, :pre_import_snapshot_unavailable}
      false -> {:error, :project_changed_since_import_snapshot}
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_import_snapshot_identity}
    end
  end

  defp current_project_checksum(project) do
    assets = Assets.list_assets_for_export(project.id)

    snapshot =
      project.id
      |> ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(
        localization_scope: :active,
        include_referenced_tombstones: true
      )
      |> put_asset_capture_contract(assets)

    case SnapshotArchiveStorage.canonical_project_checksum(snapshot, assets) do
      {:ok, checksum} when is_binary(checksum) -> {:ok, checksum}
      {:error, _reason} -> {:error, :pre_import_snapshot_verification_failed}
      _invalid -> {:error, :pre_import_snapshot_verification_failed}
    end
  end

  defp put_asset_capture_contract(snapshot, assets) do
    {asset_blob_hashes, asset_metadata} = AssetHashResolver.capture_catalog_maps(assets)

    snapshot
    |> Map.put("asset_restore_contract_version", AssetHashResolver.exact_restore_contract_version())
    |> Map.put("asset_blob_hashes", asset_blob_hashes)
    |> Map.put("asset_metadata", asset_metadata)
  end

  defp active_roots(project_id) do
    {:ok,
     %{
       flows: root_entities(Flow, project_id),
       scenes: root_entities(Scene, project_id),
       sheets: root_entities(Sheet, project_id)
     }}
  end

  defp root_entities(schema, project_id) do
    Repo.all(
      from entity in schema,
        where:
          entity.project_id == ^project_id and is_nil(entity.parent_id) and
            is_nil(entity.deleted_at),
        order_by: [asc: entity.id]
    )
  end

  defp trash_active_graph(roots) do
    with :ok <- trash_roots(roots.flows, &FlowProjectTrash.delete_subtree_in_transaction/1),
         :ok <- trash_roots(roots.scenes, &SceneProjectTrash.delete_subtree_in_transaction/1) do
      trash_roots(roots.sheets, &SheetProjectTrash.delete_subtree_in_transaction/1)
    end
  end

  defp trash_roots(roots, delete_fun) do
    Enum.reduce_while(roots, :ok, fn root, :ok ->
      case delete_fun.(root) do
        %{entity: _entity} -> {:cont, :ok}
        {:ok, %{entity: _entity}} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
        _invalid -> {:halt, {:error, :import_project_replacement_failed}}
      end
    end)
  end

  defp archive_active_localization(project_id) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(language in ProjectLanguage,
        where: language.project_id == ^project_id and is_nil(language.archived_at)
      ),
      set: [archived_at: now, updated_at: now]
    )

    Repo.update_all(
      from(text in LocalizedText,
        where: text.project_id == ^project_id and is_nil(text.archived_at)
      ),
      set: [archived_at: now, archive_reason: "version_replaced", updated_at: now]
    )

    :ok
  end

  defp validate_unbound_snapshot_request_identity(attempt, project, snapshot) do
    valid_identity? =
      Enum.all?([
        attempt.import_mode == "replace_project",
        attempt.replace_eligible == true,
        snapshot.project_id == project.id,
        snapshot.created_by_id == attempt.user_id,
        snapshot.idempotency_key == attempt.snapshot_request_key,
        snapshot.mode == "full",
        snapshot.origin == "user",
        snapshot.is_auto == false
      ])

    if valid_identity?, do: :ok, else: {:error, :invalid_import_snapshot_identity}
  end

  defp validate_snapshot_request_identity(attempt, project, snapshot) do
    with true <- attempt.pre_import_snapshot_id == snapshot.id,
         :ok <- validate_unbound_snapshot_request_identity(attempt, project, snapshot) do
      :ok
    else
      _mismatch -> {:error, :invalid_import_snapshot_identity}
    end
  end

  defp validate_ready_snapshot(snapshot) do
    with {:ok, _identity} <- Versioning.restorable_project_snapshot_identity(snapshot),
         true <- valid_sha256?(snapshot.capture_digest),
         true <- valid_sha256?(snapshot.project_checksum) do
      :ok
    else
      {:error, :project_snapshot_not_restorable} -> {:error, :pre_import_snapshot_unavailable}
      _invalid -> {:error, :invalid_import_snapshot_identity}
    end
  end

  defp bound_snapshot_identity_matches?(attempt, snapshot) do
    Enum.all?([
      attempt.snapshot_lifecycle_generation == snapshot.lifecycle_generation,
      attempt.snapshot_accounting_generation == snapshot.accounting_generation,
      secure_equal?(attempt.snapshot_capture_digest, snapshot.capture_digest),
      secure_equal?(attempt.snapshot_project_checksum, snapshot.project_checksum),
      attempt.snapshot_archive_storage_key == snapshot.archive_storage_key,
      attempt.snapshot_archive_size_bytes == snapshot.archive_size_bytes,
      secure_equal?(attempt.snapshot_archive_checksum, snapshot.archive_checksum),
      attempt.snapshot_manifest_storage_key == snapshot.manifest_storage_key,
      attempt.snapshot_manifest_size_bytes == snapshot.manifest_size_bytes,
      secure_equal?(attempt.snapshot_manifest_checksum, snapshot.manifest_checksum)
    ])
  end

  defp secure_equal?(left, right) when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure_equal?(_left, _right), do: false

  defp valid_sha256?(value), do: is_binary(value) and Regex.match?(@sha256_regex, value)

  defp lock_snapshot(snapshot_id) when is_integer(snapshot_id) and snapshot_id > 0 do
    Repo.one(
      from snapshot in ProjectSnapshot,
        where: snapshot.id == ^snapshot_id,
        lock: "FOR SHARE"
    )
  end

  defp lock_snapshot(_snapshot_id), do: nil

  defp lock_active_project(%Project{id: project_id, workspace_id: workspace_id}) do
    Repo.one(
      from project in Project,
        where:
          project.id == ^project_id and project.workspace_id == ^workspace_id and
            is_nil(project.deleted_at),
        lock: "FOR UPDATE"
    )
  end

  defp lock_attempt(attempt, project) do
    Repo.one(
      from candidate in ProjectImportAttempt,
        where:
          candidate.id == ^attempt.id and candidate.project_id == ^project.id and
            candidate.user_id == ^attempt.user_id,
        lock: "FOR UPDATE"
    )
  end

  defp current_attempt(id), do: Repo.get!(ProjectImportAttempt, id)

  defp normalize_snapshot_request_error(reason) when reason in [:limit_reached, :snapshot_limit_reached],
    do: :pre_import_snapshot_capacity_unavailable

  defp normalize_snapshot_request_error(:unauthorized), do: :unauthorized
  defp normalize_snapshot_request_error(:invalid_snapshot_request), do: :invalid_import_snapshot_request
  defp normalize_snapshot_request_error(_reason), do: :pre_import_snapshot_request_failed
end
