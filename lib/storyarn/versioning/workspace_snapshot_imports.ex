defmodule Storyarn.Versioning.WorkspaceSnapshotImports do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Assets.StorageHash
  alias Storyarn.Assets.StorageKeyLock
  alias Storyarn.Billing
  alias Storyarn.Notifications
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Versioning.ProjectRecovery
  alias Storyarn.Versioning.ProjectSnapshotArchiveReader
  alias Storyarn.Versioning.ProjectSnapshotAssetMaterializer
  alias Storyarn.Versioning.WorkspaceSnapshotImport
  alias Storyarn.Workers.ImportProjectSnapshotWorker
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  require Logger

  @active_statuses ~w(queued running retrying)
  @terminal_delivery_job_states ~w(cancelled completed discarded)
  @archive_content_type "application/zip"
  @file_chunk_size 1_048_576
  @progress_flush_bytes 1_048_576
  @history_limit 50
  @lock_snooze_seconds 30

  @doc "Validates, reserves and durably stages one standalone project snapshot."
  def request(scope, workspace, uploaded_path, attrs, opts \\ [])

  def request(%Scope{user: %User{id: user_id}} = scope, %Workspace{id: workspace_id}, uploaded_path, attrs, opts)
      when is_binary(uploaded_path) and is_map(attrs) and is_list(opts) do
    reader = Keyword.get(opts, :archive_reader, ProjectSnapshotArchiveReader)
    storage = Keyword.get(opts, :storage, Storage)

    with {:ok, workspace, _membership} <-
           Workspaces.authorize(scope, workspace_id, :access_workspace_settings),
         {:ok, _workspace, _membership} <-
           Workspaces.authorize(scope, workspace_id, :create_project),
         {:ok, original_filename} <- original_filename(attrs),
         {:ok, preflight} <- reader.preflight_file(uploaded_path),
         :ok <- ProjectRecovery.validate_snapshot_import(preflight.project),
         {:ok, project_name} <- project_name(preflight.project),
         :ok <- validate_preflight(preflight) do
      semantic_key = semantic_key(user_id, workspace_id, preflight)

      admission_context = %{
        scope: scope,
        workspace: workspace,
        uploaded_path: uploaded_path,
        original_filename: original_filename,
        project_name: project_name,
        preflight: preflight,
        storage: storage
      }

      StorageKeyLock.with_session_lock(semantic_lock_name(semantic_key), fn ->
        admit_after_semantic_dedupe(admission_context)
      end)
    end
  rescue
    error ->
      Logger.warning("Workspace snapshot import admission raised error=#{safe_error(error)}")
      {:error, :snapshot_import_unavailable}
  catch
    kind, reason ->
      Logger.warning("Workspace snapshot import admission failed error=#{safe_error({kind, reason})}")
      {:error, :snapshot_import_unavailable}
  end

  def request(%Scope{}, %Workspace{}, _uploaded_path, _attrs, _opts), do: {:error, :unauthorized}
  def request(_scope, _workspace, _uploaded_path, _attrs, _opts), do: {:error, :invalid_snapshot_import_request}

  @doc "Lists recent imports visible in one workspace settings surface."
  def list(%Scope{} = scope, %Workspace{id: workspace_id}) do
    case Workspaces.authorize(scope, workspace_id, :access_workspace_settings) do
      {:ok, _workspace, _membership} ->
        WorkspaceSnapshotImport
        |> where([import], import.workspace_id == ^workspace_id)
        |> order_by([import], desc: import.inserted_at, desc: import.id)
        |> limit(@history_limit)
        |> preload(:project)
        |> Repo.all()

      {:error, _reason} ->
        []
    end
  end

  def list(_scope, _workspace), do: []

  @doc "Returns one scoped workspace import."
  def get(%Scope{} = scope, import_id) when is_integer(import_id) and import_id > 0 do
    with %WorkspaceSnapshotImport{} = import <- Repo.get(WorkspaceSnapshotImport, import_id),
         {:ok, _workspace, _membership} <-
           Workspaces.authorize(scope, import.workspace_id, :access_workspace_settings) do
      {:ok, Repo.preload(import, :project)}
    else
      _not_visible -> {:error, :not_found}
    end
  end

  def get(_scope, _import_id), do: {:error, :not_found}

  @doc "Subscribes to committed lifecycle changes for one workspace."
  def subscribe(workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, workspace_topic(workspace_id))
  end

  def subscribe(_workspace_id), do: {:error, :invalid_workspace}

  @doc false
  def prepare_workspace_hard_delete(%Workspace{id: workspace_id}) when is_integer(workspace_id) do
    if Billing.workspace_lock_held?(workspace_id) do
      active_import? =
        WorkspaceSnapshotImport
        |> where([import], import.workspace_id == ^workspace_id and import.status in ^@active_statuses)
        |> order_by([import], asc: import.id)
        |> lock("FOR UPDATE")
        |> Repo.exists?()

      if active_import?, do: {:error, :workspace_snapshot_import_in_progress}, else: :ok
    else
      {:error, :workspace_snapshot_import_cleanup_lock_required}
    end
  end

  def prepare_workspace_hard_delete(_workspace), do: {:error, :invalid_workspace_snapshot_import_cleanup_scope}

  @doc false
  def perform(import_id, opts \\ [])

  def perform(import_id, opts) when is_integer(import_id) and import_id > 0 and is_list(opts) do
    case Repo.get(WorkspaceSnapshotImport, import_id) do
      %WorkspaceSnapshotImport{} = import ->
        lock_opts =
          case Keyword.fetch(opts, :lock_acquisition_timeout) do
            {:ok, timeout} -> [acquisition_timeout: timeout]
            :error -> []
          end

        import.idempotency_key
        |> request_lock_name()
        |> StorageKeyLock.with_session_lock(fn -> perform_locked(import_id, opts) end, lock_opts)
        |> normalize_session_lock_result()

      nil ->
        {:discard, :workspace_snapshot_import_not_found}
    end
  end

  def perform(_import_id, _opts), do: {:discard, :invalid_workspace_snapshot_import_job}

  @doc false
  def reconcile_abandoned_deliveries(opts \\ [])

  def reconcile_abandoned_deliveries(opts) when is_list(opts) do
    limit = opts |> Keyword.get(:limit, 50) |> min(50) |> max(1)

    candidates =
      WorkspaceSnapshotImport
      |> join(:left, [import], job in Oban.Job, on: job.id == import.oban_job_id)
      |> where(
        [import, job],
        import.status in ^@active_statuses and
          (is_nil(job.id) or job.state in ^@terminal_delivery_job_states)
      )
      |> order_by([import, _job], asc: import.id)
      |> limit(^limit)
      |> select([import, _job], %{
        import_id: import.id,
        workspace_id: import.workspace_id,
        idempotency_key: import.idempotency_key
      })
      |> Repo.all()

    Enum.reduce(
      candidates,
      %{candidate_count: length(candidates), terminalized_count: 0, changed_count: 0, failure_count: 0},
      &reconcile_abandoned_delivery/2
    )
  end

  def reconcile_abandoned_deliveries(_opts),
    do: %{candidate_count: 0, terminalized_count: 0, changed_count: 0, failure_count: 1}

  defp admit_after_semantic_dedupe(context) do
    case get_semantic_active(context.scope.user.id, context.workspace.id, context.preflight) do
      %WorkspaceSnapshotImport{} = candidate ->
        with {:ok, archive_checksum} <-
               hash_uploaded_file(context.uploaded_path, context.preflight.archive_size_bytes) do
          resolve_semantic_candidate(context, candidate, archive_checksum)
        end

      nil ->
        with :ok <- early_capacity_check(context.workspace, context.preflight.logical_asset_bytes),
             {:ok, archive_checksum} <-
               hash_uploaded_file(context.uploaded_path, context.preflight.archive_size_bytes) do
          admit_new_archive(context, archive_checksum)
        end
    end
  end

  defp resolve_semantic_candidate(
         _context,
         %WorkspaceSnapshotImport{archive_checksum: archive_checksum} = candidate,
         archive_checksum
       ) do
    {:ok, Repo.preload(candidate, :project)}
  end

  defp resolve_semantic_candidate(context, _candidate, archive_checksum), do: admit_new_archive(context, archive_checksum)

  defp admit_new_archive(context, archive_checksum) do
    idempotency_key = idempotency_key(context.scope.user.id, context.workspace.id, archive_checksum)
    context = Map.merge(context, %{archive_checksum: archive_checksum, idempotency_key: idempotency_key})

    StorageKeyLock.with_session_lock(request_lock_name(idempotency_key), fn ->
      admit_and_stage(context)
    end)
  end

  defp admit_and_stage(context) do
    with {:ok, {import, admission}} <- admit_operation(context) do
      stage_admission(admission, import, context)
    end
  end

  defp stage_admission(:existing, import, _context), do: {:ok, import}

  defp stage_admission(:created, import, context) do
    case upload_archive(context.uploaded_path, import, context.storage) do
      :ok ->
        publish(import)
        {:ok, import}

      {:error, reason} ->
        terminalize_admission_failure(import, reason)
    end
  end

  defp admit_operation(context) do
    context.workspace.id
    |> Billing.transact_with_workspace_lock(fn locked_workspace ->
      with {:ok, _membership} <- authorize_locked_import_member(context.scope, locked_workspace) do
        admit_locked_operation(context, locked_workspace)
      end
    end)
    |> normalize_capacity_transaction_result()
  end

  defp admit_locked_operation(context, locked_workspace) do
    case active_by_idempotency(locked_workspace.id, context.idempotency_key) do
      %WorkspaceSnapshotImport{} = import ->
        {:ok, {Repo.preload(import, :project), :existing}}

      nil ->
        insert_locked_operation(context, locked_workspace)
    end
  end

  defp insert_locked_operation(context, locked_workspace) do
    with :ok <- normalize_project_capacity(Billing.can_create_project?(locked_workspace)),
         :ok <-
           normalize_storage_capacity(
             Billing.can_upload_asset?(
               locked_workspace,
               context.preflight.logical_asset_bytes
             )
           ) do
      insert_operation(
        context.scope.user.id,
        locked_workspace.id,
        context.original_filename,
        context.project_name,
        context.preflight,
        context.archive_checksum,
        context.idempotency_key
      )
    end
  end

  defp insert_operation(
         user_id,
         workspace_id,
         original_filename,
         project_name,
         preflight,
         archive_checksum,
         idempotency_key
       ) do
    plan = admission_plan(workspace_id, idempotency_key, preflight.manifest)

    attrs = %{
      workspace_id: workspace_id,
      user_id: user_id,
      idempotency_key: idempotency_key,
      original_filename: original_filename,
      project_name: project_name,
      archive_storage_key: plan.archive_key,
      archive_size_bytes: preflight.archive_size_bytes,
      archive_checksum: archive_checksum,
      manifest_checksum: preflight.manifest_checksum,
      project_checksum: preflight.project_checksum,
      reserved_bytes: preflight.logical_asset_bytes,
      staging_storage_keys: plan.staging_keys,
      progress_total_bytes: progress_total_bytes(preflight),
      max_attempts: ImportProjectSnapshotWorker.max_attempts()
    }

    with {:ok, import} <-
           %WorkspaceSnapshotImport{}
           |> WorkspaceSnapshotImport.request_changeset(attrs)
           |> Repo.insert(),
         {:ok, job} <-
           %{"import_id" => import.id}
           |> ImportProjectSnapshotWorker.new()
           |> Oban.insert(),
         {:ok, import} <-
           import
           |> WorkspaceSnapshotImport.bind_job_changeset(job.id)
           |> Repo.update() do
      {:ok, {Repo.preload(import, :project), :created}}
    end
  end

  defp active_by_idempotency(workspace_id, idempotency_key) do
    WorkspaceSnapshotImport
    |> where(
      [import],
      import.workspace_id == ^workspace_id and import.idempotency_key == ^idempotency_key and
        import.status in ^@active_statuses
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp get_semantic_active(user_id, workspace_id, preflight) do
    WorkspaceSnapshotImport
    |> where(
      [import],
      import.user_id == ^user_id and import.workspace_id == ^workspace_id and
        import.manifest_checksum == ^preflight.manifest_checksum and
        import.project_checksum == ^preflight.project_checksum and
        import.archive_size_bytes == ^preflight.archive_size_bytes and import.status in ^@active_statuses
    )
    |> order_by([import], desc: import.id)
    |> limit(1)
    |> Repo.one()
  end

  defp early_capacity_check(workspace, requested_bytes) do
    workspace.id
    |> Billing.transact_with_workspace_lock(&validate_early_capacity(&1, requested_bytes))
    |> normalize_early_capacity_result()
  end

  defp validate_early_capacity(locked_workspace, requested_bytes) do
    with :ok <- normalize_project_capacity(Billing.can_create_project?(locked_workspace)),
         :ok <- normalize_storage_capacity(Billing.can_upload_asset?(locked_workspace, requested_bytes)) do
      {:ok, :admitted}
    end
  end

  defp normalize_early_capacity_result({:ok, :admitted}), do: :ok

  defp normalize_early_capacity_result({:error, {:limit_reached, details}}), do: {:error, :limit_reached, details}

  defp normalize_early_capacity_result({:error, _reason} = error), do: error

  defp upload_archive(path, import, storage) do
    upload_archive(
      path,
      import.archive_storage_key,
      import.archive_size_bytes,
      import.archive_checksum,
      storage
    )
  end

  defp upload_archive(path, archive_storage_key, archive_size_bytes, _archive_checksum, storage) do
    chunks = path |> File.stream!(@file_chunk_size, []) |> Stream.map(&{:ok, &1})

    with {:ok, _url} <- storage.upload_stream(archive_storage_key, chunks, @archive_content_type),
         {:ok, %{size: ^archive_size_bytes}} <- storage.stat(archive_storage_key) do
      :ok
    else
      {:ok, %{size: _other_size}} -> {:error, :snapshot_archive_upload_size_mismatch}
      {:error, _reason} = error -> error
    end
  rescue
    error -> {:error, {:archive_upload_exception, error.__struct__}}
  catch
    kind, reason -> {:error, {:archive_upload_failure, kind, safe_reason(reason)}}
  end

  defp admission_plan(workspace_id, _idempotency_key, manifest) do
    token = Ecto.UUID.generate()
    archive_key = archive_key(workspace_id, token)
    blob_keys = planned_blob_keys(workspace_id, token, manifest)

    %{
      archive_key: archive_key,
      staging_keys: [archive_key | Map.values(blob_keys)] |> Enum.uniq() |> Enum.sort()
    }
  end

  defp terminalize_admission_failure(import, reason) do
    case fail_terminal(import.id, failure_code(reason), import.attempt, import.max_attempts) do
      {:ok, _failed} ->
        {:error, :snapshot_archive_stage_failed}

      {:error, terminal_reason} ->
        Logger.error(
          "Snapshot import admission failure could not terminalize import_id=#{import.id} error=#{safe_error(terminal_reason)}"
        )

        {:error, :snapshot_import_unavailable}
    end
  end

  defp perform_locked(import_id, opts) do
    attempt = Keyword.get(opts, :attempt, 1)
    max_attempts = Keyword.get(opts, :max_attempts, ImportProjectSnapshotWorker.max_attempts())
    job_id = Keyword.get(opts, :job_id)

    case claim(import_id, job_id, attempt, max_attempts) do
      {:ok, import} ->
        case import.status do
          status when status in ["completed", "failed"] ->
            {:ok, import}

          "running" ->
            run_import(import, opts)
        end

      {:discard, _reason} = discard ->
        discard

      {:error, reason} ->
        handle_execution_error(import_id, {:claim, reason}, attempt, max_attempts)
    end
  end

  defp claim(import_id, job_id, attempt, max_attempts) do
    fn ->
      import =
        WorkspaceSnapshotImport
        |> where([import], import.id == ^import_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      case import do
        nil ->
          {:error, {:discard, :workspace_snapshot_import_not_found}}

        %WorkspaceSnapshotImport{status: status} = terminal when status in ["completed", "failed"] ->
          {:ok, Repo.preload(terminal, :project)}

        %WorkspaceSnapshotImport{oban_job_id: stored_job_id}
        when not is_integer(job_id) or stored_job_id != job_id ->
          {:error, {:discard, :workspace_snapshot_import_job_mismatch}}

        %WorkspaceSnapshotImport{} = active ->
          active
          |> WorkspaceSnapshotImport.running_changeset(attempt, max_attempts)
          |> Repo.update()
      end
    end
    |> Repo.transact()
    |> case do
      {:ok, result} ->
        if match?(%WorkspaceSnapshotImport{}, result), do: publish(result)
        {:ok, result}

      {:error, reason} ->
        normalize_claim_error(reason)
    end
  end

  defp run_import(import, opts) do
    reader = Keyword.get(opts, :archive_reader, ProjectSnapshotArchiveReader)
    storage = Keyword.get(opts, :storage, Storage)
    progress_key = {__MODULE__, :progress, import.id}
    Process.put(progress_key, %{current: 0, persisted: 0})

    result =
      with {:ok, plan} <-
             tag_error(
               verify_archive(
                 reader,
                 %{
                   archive_storage_key: import.archive_storage_key,
                   archive_size_bytes: import.archive_size_bytes,
                   archive_checksum: import.archive_checksum
                 },
                 fn entry, chunks ->
                   consume_entry(import, entry, chunks, storage, progress_key)
                 end
               ),
               :archive_verification
             ),
           :ok <- validate_verified_plan(import, plan),
           {:ok, import, asset_plan} <- prepare_materialization(import, plan, opts) do
        stage_and_materialize(import, plan, asset_plan, opts)
      end

    Process.delete(progress_key)

    case result do
      {:ok, _completed} = success -> success
      {:error, reason} -> handle_execution_error(import.id, reason, import.attempt, import.max_attempts)
    end
  rescue
    error ->
      Process.delete({__MODULE__, :progress, import.id})
      handle_execution_error(import.id, {:exception, error}, import.attempt, import.max_attempts)
  catch
    kind, reason ->
      Process.delete({__MODULE__, :progress, import.id})
      handle_execution_error(import.id, {kind, safe_reason(reason)}, import.attempt, import.max_attempts)
  end

  defp verify_archive(reader, archive_identity, consume_entry) do
    reader.verify_archive(archive_identity, consume_entry: consume_entry)
  rescue
    error in [Req.TransportError, Req.HTTPError] -> {:error, error}
  end

  defp consume_entry(import, entry, chunks, storage, progress_key) do
    result =
      if entry.path in ["manifest.json", "project.json"] do
        drain_chunks(chunks)
      else
        key = staging_blob_key(import, entry.sha256, entry.content_type)

        if key in import.staging_storage_keys do
          ensure_staged_blob(storage, key, entry, chunks)
        else
          {:error, :unplanned_snapshot_import_object}
        end
      end

    with :ok <- result do
      update_progress(import, entry.size_bytes, progress_key)
    end
  end

  defp ensure_staged_blob(storage, key, entry, chunks) do
    case verify_staged_object(storage, key, entry.size_bytes, entry.sha256) do
      :ok ->
        drain_chunks(chunks)

      {:error, reason} when reason in [:enoent, :staged_object_mismatch] ->
        with {:ok, _url} <- storage.upload_stream(key, chunks, entry.content_type) do
          verify_staged_object(storage, key, entry.size_bytes, entry.sha256)
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp verify_staged_object(storage, key, expected_size, expected_checksum) do
    with {:ok, %{size: ^expected_size}} <- storage.stat(key),
         {:ok, chunks} <- storage.stream(key, 0, expected_size),
         {:ok, ^expected_checksum} <- StorageHash.sha256_chunks(chunks) do
      :ok
    else
      {:ok, %{size: _other}} -> {:error, :staged_object_mismatch}
      {:ok, _other_checksum} -> {:error, :staged_object_mismatch}
      {:error, :enoent} -> {:error, :enoent}
      {:error, reason} -> {:error, {:staged_object_verification_failed, reason}}
      _unexpected -> {:error, :staged_object_mismatch}
    end
  end

  defp drain_chunks(chunks) do
    Enum.reduce_while(chunks, :ok, fn
      {:ok, chunk}, :ok when is_binary(chunk) -> {:cont, :ok}
      {:error, reason}, :ok -> {:halt, {:error, reason}}
      _unexpected, :ok -> {:halt, {:error, :unexpected_snapshot_import_stream_chunk}}
    end)
  end

  defp update_progress(import, increment, progress_key) do
    state = Process.get(progress_key, %{current: 0, persisted: 0})
    current = state.current + increment
    state = %{state | current: current}

    if current - state.persisted >= @progress_flush_bytes or current >= import.progress_total_bytes do
      case persist_progress(import.id, current) do
        {:ok, updated} ->
          Process.put(progress_key, %{current: current, persisted: current})
          publish(updated)
          :ok

        {:error, _reason} = error ->
          error
      end
    else
      Process.put(progress_key, state)
      :ok
    end
  end

  defp persist_progress(import_id, progress_bytes) do
    case Repo.get(WorkspaceSnapshotImport, import_id) do
      %WorkspaceSnapshotImport{status: "running"} = import ->
        import
        |> WorkspaceSnapshotImport.progress_changeset(progress_bytes)
        |> Repo.update()

      _not_running ->
        {:error, :workspace_snapshot_import_context_changed}
    end
  end

  defp validate_verified_plan(import, plan) do
    project_descriptor =
      Enum.find(plan.manifest["objects"], &(&1["kind"] == "project"))

    with true <- plan.archive_key == import.archive_storage_key,
         true <- plan.archive_size_bytes == import.archive_size_bytes,
         true <- plan.archive_checksum == import.archive_checksum,
         true <- sha256(plan.manifest_json) == import.manifest_checksum,
         true <- is_map(project_descriptor) and project_descriptor["sha256"] == import.project_checksum,
         true <- plan.logical_asset_bytes == import.reserved_bytes,
         true <- planned_keys_from_plan(import, plan) == Enum.sort(import.staging_storage_keys),
         :ok <- ProjectRecovery.validate_snapshot_import(plan.project) do
      :ok
    else
      false -> {:error, :snapshot_import_identity_mismatch}
      {:error, _reason} = error -> error
    end
  end

  defp prepare_materialization(import, archive_plan, opts) do
    asset_materializer = Keyword.get(opts, :asset_materializer, ProjectSnapshotAssetMaterializer)

    result =
      Billing.transact_with_workspace_lock(import.workspace_id, fn _locked_workspace ->
        locked_import =
          WorkspaceSnapshotImport
          |> where([candidate], candidate.id == ^import.id and candidate.status == "running")
          |> lock("FOR UPDATE")
          |> Repo.one()

        with %WorkspaceSnapshotImport{} = locked_import <- locked_import,
             {:ok, reserved_project_id} <- reserved_project_id(locked_import),
             {:ok, asset_plan} <-
               build_asset_plan(asset_materializer, locked_import, archive_plan, reserved_project_id),
             {:ok, planned} <-
               persist_materialization_plan(
                 asset_materializer,
                 locked_import,
                 reserved_project_id,
                 asset_plan
               ) do
          {:ok, {planned, asset_plan}}
        else
          nil -> {:error, :workspace_snapshot_import_context_changed}
          {:error, _reason} = error -> error
        end
      end)

    case result do
      {:ok, {import, asset_plan}} ->
        publish(import)
        {:ok, import, asset_plan}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reserved_project_id(%WorkspaceSnapshotImport{reserved_project_id: project_id})
       when is_integer(project_id) and project_id > 0, do: {:ok, project_id}

  defp reserved_project_id(%WorkspaceSnapshotImport{reserved_project_id: nil}) do
    case Repo.query!("SELECT nextval(pg_get_serial_sequence('projects', 'id'))") do
      %Postgrex.Result{rows: [[project_id]]} when is_integer(project_id) and project_id > 0 ->
        {:ok, project_id}

      _unexpected ->
        {:error, :workspace_snapshot_import_project_identity_unavailable}
    end
  end

  defp reserved_project_id(_import), do: {:error, :invalid_workspace_snapshot_import_project_identity}

  defp build_asset_plan(asset_materializer, import, archive_plan, reserved_project_id) do
    asset_materializer.prepare(
      reserved_project_id,
      "workspace-snapshot-import:#{import.id}",
      archive_plan.manifest,
      archive_plan.project,
      staging_prefix(import),
      asset_staging_keys(import, archive_plan.manifest)
    )
  end

  defp persist_materialization_plan(asset_materializer, import, reserved_project_id, asset_plan) do
    storage_keys = asset_materializer.planned_storage_keys(asset_plan)

    with :ok <- validate_persisted_materialization_identity(import, reserved_project_id, storage_keys) do
      import
      |> WorkspaceSnapshotImport.materialization_plan_changeset(reserved_project_id, storage_keys)
      |> Ecto.Changeset.put_change(:progress_bytes, import.progress_total_bytes)
      |> Repo.update()
    end
  end

  defp validate_persisted_materialization_identity(
         %WorkspaceSnapshotImport{reserved_project_id: nil, materialization_storage_keys: []},
         _project_id,
         _storage_keys
       ), do: :ok

  defp validate_persisted_materialization_identity(import, project_id, storage_keys) do
    if import.reserved_project_id == project_id and Enum.sort(import.materialization_storage_keys) == storage_keys,
      do: :ok,
      else: {:error, :workspace_snapshot_import_materialization_plan_changed}
  end

  defp stage_and_materialize(import, archive_plan, asset_plan, opts) do
    tracker = StorageCompensation.new()
    asset_materializer = Keyword.get(opts, :asset_materializer, ProjectSnapshotAssetMaterializer)

    case stage_destination_objects(asset_materializer, asset_plan, tracker) do
      :ok -> materialize(import, archive_plan, asset_plan, tracker, opts)
      {:error, reason} -> cleanup_materialization_rollback(tracker, {:asset_provider_staging, reason})
    end
  end

  defp stage_destination_objects(asset_materializer, asset_plan, tracker) do
    asset_materializer.stage_destination_objects(asset_plan, tracker)
  rescue
    error in [Req.TransportError, Req.HTTPError] -> {:error, error}
  end

  defp materialize(import, plan, asset_plan, tracker, opts) do
    materialize_fun = Keyword.get(opts, :materialize_fun, &ProjectRecovery.materialize_snapshot_import/4)
    asset_materializer = Keyword.get(opts, :asset_materializer, ProjectSnapshotAssetMaterializer)

    catalog_fun = fn project, _snapshot_data, user_id, scoped_opts ->
      tracker = Keyword.fetch!(scoped_opts, :asset_copy_tracker)

      with {:ok, adopted} <- asset_materializer.adopt_locked(asset_plan, project, user_id, tracker),
           :ok <- asset_materializer.verify_adopted_locked(asset_plan, adopted.logical_id_map) do
        {:ok, adopted.source_id_map}
      end
    end

    result =
      Billing.transact_with_workspace_lock(import.workspace_id, fn locked_workspace ->
        with %WorkspaceSnapshotImport{} = locked_import <- lock_running_import(import.id),
             %User{} = requester <- Repo.get(User, locked_import.user_id),
             {:ok, _membership} <-
               authorize_locked_import_member(Scope.for_user(requester), locked_workspace),
             :ok <- normalize_project_capacity(Billing.can_create_project?(locked_workspace)),
             {:ok, unreserved} <- clear_reservation(locked_import),
             {:ok, %Project{} = project} <-
               materialize_fun.(locked_workspace.id, plan.project, requester.id,
                 asset_copy_tracker: tracker,
                 snapshot_import_asset_catalog_fun: catalog_fun,
                 snapshot_import_project_id: locked_import.reserved_project_id
               ),
             {:ok, completed} <-
               unreserved
               |> WorkspaceSnapshotImport.completed_changeset(project)
               |> Repo.update(),
             {:ok, _cleanup_request} <-
               StorageCompensation.persist_planned_cleanup_request(locked_import.staging_storage_keys),
             {:ok, notification_outcome} <-
               deliver_result(completed, project, requester, "success"),
             :ok <- StorageCompensation.prepare_unretained_cleanup(tracker) do
          {:ok, {completed, notification_outcome}}
        else
          nil -> {:error, :workspace_snapshot_import_context_changed}
          {:error, _reason} = error -> error
        end
      end)

    case result do
      {:ok, {completed, notification_outcome}} ->
        StorageCompensation.discard(tracker)
        Notifications.publish_committed(notification_outcome)
        completed = Repo.preload(completed, :project, force: true)
        publish(completed)
        {:ok, completed}

      {:error, reason} ->
        cleanup_materialization_rollback(tracker, reason)
    end
  end

  defp lock_running_import(import_id) do
    WorkspaceSnapshotImport
    |> where([import], import.id == ^import_id and import.status == "running" and import.stage == "materializing")
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  # The workspace row is always locked first by StorageAccounting. Locking the
  # membership next makes authorization atomic with admission/publication and
  # serializes concurrent role changes or membership removal until commit.
  defp authorize_locked_import_member(%Scope{user: %User{id: user_id}}, %Workspace{id: workspace_id}) do
    membership =
      WorkspaceMembership
      |> where(
        [membership],
        membership.workspace_id == ^workspace_id and membership.user_id == ^user_id
      )
      |> lock("FOR UPDATE")
      |> Repo.one()

    case membership do
      %WorkspaceMembership{role: role} = membership ->
        if WorkspaceMembership.can?(role, :access_workspace_settings) and
             WorkspaceMembership.can?(role, :create_project),
           do: {:ok, membership},
           else: {:error, :unauthorized}

      nil ->
        {:error, :unauthorized}
    end
  end

  defp clear_reservation(import) do
    import
    |> Ecto.Changeset.change(reserved_bytes: 0)
    |> Repo.update()
  end

  defp handle_execution_error(import_id, reason, attempt, max_attempts) do
    if not retryable_failure?(reason) or attempt >= max_attempts do
      case fail_terminal(import_id, failure_code(reason), attempt, max_attempts) do
        {:ok, failed} ->
          {:ok, failed}

        {:error, terminal_reason} ->
          Logger.error(
            "Snapshot import could not persist terminal state import_id=#{import_id} " <>
              "error=#{safe_error(terminal_reason)}"
          )

          {:snooze, @lock_snooze_seconds}
      end
    else
      retry(import_id, reason, attempt, max_attempts)
    end
  end

  defp reconcile_abandoned_delivery(candidate, counts) do
    case reconcile_abandoned_delivery(candidate) do
      {:ok, :terminalized} -> %{counts | terminalized_count: counts.terminalized_count + 1}
      {:ok, :changed} -> %{counts | changed_count: counts.changed_count + 1}
      {:error, _reason} -> %{counts | failure_count: counts.failure_count + 1}
    end
  end

  defp reconcile_abandoned_delivery(%{import_id: import_id, workspace_id: workspace_id, idempotency_key: idempotency_key}) do
    idempotency_key
    |> request_lock_name()
    |> StorageKeyLock.with_session_lock(
      fn -> reconcile_abandoned_delivery_locked(import_id, workspace_id) end,
      acquisition_timeout: 0
    )
  end

  defp reconcile_abandoned_delivery_locked(import_id, workspace_id) do
    workspace_id
    |> Billing.transact_with_workspace_lock(fn _workspace ->
      import_id
      |> lock_reconciliation_import()
      |> reconcile_locked_import()
    end)
    |> finalize_reconciliation()
  end

  defp lock_reconciliation_import(import_id) do
    WorkspaceSnapshotImport
    |> where([candidate], candidate.id == ^import_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp reconcile_locked_import(nil), do: {:ok, :changed}

  defp reconcile_locked_import(%WorkspaceSnapshotImport{status: status}) when status not in @active_statuses,
    do: {:ok, :changed}

  defp reconcile_locked_import(%WorkspaceSnapshotImport{} = import) do
    if abandoned_delivery_job?(get_delivery_job(import.oban_job_id)),
      do: terminalize_abandoned_import(import),
      else: {:ok, :changed}
  end

  defp terminalize_abandoned_import(import) do
    case terminalize_import_locked(
           import,
           "snapshot_import_delivery_abandoned",
           import.attempt,
           import.max_attempts
         ) do
      {:ok, {failed, notification_outcome}} ->
        {:ok, {:terminalized, failed, notification_outcome}}

      {:error, _reason} = error ->
        error
    end
  end

  defp finalize_reconciliation({:ok, {:terminalized, failed, notification_outcome}}) do
    Notifications.publish_committed(notification_outcome)
    publish(failed)
    {:ok, :terminalized}
  end

  defp finalize_reconciliation({:ok, :changed}), do: {:ok, :changed}
  defp finalize_reconciliation({:error, _reason} = error), do: error

  defp abandoned_delivery_job?(nil), do: true
  defp abandoned_delivery_job?(%Oban.Job{state: state}), do: state in @terminal_delivery_job_states

  defp get_delivery_job(job_id) when is_integer(job_id) and job_id > 0, do: Repo.get(Oban.Job, job_id)
  defp get_delivery_job(_job_id), do: nil

  defp retry(import_id, reason, attempt, max_attempts) do
    details = %{attempt: attempt, max_attempts: max_attempts}

    case Repo.get(WorkspaceSnapshotImport, import_id) do
      %WorkspaceSnapshotImport{status: status} = import when status in @active_statuses ->
        case import
             |> WorkspaceSnapshotImport.retrying_changeset(failure_code(reason), details)
             |> Repo.update() do
          {:ok, retrying} ->
            publish(retrying)
            {:retry, failure_code(reason)}

          {:error, changeset} ->
            {:retry, {:workspace_snapshot_import_retry_state_failed, changeset}}
        end

      %WorkspaceSnapshotImport{} = terminal ->
        {:ok, Repo.preload(terminal, :project)}

      nil ->
        {:discard, :workspace_snapshot_import_not_found}
    end
  end

  defp fail_terminal(import_id, code, attempt, max_attempts) do
    result =
      Repo.transact(fn ->
        import =
          WorkspaceSnapshotImport
          |> where([import], import.id == ^import_id)
          |> lock("FOR UPDATE")
          |> Repo.one()

        case import do
          %WorkspaceSnapshotImport{status: status} = terminal when status in ["completed", "failed"] ->
            {:ok, {terminal, :suppressed}}

          %WorkspaceSnapshotImport{} = active ->
            terminalize_import_locked(active, code, attempt, max_attempts)

          nil ->
            {:error, :workspace_snapshot_import_not_found}
        end
      end)

    case result do
      {:ok, {failed, notification_outcome}} ->
        Notifications.publish_committed(notification_outcome)
        publish(failed)
        {:ok, failed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp terminalize_import_locked(active, code, attempt, max_attempts) do
    requester = Repo.get(User, active.user_id)

    with {:ok, failed} <-
           active
           |> WorkspaceSnapshotImport.failed_changeset(code, %{
             attempt: attempt,
             max_attempts: max_attempts
           })
           |> Repo.update(),
         {:ok, _cleanup_request} <-
           StorageCompensation.persist_planned_cleanup_request(cleanup_storage_keys(active)),
         {:ok, notification_outcome} <-
           deliver_result(failed, nil, requester, "failure") do
      {:ok, {failed, notification_outcome}}
    end
  end

  defp deliver_result(import, project, %User{} = requester, status) do
    Notifications.deliver_async_result(
      Scope.for_user(requester),
      project,
      %{
        entity_type: "workspace_snapshot_import",
        entity_id: import.id,
        entity_name: import.project_name,
        status: status,
        dedupe_key: "workspace_snapshot_import:#{import.id}:#{status}"
      }
    )
  end

  defp deliver_result(_import, _project, nil, _status), do: {:ok, :suppressed}

  defp cleanup_materialization_rollback(tracker, reason) do
    case StorageCompensation.cleanup_after_rollback(tracker) do
      :ok -> {:error, reason}
      {:error, cleanup_reason} -> {:error, {:asset_storage_cleanup_failed, cleanup_reason}}
    end
  end

  defp cleanup_storage_keys(import) do
    (import.staging_storage_keys ++ import.materialization_storage_keys)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp planned_blob_keys(workspace_id, token, manifest) do
    manifest["objects"]
    |> Enum.filter(&(&1["kind"] == "asset_blob"))
    |> Map.new(fn descriptor ->
      {descriptor["path"], blob_key(workspace_id, token, descriptor["sha256"], descriptor["content_type"])}
    end)
  end

  defp planned_keys_from_plan(import, plan) do
    token = import_token(import.archive_storage_key)

    [import.archive_storage_key | Map.values(planned_blob_keys(import.workspace_id, token, plan.manifest))]
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp asset_staging_keys(import, manifest),
    do: planned_blob_keys(import.workspace_id, import_token(import.archive_storage_key), manifest)

  defp staging_prefix(import), do: Path.dirname(import.archive_storage_key)

  defp staging_blob_key(import, checksum, content_type) do
    blob_key(import.workspace_id, import_token(import.archive_storage_key), checksum, content_type)
  end

  defp archive_key(workspace_id, token), do: "workspaces/#{workspace_id}/snapshot-imports/v1/#{token}/snapshot.zip"

  defp blob_key(workspace_id, token, checksum, content_type) do
    extension = BlobStore.ext_from_content_type(content_type)
    "workspaces/#{workspace_id}/snapshot-imports/v1/#{token}/blobs/#{checksum}.#{extension}"
  end

  defp import_token(archive_key) do
    archive_key |> String.split("/") |> Enum.at(4)
  end

  defp progress_total_bytes(preflight) do
    byte_size(preflight.manifest_json) + preflight.manifest["payload_size_bytes"]
  end

  defp validate_preflight(preflight) do
    with true <- is_map(preflight.manifest) and is_map(preflight.project),
         true <- is_binary(preflight.manifest_json),
         true <- is_integer(preflight.archive_size_bytes) and preflight.archive_size_bytes > 0,
         true <- is_integer(preflight.logical_asset_bytes) and preflight.logical_asset_bytes >= 0,
         true <- is_list(preflight.entry_order),
         true <- length(preflight.entry_order) <= 10_002,
         true <- valid_sha256?(preflight.manifest_checksum),
         true <- valid_sha256?(preflight.project_checksum),
         true <- is_integer(progress_total_bytes(preflight)) and progress_total_bytes(preflight) > 0 do
      :ok
    else
      false -> {:error, :invalid_snapshot_archive}
    end
  rescue
    _error -> {:error, :invalid_snapshot_archive}
  end

  defp project_name(project) do
    case get_in(project, ["project", "name"]) do
      name when is_binary(name) and name != "" ->
        if String.length(name) <= 255,
          do: {:ok, name},
          else: {:error, :invalid_snapshot_project_name}

      _invalid ->
        {:error, :invalid_snapshot_project_name}
    end
  end

  defp original_filename(attrs) do
    case Map.get(attrs, :original_filename, Map.get(attrs, "original_filename")) do
      filename when is_binary(filename) ->
        filename = filename |> Path.basename() |> String.trim()

        if filename != "" and String.valid?(filename) and String.length(filename) <= 255,
          do: {:ok, filename},
          else: {:error, :invalid_snapshot_filename}

      _invalid ->
        {:error, :invalid_snapshot_filename}
    end
  end

  defp hash_uploaded_file(path, expected_size) do
    with {:ok, %{type: :regular, size: ^expected_size}} <- File.stat(path),
         {:ok, checksum} <-
           path
           |> File.stream!(@file_chunk_size, [])
           |> Stream.map(&{:ok, &1})
           |> StorageHash.sha256_chunks(),
         {:ok, %{type: :regular, size: ^expected_size}} <- File.stat(path) do
      {:ok, checksum}
    else
      _invalid -> {:error, :invalid_snapshot_archive_file}
    end
  end

  defp idempotency_key(user_id, workspace_id, archive_checksum) do
    secret = Application.fetch_env!(:storyarn, :import_idempotency_secret)
    payload = :erlang.term_to_binary({"workspace_snapshot_import/v1", user_id, workspace_id, archive_checksum})

    hmac_idempotency_key(secret, payload)
  end

  defp semantic_key(user_id, workspace_id, preflight) do
    secret = Application.fetch_env!(:storyarn, :import_idempotency_secret)

    payload =
      :erlang.term_to_binary({
        "workspace_snapshot_import_semantic_lock/v1",
        user_id,
        workspace_id,
        preflight.manifest_checksum,
        preflight.project_checksum,
        preflight.archive_size_bytes
      })

    hmac_idempotency_key(secret, payload)
  end

  defp hmac_idempotency_key(secret, payload) do
    :hmac
    |> :crypto.mac(:sha256, secret, payload)
    |> Base.encode16(case: :lower)
  end

  defp normalize_project_capacity(:ok), do: :ok
  defp normalize_project_capacity({:error, :limit_reached, _details}), do: {:error, :project_limit_reached}
  defp normalize_project_capacity({:error, reason}), do: {:error, reason}

  defp normalize_storage_capacity(:ok), do: :ok

  defp normalize_storage_capacity({:error, :limit_reached, details}) do
    {:error,
     {:limit_reached,
      %{
        required_bytes: details.required,
        available_bytes: details.available,
        limit_bytes: details.limit
      }}}
  end

  defp normalize_storage_capacity({:error, reason}), do: {:error, reason}

  defp normalize_capacity_transaction_result({:error, {:limit_reached, details}}), do: {:error, :limit_reached, details}

  defp normalize_capacity_transaction_result(result), do: result

  defp normalize_claim_error({:discard, reason}), do: {:discard, reason}
  defp normalize_claim_error(reason), do: {:error, reason}

  defp normalize_session_lock_result({:error, :session_lock_timeout}), do: {:snooze, @lock_snooze_seconds}

  defp normalize_session_lock_result(result), do: result

  defp tag_error({:ok, value}, _phase), do: {:ok, value}
  defp tag_error({:error, reason}, phase), do: {:error, {phase, reason}}

  defp retryable_failure?({:archive_verification, reason}), do: ProjectSnapshotArchiveReader.retryable_error?(reason)

  defp retryable_failure?({:asset_provider_staging, reason}), do: retryable_provider_failure?(reason)

  defp retryable_failure?({:claim, reason}), do: retryable_database_failure?(reason)
  defp retryable_failure?({:exception, reason}), do: retryable_database_failure?(reason)
  defp retryable_failure?(reason), do: retryable_database_failure?(reason)

  defp retryable_provider_failure?(reason) when reason in [:session_lock_timeout, :storage_key_lock_timeout], do: true

  defp retryable_provider_failure?({:snapshot_blob_staging_failed, _path, reason}),
    do: retryable_provider_failure?(reason)

  defp retryable_provider_failure?({:snapshot_asset_staging_failed, _logical_id, reason}),
    do: retryable_provider_failure?(reason)

  defp retryable_provider_failure?({:destination_stat_failed, reason}), do: retryable_provider_failure?(reason)

  defp retryable_provider_failure?({:conditional_copy_cleanup_required, _created?, _cleanup_key, reason}),
    do: retryable_provider_failure?(reason)

  defp retryable_provider_failure?({:storage_write_cleanup_required, _cleanup_key, write_reason, cleanup_reason}),
    do: retryable_provider_failure?(write_reason) or retryable_provider_failure?(cleanup_reason)

  defp retryable_provider_failure?(reason), do: ProjectSnapshotArchiveReader.retryable_error?(reason)

  defp retryable_database_failure?(%DBConnection.ConnectionError{}), do: true

  defp retryable_database_failure?(%Postgrex.Error{postgres: %{code: code}})
       when code in [
              :serialization_failure,
              :deadlock_detected,
              :lock_not_available,
              :query_canceled,
              :connection_exception,
              :connection_failure,
              :cannot_connect_now,
              :admin_shutdown,
              :crash_shutdown,
              :too_many_connections
            ], do: true

  defp retryable_database_failure?(_reason), do: false

  defp failure_code({phase, reason}) when phase in [:archive_verification, :asset_provider_staging],
    do: failure_code(reason)

  defp failure_code(reason) when is_atom(reason), do: reason |> Atom.to_string() |> String.slice(0, 100)
  defp failure_code({reason, _details}) when is_atom(reason), do: failure_code(reason)
  defp failure_code(_reason), do: "snapshot_import_failed"

  defp request_lock_name(idempotency_key), do: "workspace-snapshot-import:#{idempotency_key}"
  defp semantic_lock_name(semantic_key), do: "workspace-snapshot-import-admission:#{semantic_key}"
  defp workspace_topic(workspace_id), do: "workspace_snapshot_imports:workspace:#{workspace_id}"

  defp publish(%WorkspaceSnapshotImport{} = import) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      workspace_topic(import.workspace_id),
      {:workspace_snapshot_import_updated, Repo.preload(import, :project)}
    )
  end

  defp valid_sha256?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp sha256(binary), do: :sha256 |> :crypto.hash(binary) |> Base.encode16(case: :lower)

  defp safe_reason(reason) when is_atom(reason), do: reason
  defp safe_reason({reason, _details}) when is_atom(reason), do: reason
  defp safe_reason(_reason), do: :unexpected_error

  defp safe_error(error) when is_exception(error), do: error.__struct__
  defp safe_error({kind, reason}) when is_atom(kind), do: {kind, safe_reason(reason)}
  defp safe_error(reason), do: safe_reason(reason)
end
