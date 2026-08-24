defmodule Storyarn.Versioning.WorkspaceSnapshotImports do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Assets.StorageHash
  alias Storyarn.Billing
  alias Storyarn.Notifications
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Persistence.UserRecord, as: User
  alias Storyarn.Projects.Persistence.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.WorkspaceAccess
  alias Storyarn.Repo
  alias Storyarn.Versioning.ProjectRecovery
  alias Storyarn.Versioning.ProjectSnapshotArchiveReader
  alias Storyarn.Versioning.ProjectSnapshotAssetMaterializer
  alias Storyarn.Versioning.WorkspaceSnapshotImport
  alias Storyarn.Workers.ImportProjectSnapshotWorker

  require Logger

  @active_statuses ~w(uploading queued running retrying)
  @terminal_delivery_job_states ~w(cancelled completed discarded)
  @archive_content_type "application/zip"
  @file_chunk_size 1_048_576
  @progress_flush_bytes 1_048_576
  @history_limit 50
  @duplicate_delivery_snooze_seconds 30
  @upload_ttl_seconds 3_600
  @max_live_upload_grants 3

  @doc "Validates and stages a local upload without holding a database checkout during file I/O."
  def request(scope, workspace, uploaded_path, attrs, opts \\ [])

  def request(%{user: _} = scope, %{id: _} = workspace, uploaded_path, attrs, opts)
      when is_binary(uploaded_path) and is_map(attrs) and is_list(opts) do
    reader = Keyword.get(opts, :archive_reader, ProjectSnapshotArchiveReader)
    storage = Keyword.get(opts, :storage, Storage)

    with {:ok, workspace, _membership} <-
           WorkspaceAccess.authorize(scope, workspace.id, :access_workspace_settings),
         {:ok, _workspace, _membership} <- WorkspaceAccess.authorize(scope, workspace.id, :create_project),
         {:ok, original_filename} <- original_filename(attrs),
         {:ok, preflight} <- reader.preflight_file(uploaded_path),
         :ok <- validate_preflight(preflight),
         {:ok, upload} <-
           prepare_upload(scope, workspace, %{
             original_filename: original_filename,
             archive_size_bytes: preflight.archive_size_bytes
           }) do
      complete_local_upload(scope, workspace, upload, uploaded_path, upload.project_name, preflight, storage)
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

  def request(%{user: _}, %{id: _}, _uploaded_path, _attrs, _opts), do: {:error, :unauthorized}
  def request(_scope, _workspace, _uploaded_path, _attrs, _opts), do: {:error, :invalid_snapshot_import_request}

  @doc "Creates the durable owner of one direct-upload key before bytes leave the browser."
  def prepare_upload(%{user: %{id: _}} = scope, %{id: _} = workspace, attrs) when is_map(attrs),
    do: prepare_upload(scope, workspace, attrs, false)

  def prepare_upload(_scope, _workspace, _attrs), do: {:error, :invalid_snapshot_import_request}

  defp prepare_upload(%{user: %{id: _}} = scope, %{id: _} = workspace, attrs, enforce_grant_limit?)
       when is_map(attrs) and is_boolean(enforce_grant_limit?) do
    with {:ok, original_filename} <- original_filename(attrs),
         {:ok, archive_size_bytes} <- archive_size_bytes(attrs),
         {:ok, workspace, _membership} <-
           WorkspaceAccess.authorize(scope, workspace.id, :access_workspace_settings),
         {:ok, _workspace, _membership} <- WorkspaceAccess.authorize(scope, workspace.id, :create_project) do
      insert_upload_owner(scope, workspace, original_filename, archive_size_bytes, enforce_grant_limit?)
    end
  end

  defp prepare_upload(_scope, _workspace, _attrs, _enforce_grant_limit?), do: {:error, :invalid_snapshot_import_request}

  @doc "Creates an owned upload and returns a short-lived direct PUT."
  def prepare_external_upload(scope, workspace, attrs, opts \\ [])

  def prepare_external_upload(%{user: _} = scope, %{id: _} = workspace, attrs, opts)
      when is_map(attrs) and is_list(opts) do
    storage = Keyword.get(opts, :storage, Storage)

    with {:ok, upload} <- prepare_upload(scope, workspace, attrs, true) do
      presign_upload(scope, workspace, upload, storage)
    end
  end

  def prepare_external_upload(_scope, _workspace, _attrs, _opts), do: {:error, :invalid_snapshot_import_request}

  defp presign_upload(scope, workspace, upload, storage) do
    case storage.presigned_upload_url(upload.archive_storage_key, @archive_content_type,
           expires_in: @upload_ttl_seconds,
           content_length: upload.archive_size_bytes
         ) do
      {:ok, url, metadata} when is_binary(url) and is_map(metadata) ->
        {:ok,
         %{
           import_id: upload.id,
           url: url,
           headers: Map.get(metadata, :headers, %{"content-type" => @archive_content_type})
         }}

      {:error, _reason} ->
        discard_upload_result(scope, workspace, upload.id, {:error, :snapshot_import_unavailable})
    end
  rescue
    _error -> discard_upload_result(scope, workspace, upload.id, {:error, :snapshot_import_unavailable})
  catch
    _kind, _reason -> discard_upload_result(scope, workspace, upload.id, {:error, :snapshot_import_unavailable})
  end

  @doc "Preflights an owned private object, reserves capacity, and enqueues its asynchronous import."
  def request_stored(scope, workspace, import_id, opts \\ [])

  def request_stored(%{user: _} = scope, %{id: _} = workspace, import_id, opts)
      when is_integer(import_id) and import_id > 0 and is_list(opts) do
    reader = Keyword.get(opts, :archive_reader, ProjectSnapshotArchiveReader)

    with {:ok, upload} <- owned_upload(scope, workspace, import_id),
         {:ok, preflight} <-
           reader.preflight_archive(%{
             archive_storage_key: upload.archive_storage_key,
             archive_size_bytes: upload.archive_size_bytes
           }),
         :ok <- validate_preflight(preflight),
         {:ok, accepted} <- admit_preflight(scope, workspace, upload, upload.project_name, preflight) do
      publish(accepted)
      {:ok, accepted}
    else
      {:error, _reason} = error -> discard_upload_result(scope, workspace, import_id, error)
      {:error, _reason, _details} = error -> discard_upload_result(scope, workspace, import_id, error)
    end
  end

  def request_stored(_scope, _workspace, _import_id, _opts), do: {:error, :invalid_snapshot_import_request}

  @doc false
  def upload_progress(%{user: _} = scope, %{id: _} = workspace, import_id, percent)
      when is_integer(import_id) and import_id > 0 and is_integer(percent) and percent in 0..100 do
    with {:ok, _workspace, _membership} <-
           WorkspaceAccess.authorize(scope, workspace.id, :access_workspace_settings),
         {1, _rows} <- heartbeat_upload(scope.user.id, workspace.id, import_id, percent),
         %WorkspaceSnapshotImport{} = updated <- Repo.get(WorkspaceSnapshotImport, import_id) do
      publish(updated)
      {:ok, updated}
    else
      _stale_or_unauthorized -> {:error, :workspace_snapshot_upload_not_found}
    end
  end

  def upload_progress(_scope, _workspace, _import_id, _percent), do: {:error, :workspace_snapshot_upload_not_found}

  @doc false
  def cancel_upload(%{user: _} = scope, %{id: _} = workspace, import_id), do: discard_upload(scope, workspace, import_id)

  @doc "Lists recent imports visible in one workspace settings surface."
  def list(%{user: _} = scope, %{id: workspace_id}) do
    case WorkspaceAccess.authorize(scope, workspace_id, :access_workspace_settings) do
      {:ok, _workspace, _membership} ->
        active =
          WorkspaceSnapshotImport
          |> where([import], import.workspace_id == ^workspace_id and import.status in ^@active_statuses)
          |> preload(:project)
          |> Repo.all()

        terminal =
          WorkspaceSnapshotImport
          |> where([import], import.workspace_id == ^workspace_id and import.status in ["completed", "failed"])
          |> order_by([import], desc: import.inserted_at, desc: import.id)
          |> limit(@history_limit)
          |> preload(:project)
          |> Repo.all()

        Enum.sort_by(active ++ terminal, &{&1.inserted_at, &1.id}, :desc)

      {:error, _reason} ->
        []
    end
  end

  def list(_scope, _workspace), do: []

  @doc "Subscribes to committed lifecycle changes for one workspace."
  def subscribe(workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, workspace_topic(workspace_id))
  end

  def subscribe(_workspace_id), do: {:error, :invalid_workspace}

  @doc false
  def prepare_workspace_hard_delete(%{id: workspace_id}) when is_integer(workspace_id) do
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
    perform_attempt(import_id, opts)
  end

  def perform(_import_id, _opts), do: {:discard, :invalid_workspace_snapshot_import_job}

  @doc false
  def reconcile_abandoned_deliveries(opts \\ [])

  def reconcile_abandoned_deliveries(opts) when is_list(opts) do
    limit = opts |> Keyword.get(:limit, 50) |> min(50) |> max(1)
    upload_ttl = Keyword.get(opts, :upload_ttl_seconds, @upload_ttl_seconds)
    stale_before = DateTime.add(TimeHelpers.now(), -upload_ttl, :second)

    candidates =
      WorkspaceSnapshotImport
      |> join(:left, [import], job in Oban.Job, on: job.id == import.oban_job_id)
      |> where(
        [import, job],
        (import.status == "uploading" and import.updated_at < ^stale_before) or
          (import.status in ["queued", "running", "retrying"] and
             (is_nil(job.id) or job.state in ^@terminal_delivery_job_states))
      )
      |> order_by([import, _job], asc: import.id)
      |> limit(^limit)
      |> select([import, _job], %{
        import_id: import.id,
        workspace_id: import.workspace_id
      })
      |> Repo.all()
      |> Enum.map(&Map.put(&1, :stale_before, stale_before))

    Enum.reduce(
      candidates,
      %{candidate_count: length(candidates), terminalized_count: 0, changed_count: 0, failure_count: 0},
      &reconcile_abandoned_delivery/2
    )
  end

  def reconcile_abandoned_deliveries(_opts),
    do: %{candidate_count: 0, terminalized_count: 0, changed_count: 0, failure_count: 1}

  defp insert_upload_owner(scope, workspace, original_filename, archive_size_bytes, enforce_grant_limit?) do
    Billing.transact_with_workspace_lock(workspace.id, fn locked_workspace ->
      with {:ok, _membership} <- authorize_locked_import_member(scope, locked_workspace),
           :ok <- normalize_project_capacity(Billing.can_create_project?(locked_workspace)),
           :ok <- maybe_enforce_upload_grant_limit(locked_workspace.id, enforce_grant_limit?) do
        token = Ecto.UUID.generate()
        archive_storage_key = archive_key(locked_workspace.id, token)

        attrs = %{
          workspace_id: locked_workspace.id,
          user_id: scope.user.id,
          original_filename: original_filename,
          project_name: Path.rootname(original_filename),
          archive_storage_key: archive_storage_key,
          archive_size_bytes: archive_size_bytes,
          staging_storage_keys: [archive_storage_key],
          progress_total_bytes: archive_size_bytes,
          max_attempts: ImportProjectSnapshotWorker.max_attempts()
        }

        %WorkspaceSnapshotImport{}
        |> WorkspaceSnapshotImport.upload_changeset(attrs)
        |> Repo.insert()
        |> normalize_active_import_insert()
      end
    end)
  end

  defp maybe_enforce_upload_grant_limit(workspace_id, true), do: enforce_upload_grant_limit(workspace_id)
  defp maybe_enforce_upload_grant_limit(_workspace_id, false), do: :ok

  defp enforce_upload_grant_limit(workspace_id) do
    cutoff =
      DateTime.add(
        TimeHelpers.now(),
        -@upload_ttl_seconds - Storage.multipart_cleanup_quiescence_seconds(),
        :second
      )

    count =
      StorageCleanupRequest
      |> where(
        [request],
        request.owner_kind == "storage_compensation" and request.inserted_at >= ^cutoff and
          request.multipart_quiescence_not_before > fragment("clock_timestamp()")
      )
      |> where(
        [request],
        fragment(
          "EXISTS (SELECT 1 FROM unnest(?) AS keys(storage_key) WHERE storage_key LIKE ?)",
          request.storage_keys,
          ^"workspace-snapshot-imports/v1/#{workspace_id}/%"
        )
      )
      |> Repo.aggregate(:count)

    if count < @max_live_upload_grants, do: :ok, else: {:error, :workspace_snapshot_upload_rate_limited}
  end

  defp complete_local_upload(scope, workspace, upload, path, project_name, preflight, storage) do
    case upload_archive(path, upload, storage) do
      :ok ->
        case admit_preflight(scope, workspace, upload, project_name, preflight) do
          {:ok, accepted} ->
            publish(accepted)
            {:ok, accepted}

          {:error, _reason} = error ->
            discard_upload_result(scope, workspace, upload.id, error)

          {:error, _reason, _details} = error ->
            discard_upload_result(scope, workspace, upload.id, error)
        end

      {:error, _reason} ->
        discard_upload_result(scope, workspace, upload.id, {:error, :snapshot_archive_stage_failed})
    end
  end

  defp heartbeat_upload(user_id, workspace_id, import_id, percent) do
    query =
      from(import in WorkspaceSnapshotImport,
        where:
          import.id == ^import_id and import.workspace_id == ^workspace_id and import.user_id == ^user_id and
            import.status == "uploading",
        update: [
          set: [
            progress_bytes:
              fragment("GREATEST(?, (? * ?) / 100)", import.progress_bytes, import.archive_size_bytes, ^percent),
            updated_at: ^TimeHelpers.now()
          ]
        ]
      )

    Repo.update_all(query, [])
  end

  defp owned_upload(%{user: %{id: user_id}} = scope, %{id: workspace_id}, import_id) do
    with {:ok, _workspace, _membership} <-
           WorkspaceAccess.authorize(scope, workspace_id, :access_workspace_settings),
         %WorkspaceSnapshotImport{} = upload <-
           WorkspaceSnapshotImport
           |> where(
             [import],
             import.id == ^import_id and import.workspace_id == ^workspace_id and import.user_id == ^user_id and
               import.status == "uploading"
           )
           |> Repo.one() do
      {:ok, upload}
    else
      _not_owned -> {:error, :workspace_snapshot_upload_not_found}
    end
  end

  defp admit_preflight(scope, workspace, upload, project_name, preflight) do
    workspace.id
    |> Billing.transact_with_workspace_lock(fn locked_workspace ->
      locked_upload =
        WorkspaceSnapshotImport
        |> where(
          [import],
          import.id == ^upload.id and import.workspace_id == ^locked_workspace.id and
            import.user_id == ^scope.user.id and import.status == "uploading"
        )
        |> lock("FOR UPDATE")
        |> Repo.one()

      with %WorkspaceSnapshotImport{} = locked_upload <- locked_upload,
           {:ok, _membership} <- authorize_locked_import_member(scope, locked_workspace),
           :ok <- normalize_project_capacity(Billing.can_publish_reserved_project?(locked_workspace)),
           :ok <-
             normalize_storage_capacity(Billing.can_upload_asset?(locked_workspace, preflight.logical_asset_bytes)),
           {:ok, queued} <- persist_admitted_upload(locked_upload, project_name, preflight),
           {:ok, job} <- %{"import_id" => queued.id} |> ImportProjectSnapshotWorker.new() |> Oban.insert(),
           {:ok, bound} <- queued |> WorkspaceSnapshotImport.bind_job_changeset(job.id) |> Repo.update() do
        {:ok, Repo.preload(bound, :project)}
      else
        nil -> {:error, :workspace_snapshot_upload_not_found}
        {:error, _reason} = error -> error
      end
    end)
    |> normalize_capacity_transaction_result()
  end

  defp persist_admitted_upload(upload, project_name, preflight) do
    upload
    |> WorkspaceSnapshotImport.admit_changeset(%{
      project_name: project_name,
      manifest_checksum: preflight.manifest_checksum,
      project_checksum: preflight.project_checksum,
      reserved_bytes: preflight.logical_asset_bytes,
      staging_storage_keys: planned_keys_from_preflight(upload, preflight.manifest),
      progress_total_bytes: progress_total_bytes(preflight)
    })
    |> Repo.update()
  end

  defp discard_upload_result(scope, workspace, import_id, original_result) do
    case discard_upload(scope, workspace, import_id) do
      {:ok, _discarded} -> original_result
      {:error, :workspace_snapshot_upload_not_found} -> original_result
      {:error, _reason} -> {:error, :snapshot_import_unavailable}
    end
  end

  defp discard_upload(%{user: _} = scope, %{id: _} = workspace, import_id) do
    result =
      Billing.transact_with_workspace_lock(workspace.id, fn locked_workspace ->
        with {:ok, _membership} <- authorize_locked_import_member(scope, locked_workspace),
             %WorkspaceSnapshotImport{} = upload <-
               WorkspaceSnapshotImport
               |> where(
                 [import],
                 import.id == ^import_id and import.workspace_id == ^locked_workspace.id and import.status == "uploading"
               )
               |> lock("FOR UPDATE")
               |> Repo.one(),
             {:ok, _cleanup_request} <-
               persist_import_cleanup(upload, upload.staging_storage_keys),
             {:ok, deleted} <- Repo.delete(upload) do
          {:ok, deleted}
        else
          nil -> {:error, :workspace_snapshot_upload_not_found}
          {:error, _reason} = error -> error
        end
      end)

    case result do
      {:ok, discarded} ->
        delete_provisional_objects(discarded.staging_storage_keys)
        publish(discarded)
        {:ok, discarded}

      {:error, _reason} = error ->
        error
    end
  end

  defp planned_keys_from_preflight(import, manifest) do
    [
      import.archive_storage_key
      | Map.values(planned_blob_keys(import.workspace_id, import_token(import.archive_storage_key), manifest))
    ]
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_active_import_insert({:error, %Ecto.Changeset{} = changeset}) do
    if Keyword.has_key?(changeset.errors, :workspace_id),
      do: {:error, :workspace_snapshot_import_in_progress},
      else: {:error, changeset}
  end

  defp normalize_active_import_insert(result), do: result

  defp upload_archive(path, import, storage) do
    upload_archive(path, import.archive_storage_key, import.archive_size_bytes, storage)
  end

  defp upload_archive(path, archive_storage_key, archive_size_bytes, storage) do
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

  defp perform_attempt(import_id, opts) do
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

      {:snooze, _seconds} = snooze ->
        snooze

      {:error, reason} ->
        if retryable_database_failure?(reason) and attempt < max_attempts,
          do: {:retry, failure_code(reason)},
          else: {:discard, :workspace_snapshot_import_claim_failed}
    end
  end

  defp claim(import_id, job_id, attempt, max_attempts) do
    fn ->
      WorkspaceSnapshotImport
      |> where([import], import.id == ^import_id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> transition_claim(job_id, attempt, max_attempts)
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

  defp transition_claim(nil, _job_id, _attempt, _max_attempts),
    do: {:error, {:discard, :workspace_snapshot_import_not_found}}

  defp transition_claim(%WorkspaceSnapshotImport{status: status} = terminal, _job_id, _attempt, _max_attempts)
       when status in ["completed", "failed"], do: {:ok, Repo.preload(terminal, :project)}

  defp transition_claim(%WorkspaceSnapshotImport{oban_job_id: stored_job_id}, job_id, _attempt, _max_attempts)
       when not is_integer(job_id) or stored_job_id != job_id,
       do: {:error, {:discard, :workspace_snapshot_import_job_mismatch}}

  defp transition_claim(
         %WorkspaceSnapshotImport{status: status, attempt: stored_attempt} = active,
         _job_id,
         attempt,
         max_attempts
       )
       when status in ["queued", "retrying", "running"] and is_integer(attempt) and attempt > stored_attempt and
              is_integer(max_attempts) and attempt <= max_attempts do
    active
    |> WorkspaceSnapshotImport.running_changeset(attempt, max_attempts)
    |> Repo.update()
  end

  defp transition_claim(%WorkspaceSnapshotImport{}, _job_id, _attempt, _max_attempts),
    do: {:error, {:snooze, @duplicate_delivery_snooze_seconds}}

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
           {:ok, verified_name} <- project_name(plan.project),
           {:ok, import} <- pin_verified_identity(import, plan.archive_checksum, verified_name),
           :ok <- validate_verified_plan(import, plan),
           {:ok, import, asset_plan} <- prepare_materialization(import, plan, opts) do
        stage_and_materialize(import, plan, asset_plan, opts)
      end

    Process.delete(progress_key)

    case result do
      {:ok, _completed} = success -> success
      {:error, reason} -> handle_execution_error(import, reason)
    end
  rescue
    error ->
      Process.delete({__MODULE__, :progress, import.id})
      handle_execution_error(import, {:exception, error})
  catch
    kind, reason ->
      Process.delete({__MODULE__, :progress, import.id})
      handle_execution_error(import, {kind, safe_reason(reason)})
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
      case persist_progress(import, current) do
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

  defp persist_progress(import, progress_bytes) do
    Repo.transact(fn ->
      case lock_owned_running(import) do
        %WorkspaceSnapshotImport{} = owned ->
          owned |> WorkspaceSnapshotImport.progress_changeset(progress_bytes) |> Repo.update()

        nil ->
          {:error, :workspace_snapshot_import_context_changed}
      end
    end)
  end

  defp pin_verified_identity(import, archive_checksum, project_name) do
    result =
      Repo.transact(fn ->
        case lock_owned_running(import) do
          %WorkspaceSnapshotImport{archive_checksum: nil} = owned ->
            owned
            |> WorkspaceSnapshotImport.verified_changeset(archive_checksum)
            |> Ecto.Changeset.put_change(:project_name, project_name)
            |> Repo.update()

          %WorkspaceSnapshotImport{archive_checksum: ^archive_checksum} = owned ->
            owned |> Ecto.Changeset.change(project_name: project_name) |> Repo.update()

          %WorkspaceSnapshotImport{} ->
            {:error, :snapshot_import_identity_mismatch}

          nil ->
            {:error, :workspace_snapshot_import_context_changed}
        end
      end)

    case result do
      {:ok, updated} ->
        publish(updated)
        {:ok, updated}

      {:error, _reason} = error ->
        error
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
          |> where(
            [candidate],
            candidate.id == ^import.id and candidate.oban_job_id == ^import.oban_job_id and
              candidate.attempt == ^import.attempt and candidate.status == "running"
          )
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
        with %WorkspaceSnapshotImport{} = locked_import <- lock_running_import(import),
             %User{} = requester <- Repo.get(User, locked_import.user_id),
             {:ok, _membership} <-
               authorize_locked_import_member(%{user: requester}, locked_workspace),
             :ok <- normalize_project_capacity(Billing.can_publish_reserved_project?(locked_workspace)),
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
               persist_import_cleanup(locked_import, locked_import.staging_storage_keys),
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
        delete_provisional_objects(completed.staging_storage_keys)
        Notifications.publish_committed(notification_outcome)
        completed = Repo.preload(completed, :project, force: true)
        publish(completed)
        {:ok, completed}

      {:error, reason} ->
        cleanup_materialization_rollback(tracker, reason)
    end
  end

  defp lock_running_import(import) do
    WorkspaceSnapshotImport
    |> where(
      [candidate],
      candidate.id == ^import.id and candidate.oban_job_id == ^import.oban_job_id and
        candidate.attempt == ^import.attempt and candidate.status == "running" and candidate.stage == "materializing"
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp lock_owned_running(import) do
    WorkspaceSnapshotImport
    |> where(
      [candidate],
      candidate.id == ^import.id and candidate.oban_job_id == ^import.oban_job_id and
        candidate.attempt == ^import.attempt and candidate.status == "running"
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  # The workspace row is always locked first by StorageAccounting. Locking the
  # membership next makes authorization atomic with admission/publication and
  # serializes concurrent role changes or membership removal until commit.
  defp authorize_locked_import_member(%{user: %{id: user_id}}, %{id: workspace_id}) do
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
        if WorkspaceAccess.can?(role, :access_workspace_settings) and
             WorkspaceAccess.can?(role, :create_project),
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

  defp handle_execution_error(import, reason) do
    if not retryable_failure?(reason) or import.attempt >= import.max_attempts do
      case fail_terminal(import, failure_code(reason)) do
        {:ok, failed} ->
          {:ok, failed}

        {:discard, _reason} = discard ->
          discard

        {:error, terminal_reason} ->
          Logger.error(
            "Snapshot import could not persist terminal state import_id=#{import.id} " <>
              "error=#{safe_error(terminal_reason)}"
          )

          {:retry, :workspace_snapshot_import_terminal_state_failed}
      end
    else
      retry(import, reason)
    end
  end

  defp reconcile_abandoned_delivery(candidate, counts) do
    case reconcile_abandoned_delivery(candidate) do
      {:ok, :terminalized} -> %{counts | terminalized_count: counts.terminalized_count + 1}
      {:ok, :changed} -> %{counts | changed_count: counts.changed_count + 1}
      {:error, _reason} -> %{counts | failure_count: counts.failure_count + 1}
    end
  end

  defp reconcile_abandoned_delivery(%{import_id: import_id, workspace_id: workspace_id, stale_before: stale_before}) do
    workspace_id
    |> Billing.transact_with_workspace_lock(fn _workspace ->
      import_id
      |> lock_reconciliation_import()
      |> reconcile_locked_import(stale_before)
    end)
    |> finalize_reconciliation()
  end

  defp lock_reconciliation_import(import_id) do
    WorkspaceSnapshotImport
    |> where([candidate], candidate.id == ^import_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp reconcile_locked_import(nil, _stale_before), do: {:ok, :changed}

  defp reconcile_locked_import(%WorkspaceSnapshotImport{status: status}, _stale_before)
       when status not in @active_statuses, do: {:ok, :changed}

  defp reconcile_locked_import(
         %WorkspaceSnapshotImport{status: "uploading", updated_at: updated_at} = import,
         stale_before
       ) do
    if DateTime.before?(updated_at, stale_before) do
      with {:ok, _cleanup_request} <-
             persist_import_cleanup(import, import.staging_storage_keys),
           {:ok, deleted} <- Repo.delete(import) do
        {:ok, {:discarded_upload, deleted}}
      end
    else
      {:ok, :changed}
    end
  end

  defp reconcile_locked_import(%WorkspaceSnapshotImport{} = import, _stale_before) do
    if abandoned_delivery_job?(get_delivery_job(import.oban_job_id)),
      do: terminalize_abandoned_import(import),
      else: {:ok, :changed}
  end

  defp terminalize_abandoned_import(import) do
    case terminalize_import_locked(
           import,
           "snapshot_import_delivery_abandoned"
         ) do
      {:ok, {failed, notification_outcome}} ->
        {:ok, {:terminalized, failed, notification_outcome}}

      {:error, _reason} = error ->
        error
    end
  end

  defp finalize_reconciliation({:ok, {:terminalized, failed, notification_outcome}}) do
    delete_provisional_objects(cleanup_storage_keys(failed))
    Notifications.publish_committed(notification_outcome)
    publish(failed)
    {:ok, :terminalized}
  end

  defp finalize_reconciliation({:ok, {:discarded_upload, upload}}) do
    delete_provisional_objects(upload.staging_storage_keys)
    publish(upload)
    {:ok, :changed}
  end

  defp finalize_reconciliation({:ok, :changed}), do: {:ok, :changed}
  defp finalize_reconciliation({:error, _reason} = error), do: error

  defp abandoned_delivery_job?(nil), do: true
  defp abandoned_delivery_job?(%Oban.Job{state: state}), do: state in @terminal_delivery_job_states

  defp get_delivery_job(job_id) when is_integer(job_id) and job_id > 0, do: Repo.get(Oban.Job, job_id)
  defp get_delivery_job(_job_id), do: nil

  defp retry(import, reason) do
    details = %{attempt: import.attempt, max_attempts: import.max_attempts}

    result =
      Repo.transact(fn ->
        case lock_owned_running(import) do
          %WorkspaceSnapshotImport{} = owned ->
            owned
            |> WorkspaceSnapshotImport.retrying_changeset(failure_code(reason), details)
            |> Repo.update()

          nil ->
            {:error, :workspace_snapshot_import_context_changed}
        end
      end)

    case result do
      {:ok, retrying} ->
        publish(retrying)
        {:retry, failure_code(reason)}

      {:error, :workspace_snapshot_import_context_changed} ->
        {:discard, :workspace_snapshot_import_stale_delivery}

      {:error, changeset} ->
        {:retry, {:workspace_snapshot_import_retry_state_failed, changeset}}
    end
  end

  defp fail_terminal(import, code) do
    result =
      Billing.transact_with_workspace_lock(import.workspace_id, fn _locked_workspace ->
        case lock_owned_running(import) do
          %WorkspaceSnapshotImport{} = active -> terminalize_import_locked(active, code)
          nil -> {:error, :workspace_snapshot_import_context_changed}
        end
      end)

    case result do
      {:ok, {failed, notification_outcome}} ->
        delete_provisional_objects(cleanup_storage_keys(failed))
        Notifications.publish_committed(notification_outcome)
        publish(failed)
        {:ok, failed}

      {:error, reason} ->
        if reason == :workspace_snapshot_import_context_changed,
          do: {:discard, :workspace_snapshot_import_stale_delivery},
          else: {:error, reason}
    end
  end

  defp terminalize_import_locked(active, code) do
    requester = Repo.get(User, active.user_id)

    with {:ok, failed} <-
           active
           |> WorkspaceSnapshotImport.failed_changeset(code, %{
             attempt: active.attempt,
             max_attempts: active.max_attempts
           })
           |> Repo.update(),
         {:ok, _cleanup_request} <-
           persist_import_cleanup(active, cleanup_storage_keys(active)),
         {:ok, notification_outcome} <-
           deliver_result(failed, nil, requester, "failure") do
      {:ok, {failed, notification_outcome}}
    end
  end

  defp deliver_result(import, project, %User{} = requester, status) do
    Notifications.deliver_async_result(
      %{user: requester},
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
    case StorageCompensation.cleanup(tracker) do
      :ok -> {:error, reason}
      {:error, cleanup_reason} -> {:error, {:asset_storage_cleanup_failed, cleanup_reason}}
    end
  end

  defp cleanup_storage_keys(import) do
    (import.staging_storage_keys ++ import.materialization_storage_keys)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # A presigned PUT remains reusable until expiry. Keep the durable cleanup
  # receipt asleep beyond that window so cancel, rejection, failure and success
  # cannot consume it before a cooperative browser finishes or aborts the PUT.
  defp persist_import_cleanup(import, storage_keys) do
    not_before =
      DateTime.add(
        import.inserted_at,
        @upload_ttl_seconds + Storage.multipart_cleanup_quiescence_seconds(),
        :second
      )

    StorageCompensation.persist_planned_cleanup_request(storage_keys, not_before: not_before)
  end

  defp delete_provisional_objects(storage_keys), do: Enum.each(storage_keys, &delete_provisional_object/1)

  defp delete_provisional_object(storage_key) do
    Storage.delete(storage_key)
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
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

  defp archive_key(workspace_id, token), do: "workspace-snapshot-imports/v1/#{workspace_id}/#{token}/snapshot.zip"

  defp blob_key(workspace_id, token, checksum, content_type) do
    extension = BlobStore.ext_from_content_type(content_type)
    "workspace-snapshot-imports/v1/#{workspace_id}/#{token}/blobs/#{checksum}.#{extension}"
  end

  defp import_token(archive_key) do
    archive_key |> String.split("/") |> Enum.at(3)
  end

  defp progress_total_bytes(preflight) do
    byte_size(preflight.manifest_json) + preflight.manifest["payload_size_bytes"]
  end

  defp validate_preflight(preflight) do
    with true <- is_map(preflight.manifest),
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

  defp archive_size_bytes(attrs) do
    case Map.get(attrs, :archive_size_bytes, Map.get(attrs, "archive_size_bytes")) do
      size when is_integer(size) and size > 0 ->
        if size <= ProjectSnapshotArchiveReader.max_archive_size_bytes(),
          do: {:ok, size},
          else: {:error, :invalid_snapshot_archive_size}

      _invalid ->
        {:error, :invalid_snapshot_archive_size}
    end
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
  defp normalize_claim_error({:snooze, seconds}), do: {:snooze, seconds}
  defp normalize_claim_error(reason), do: {:error, reason}

  defp tag_error({:ok, value}, _phase), do: {:ok, value}
  defp tag_error({:error, reason}, phase), do: {:error, {phase, reason}}

  defp retryable_failure?({:archive_verification, reason}), do: ProjectSnapshotArchiveReader.retryable_error?(reason)

  defp retryable_failure?({:asset_provider_staging, reason}), do: retryable_provider_failure?(reason)

  defp retryable_failure?({:exception, reason}), do: retryable_database_failure?(reason)
  defp retryable_failure?(reason), do: retryable_database_failure?(reason)

  defp retryable_provider_failure?(:storage_key_lock_timeout), do: true

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
