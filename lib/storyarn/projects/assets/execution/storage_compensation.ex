defmodule Storyarn.Projects.Assets.StorageCompensation do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.MultipartCleanup
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageCleanupPersistenceError
  alias Storyarn.Projects.Assets.StorageCleanupRequest
  alias Storyarn.Projects.Assets.StorageHash
  alias Storyarn.Projects.Assets.StorageKeyLock
  alias Storyarn.Projects.Persistence.StorageReservationRecord, as: StorageReservation
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.Projects.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Projects.Versioning.ProjectSnapshot
  alias Storyarn.Projects.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Projects.Versioning.WorkspaceSnapshotImport
  alias Storyarn.Repo
  alias Storyarn.Workers.DeleteStorageObjectsWorker

  require Logger

  @enqueue_attempts 3
  @enqueue_retry_delay_ms 25
  @delete_attempts 3
  @delete_retry_delay_ms 25
  @persisted_cleanup_batch_size 100
  @force_delete_prefix "__storyarn_force_delete__:"
  @max_project_id 9_223_372_036_854_775_807
  @asset_uuid_pattern ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @asset_filename_pattern ~r/\A[a-z0-9_.-]{1,255}\z/
  @blob_key_pattern ~r|\Aprojects/[1-9]\d*/blobs/[0-9a-f]{64}\.([a-z0-9][a-z0-9-]{0,31})\z|
  @conditional_copy_suffix_pattern ~r/\A[A-Za-z0-9_-]{16}\z/
  @template_namespace_pattern ~r/\A[a-z0-9][a-z0-9_-]{0,127}\z/
  @template_filename_pattern ~r/\A[\w.-]{1,255}\z/u
  @snapshot_token_pattern ~r/\A[A-Za-z0-9_-]{16}\z/
  @storage_reservation_path_kinds ~w(snapshot-build restore-staging snapshot-export)
  @storage_reservation_record_kinds ~w(snapshot_build restore_staging snapshot_export)
  @storage_reservation_lease_pattern ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @storage_reservation_path_segment_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/
  @workspace_snapshot_import_key_pattern ~r'\Aworkspace-snapshot-imports/v1/[1-9]\d*/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/(?:snapshot\.zip|blobs/[0-9a-f]{64}\.[a-z0-9][a-z0-9-]{0,31})\z'
  @max_storage_reservation_relative_key_bytes 512
  @max_storage_reservation_path_segments 16

  @spec new() :: reference()
  def new do
    reference = make_ref()
    Process.put(key(reference), [])
    reference
  end

  @spec track(reference(), String.t()) :: :ok
  def track(reference, storage_key) when is_reference(reference) and is_binary(storage_key) do
    cleanup_target =
      Enum.find(tracked(reference), storage_key, fn target ->
        force_delete_target?(target) and cleanup_target_storage_key(target) == storage_key
      end)

    put_tracked(reference, cleanup_target)
    :ok
  end

  @doc """
  Tracks an object that is known to be invalid and therefore must not receive
  the conservative project-blob retention treatment during deferred cleanup.

  The force-delete intent is encoded in the durable cleanup payload. A live
  `Asset` row with the exact key still wins, preventing compensation from
  deleting storage already adopted by a committed database record.
  """
  @spec track_force_delete(reference(), String.t()) :: :ok
  def track_force_delete(reference, storage_key) when is_reference(reference) and is_binary(storage_key) do
    put_tracked(reference, force_delete_target(storage_key))
    Process.put(retained_key(reference), Enum.reject(retained(reference), &(&1 == storage_key)))
    :ok
  end

  @doc """
  Marks a tracked object as belonging to a database write that may be retained
  after the surrounding transaction commits.

  The object remains tracked so a later rollback still compensates it. After a
  successful commit, `cleanup_unretained/2` discards these retained objects and
  cleans only partial writes that never reached a database row.
  """
  @spec retain_after_commit(reference(), String.t()) :: :ok
  def retain_after_commit(reference, storage_key) when is_reference(reference) and is_binary(storage_key) do
    put_tracked(reference, storage_key)

    Process.put(
      retained_key(reference),
      [storage_key | Enum.reject(retained(reference), &(&1 == storage_key))]
    )

    :ok
  end

  @spec untrack(reference(), String.t()) :: :ok
  def untrack(reference, storage_key) when is_reference(reference) and is_binary(storage_key) do
    Process.put(
      key(reference),
      Enum.reject(tracked(reference), &(cleanup_target_storage_key(&1) == storage_key))
    )

    Process.put(retained_key(reference), Enum.reject(retained(reference), &(&1 == storage_key)))
    :ok
  end

  @doc false
  @spec pending_cleanup_targets(reference()) :: [String.t()]
  def pending_cleanup_targets(reference) when is_reference(reference) do
    reference
    |> tracked()
    |> normalize_cleanup_targets()
  end

  @spec cleanup(reference(), keyword()) :: :ok | {:error, term()}
  def cleanup(reference, opts \\ []) when is_reference(reference) do
    cleanup_targets = reference |> tracked() |> normalize_cleanup_targets()
    cleanup_storage_keys(reference, cleanup_targets, opts)
  end

  @doc """
  Compensates storage writes after the database transaction that owned them
  rolled back.

  Unlike `cleanup/2`, which avoids caller-side remote I/O and hands work to the
  cleanup queue, this function attempts deletion immediately. Any keys that
  cannot be deleted are handed to the durable queue or fallback outbox before
  the tracker is released.
  """
  @spec cleanup_after_rollback(reference(), keyword()) :: :ok | {:error, term()}
  def cleanup_after_rollback(reference, opts \\ []) when is_reference(reference) do
    cleanup_targets = reference |> tracked() |> normalize_cleanup_targets()
    cleanup_storage_keys_after_rollback(reference, cleanup_targets, opts)
  end

  @doc """
  Finalizes a successful surrounding transaction.

  Storage objects attached to committed rows are retained. Any other tracked
  objects represent failed or partial writes and are durably cleaned before the
  tracker is released.
  """
  @spec cleanup_unretained(reference(), keyword()) :: :ok | {:error, term()}
  def cleanup_unretained(reference, opts \\ []) when is_reference(reference) do
    cleanup_storage_keys(reference, unretained_cleanup_targets(reference), opts)
  end

  @doc """
  Persists cleanup ownership for partial storage writes before the surrounding
  database transaction commits.

  Unlike `cleanup_unretained/2`, this function deliberately keeps the tracker
  intact. The owner must call `discard/1` after a successful commit, or
  `cleanup/2` after rollback. This makes the cleanup handoff atomic with the
  database writes without losing rollback compensation if the commit fails.
  """
  @spec prepare_unretained_cleanup(reference(), keyword()) :: :ok | {:error, term()}
  def prepare_unretained_cleanup(reference, opts \\ []) when is_reference(reference) do
    enqueue_fun = Keyword.get(opts, :enqueue_fun, &enqueue_cleanup/1)
    persist_fun = Keyword.get(opts, :persist_fun, &persist_cleanup_request/1)

    case unretained_cleanup_targets(reference) do
      [] ->
        :ok

      cleanup_targets ->
        persist_cleanup_handoff(cleanup_targets, enqueue_fun, persist_fun)
    end
  end

  defp cleanup_storage_keys(reference, storage_keys, opts) do
    enqueue_fun = Keyword.get(opts, :enqueue_fun, &enqueue_cleanup/1)
    delete_fun = Keyword.get(opts, :delete_fun, &delete_storage_keys/1)
    persist_fun = Keyword.get(opts, :persist_fun, &persist_cleanup_request/1)

    case storage_keys do
      [] ->
        discard(reference)

      storage_keys ->
        persist_or_delete_cleanup(
          reference,
          storage_keys,
          enqueue_fun,
          delete_fun,
          persist_fun
        )
    end
  end

  defp cleanup_storage_keys_after_rollback(reference, storage_keys, opts) do
    enqueue_fun = Keyword.get(opts, :enqueue_fun, &enqueue_cleanup/1)
    delete_fun = rollback_delete_fun(opts)
    persist_fun = Keyword.get(opts, :persist_fun, &persist_cleanup_request/1)

    case storage_keys do
      [] ->
        discard(reference)

      storage_keys ->
        delete_or_persist_rollback_cleanup(
          reference,
          storage_keys,
          enqueue_fun,
          delete_fun,
          persist_fun
        )
    end
  end

  defp rollback_delete_fun(opts) do
    Keyword.get_lazy(opts, :delete_fun, fn ->
      restore_cleanup_owner = Keyword.get(opts, :restore_cleanup_owner)

      fn cleanup_targets ->
        delete_storage_keys(cleanup_targets, restore_cleanup_owner: restore_cleanup_owner)
      end
    end)
  end

  defp unretained_cleanup_targets(reference) do
    retained_keys = reference |> retained() |> MapSet.new()

    reference
    |> tracked()
    |> Enum.reject(&MapSet.member?(retained_keys, cleanup_target_storage_key(&1)))
    |> normalize_cleanup_targets()
  end

  defp persist_cleanup_handoff(cleanup_targets, enqueue_fun, persist_fun) do
    case call_enqueue(enqueue_fun, cleanup_targets) do
      :ok ->
        :ok

      {:error, enqueue_reason} ->
        case call_persist(persist_fun, cleanup_targets) do
          {:ok, _cleanup_request} ->
            :ok

          {:error, persistence_reason} ->
            Logger.error(
              "Could not prepare copied asset cleanup before commit " <>
                "enqueue_error=#{safe_error(enqueue_reason)} " <>
                "persistence_error=#{safe_error(persistence_reason)}"
            )

            {:error,
             {:storage_cleanup_handoff_not_persisted,
              %{
                cleanup_targets: cleanup_targets,
                enqueue_error: safe_error(enqueue_reason),
                persistence_error: safe_error(persistence_reason)
              }}}
        end
    end
  end

  @spec cleanup!(reference(), keyword()) :: :ok
  def cleanup!(reference, opts \\ []) when is_reference(reference) do
    case cleanup(reference, opts) do
      :ok -> :ok
      {:error, reason} -> raise StorageCleanupPersistenceError, reason: reason
    end
  end

  @spec cleanup_after_rollback!(reference(), keyword()) :: :ok
  def cleanup_after_rollback!(reference, opts \\ []) when is_reference(reference) do
    case cleanup_after_rollback(reference, opts) do
      :ok -> :ok
      {:error, reason} -> raise StorageCleanupPersistenceError, reason: reason
    end
  end

  @spec delete_storage_keys([String.t()]) :: :ok | {:error, [String.t()]}
  def delete_storage_keys(cleanup_targets) when is_list(cleanup_targets) do
    delete_storage_keys(cleanup_targets, [])
  end

  @doc false
  @spec delete_storage_keys([String.t()], keyword()) :: :ok | {:error, [String.t()]}
  def delete_storage_keys(cleanup_targets, opts) when is_list(cleanup_targets) and is_list(opts) do
    restore_cleanup_owner = normalize_restore_cleanup_owner(Keyword.get(opts, :restore_cleanup_owner))

    failed_targets =
      cleanup_targets
      |> normalize_cleanup_targets()
      |> Enum.filter(fn cleanup_target ->
        case safe_deferred_storage_delete(cleanup_target, restore_cleanup_owner) do
          :ok -> false
          {:error, _reason} -> true
        end
      end)

    if failed_targets == [], do: :ok, else: {:error, failed_targets}
  end

  @doc false
  @spec delete_storage_keys_with_evidence([String.t()]) ::
          {:ok, %{aborted_count: non_neg_integer()}} | {:error, [String.t()]}
  def delete_storage_keys_with_evidence(cleanup_targets) when is_list(cleanup_targets) do
    case delete_storage_keys(cleanup_targets) do
      :ok -> {:ok, %{aborted_count: 0}}
      {:error, failed_targets} -> {:error, failed_targets}
    end
  end

  @doc false
  @spec delete_cleanup_request_keys(pos_integer(), [String.t()], keyword()) ::
          :ok | {:deferred, pos_integer()} | {:error, [String.t()]}
  def delete_cleanup_request_keys(cleanup_request_id, cleanup_targets, opts \\ [])

  def delete_cleanup_request_keys(cleanup_request_id, cleanup_targets, opts)
      when is_integer(cleanup_request_id) and cleanup_request_id > 0 and is_list(cleanup_targets) and is_list(opts) do
    cleanup_targets = normalize_cleanup_targets(cleanup_targets)

    if multipart_cleanup_keys(cleanup_targets) == [] do
      delete_storage_keys(cleanup_targets, opts)
    else
      opts =
        opts
        |> Keyword.put_new(:authorize_fun, &authorize_multipart_cleanup_targets/1)
        |> Keyword.put_new(:object_policy_fun, &multipart_cleanup_object_policy/1)
        |> Keyword.put_new(:step_limit, 1)

      MultipartCleanup.process(cleanup_request_id, cleanup_targets, opts)
    end
  rescue
    error ->
      Logger.error("Durable multipart cleanup raised error=#{safe_error(error)}")
      {:error, cleanup_targets}
  catch
    kind, reason ->
      Logger.error("Durable multipart cleanup failed error=#{safe_error({kind, reason})}")
      {:error, cleanup_targets}
  end

  def delete_cleanup_request_keys(_cleanup_request_id, cleanup_targets, _opts) when is_list(cleanup_targets),
    do: {:error, cleanup_targets}

  def delete_cleanup_request_keys(_cleanup_request_id, _cleanup_targets, _opts), do: {:error, []}

  @doc false
  @spec reopen_confirmed_cleanup_request(pos_integer()) :: :ok | {:error, term()}
  def reopen_confirmed_cleanup_request(cleanup_request_id) do
    MultipartCleanup.reopen_confirmed(cleanup_request_id)
  end

  @doc false
  @spec resume_cleanup_request_for_replay(pos_integer()) :: :ok | {:error, term()}
  def resume_cleanup_request_for_replay(cleanup_request_id) do
    MultipartCleanup.resume_for_replay(cleanup_request_id)
  end

  defp multipart_cleanup_keys(cleanup_targets) do
    cleanup_targets
    |> Enum.map(&cleanup_target_storage_key/1)
    |> Enum.filter(&Storage.multipart_cleanup_key?/1)
    |> Enum.uniq()
  end

  defp database_clock_now do
    %Postgrex.Result{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    DateTime.truncate(now, :second)
  end

  defp seconds_until(not_before, now), do: max(DateTime.diff(not_before, now, :second), 1)

  @spec enqueue_cleanup([String.t()], keyword()) :: :ok | {:error, term()}
  def enqueue_cleanup(cleanup_targets, opts \\ []) when is_list(cleanup_targets) do
    cleanup_targets = normalize_cleanup_targets(cleanup_targets)
    insert_fun = Keyword.get(opts, :insert_fun)
    attempts = Keyword.get(opts, :attempts, @enqueue_attempts)
    retry_delay_ms = Keyword.get(opts, :retry_delay_ms, @enqueue_retry_delay_ms)

    case cleanup_targets do
      [] ->
        :ok

      cleanup_targets when is_function(insert_fun, 1) ->
        enqueue_with_retry(cleanup_targets, insert_fun, attempts, retry_delay_ms)

      cleanup_targets when is_nil(insert_fun) ->
        persist_then_enqueue_cleanup(cleanup_targets)

      _cleanup_targets ->
        {:error, :invalid_cleanup_enqueue_options}
    end
  end

  defp persist_then_enqueue_cleanup(cleanup_targets) do
    case persist_planned_cleanup_request(cleanup_targets) do
      {:ok, request} ->
        case insert_cleanup_request_job(request.id) do
          {:ok, _job} ->
            :ok

          {:error, reason} ->
            Logger.warning("Durable storage cleanup will rely on reconciliation queue_error=#{safe_error(reason)}")

            :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes one storage object, scheduling durable cleanup if the delete fails.

  A failed delete cannot be durably handed off from inside the caller's
  transaction because that job or fallback row would roll back with it. In that
  case this function returns an error; transactional callers must use
  `delete_tracked_or_enqueue/3` and finalize the tracker after the transaction.
  """
  @spec delete_or_enqueue(String.t(), keyword()) :: :ok | {:error, term()}
  def delete_or_enqueue(storage_key, opts \\ []) when is_binary(storage_key) do
    case delete_or_enqueue_with_status(storage_key, opts) do
      {:ok, _status} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp delete_or_enqueue_with_status(storage_key, opts) do
    if valid_storage_key?(storage_key),
      do: do_delete_or_enqueue_with_status(storage_key, opts),
      else: {:error, :invalid_storage_key}
  end

  defp do_delete_or_enqueue_with_status(storage_key, opts) do
    force_delete? = Keyword.get(opts, :force_delete, false)

    cleanup_target =
      if force_delete?,
        do: force_delete_target(storage_key),
        else: storage_key

    delete_fun =
      Keyword.get(opts, :delete_fun, fn storage_key ->
        delete_owned_storage_key(storage_key, force_delete?)
      end)

    transactional? = in_transaction?(opts)

    wrapper_owned_force_cleanup? =
      StorageKeyLock.wrapper_owned_transaction_lock_held?(storage_key)

    if force_delete? and transactional? and not wrapper_owned_force_cleanup? do
      # The current transaction can see a Project row that has not committed
      # yet. Keep the force target tracked until the owner knows whether that
      # row committed or rolled back, then let deferred cleanup decide whether
      # repaired bytes are still owned.
      {:error, :storage_cleanup_requires_post_transaction}
    else
      delete_attempts =
        opts |> Keyword.get(:delete_attempts, @delete_attempts) |> normalize_delete_attempts()

      delete_retry_delay_ms =
        opts |> Keyword.get(:delete_retry_delay_ms, @delete_retry_delay_ms) |> normalize_delete_retry_delay()

      case delete_with_retry(storage_key, delete_fun, delete_attempts, delete_retry_delay_ms) do
        :ok ->
          {:ok, :deleted}

        {:error, _reason} ->
          hand_off_failed_delete(cleanup_target, opts, transactional?)
      end
    end
  end

  defp hand_off_failed_delete(_cleanup_target, _opts, true) do
    {:error, :storage_cleanup_requires_post_transaction}
  end

  defp hand_off_failed_delete(cleanup_target, opts, false) do
    cleanup_opts =
      opts
      |> Keyword.drop([
        :delete_fun,
        :delete_attempts,
        :delete_retry_delay_ms,
        :force_delete,
        :in_transaction?
      ])
      |> Keyword.put(:delete_fun, fn storage_keys -> {:error, storage_keys} end)

    case cleanup_one(cleanup_target, cleanup_opts) do
      :ok -> {:ok, :handed_off}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Deletes a tracked storage object or hands it off to durable cleanup.

  The caller's tracker is released only after deletion or a durable cleanup
  handoff succeeds. When a transactional delete fails, the key stays tracked
  and this function returns an error so the owner can retry after rollback.
  """
  @spec delete_tracked_or_enqueue(reference(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete_tracked_or_enqueue(reference, storage_key, opts \\ [])
      when is_reference(reference) and is_binary(storage_key) do
    delete_tracked_or_enqueue_with_policy(reference, storage_key, opts)
  end

  @doc """
  Deletes a tracked, verified-invalid object or durably preserves that exact
  force-delete intent for post-transaction cleanup.
  """
  @spec delete_force_tracked_or_enqueue(reference(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def delete_force_tracked_or_enqueue(reference, storage_key, opts \\ [])
      when is_reference(reference) and is_binary(storage_key) do
    track_force_delete(reference, storage_key)
    delete_tracked_or_enqueue_with_policy(reference, storage_key, Keyword.put(opts, :force_delete, true))
  end

  defp delete_tracked_or_enqueue_with_policy(reference, storage_key, opts) do
    case delete_or_enqueue_with_status(storage_key, opts) do
      {:ok, :deleted} ->
        untrack(reference, storage_key)

      {:ok, :handed_off} ->
        untrack(reference, storage_key)

      {:error, _reason} = error ->
        error
    end
  end

  @doc "Deletes one storage object or raises when no durable cleanup path can be established."
  @spec delete_or_enqueue!(String.t(), keyword()) :: :ok
  def delete_or_enqueue!(storage_key, opts \\ []) when is_binary(storage_key) do
    case delete_or_enqueue(storage_key, opts) do
      :ok -> :ok
      {:error, reason} -> raise StorageCleanupPersistenceError, reason: reason
    end
  end

  @doc "Deletes every object or raises after collecting cleanup handoff failures."
  @spec delete_or_enqueue_all!([String.t()], keyword()) :: :ok
  def delete_or_enqueue_all!(storage_keys, opts \\ []) when is_list(storage_keys) do
    failures =
      Enum.reduce(storage_keys, [], fn storage_key, failures ->
        case delete_or_enqueue(storage_key, opts) do
          :ok -> failures
          {:error, reason} -> [{storage_key, reason} | failures]
        end
      end)

    case Enum.reverse(failures) do
      [] -> :ok
      failures -> raise StorageCleanupPersistenceError, reason: {:storage_cleanup_failures, failures}
    end
  end

  @spec retry_persisted_cleanup_requests(pos_integer(), keyword()) :: :ok | {:error, non_neg_integer()}
  def retry_persisted_cleanup_requests(limit \\ @persisted_cleanup_batch_size, opts \\ [])

  def retry_persisted_cleanup_requests(limit, opts) when is_integer(limit) and limit > 0 and is_list(opts) do
    cleanup_requests =
      StorageCleanupRequest
      |> where([request], request.owner_kind == "storage_compensation")
      |> where([request], is_nil(request.multipart_cleanup_phase) or request.multipart_cleanup_phase != "blocked")
      |> where(
        [request],
        is_nil(request.multipart_cleanup_next_attempt_at) or
          request.multipart_cleanup_next_attempt_at <= fragment("clock_timestamp()")
      )
      |> where(
        [request],
        is_nil(request.multipart_quiescence_not_before) or
          request.multipart_quiescence_not_before <= fragment("clock_timestamp()")
      )
      |> order_by([request], asc: request.inserted_at, asc: request.id)
      |> limit(^limit)
      |> Repo.all()

    results = Enum.map(cleanup_requests, &retry_persisted_cleanup_request(&1, opts))
    failed_count = Enum.count(results, &(&1 == :error))
    deferred_count = Enum.count(results, &(&1 == :deferred))

    :telemetry.execute(
      [:storyarn, :assets, :storage_compensation, :persisted_retry],
      %{count: length(cleanup_requests), failed_count: failed_count, deferred_count: deferred_count},
      %{}
    )

    if failed_count == 0, do: :ok, else: {:error, failed_count}
  end

  @doc false
  @spec enqueue_due_cleanup_request_jobs(pos_integer(), keyword()) ::
          :ok | {:error, non_neg_integer()}
  def enqueue_due_cleanup_request_jobs(limit \\ @persisted_cleanup_batch_size, opts \\ [])

  def enqueue_due_cleanup_request_jobs(limit, opts) when is_integer(limit) and limit > 0 and is_list(opts) do
    insert_fun = Keyword.get(opts, :insert_fun, &insert_cleanup_request_job/1)

    if is_function(insert_fun, 1) do
      cleanup_request_ids = due_cleanup_request_ids_without_delivery(limit)

      failed_count =
        Enum.count(cleanup_request_ids, fn cleanup_request_id ->
          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
          case safe_insert_cleanup_request_job(insert_fun, cleanup_request_id) do
            {:ok, _job} -> false
            {:error, _reason} -> true
          end
        end)

      :telemetry.execute(
        [:storyarn, :assets, :storage_compensation, :delivery_reconciliation],
        %{count: length(cleanup_request_ids), failed_count: failed_count},
        %{}
      )

      if failed_count == 0, do: :ok, else: {:error, failed_count}
    else
      {:error, 1}
    end
  end

  def enqueue_due_cleanup_request_jobs(_limit, _opts), do: {:error, 1}

  defp due_cleanup_request_ids_without_delivery(limit) do
    worker = to_string(DeleteStorageObjectsWorker)
    incomplete_states = ["available", "scheduled", "executing", "retryable"]

    StorageCleanupRequest
    |> join(:left, [request], job in Oban.Job,
      on:
        job.worker == ^worker and job.state in ^incomplete_states and
          fragment("?->>'cleanup_request_id' = CAST(? AS text)", job.args, request.id)
    )
    |> where([request, _job], request.owner_kind == "storage_compensation")
    |> where([request, _job], is_nil(request.multipart_cleanup_phase) or request.multipart_cleanup_phase != "blocked")
    |> where(
      [request, _job],
      is_nil(request.multipart_cleanup_next_attempt_at) or
        request.multipart_cleanup_next_attempt_at <= fragment("clock_timestamp()")
    )
    |> where(
      [request, _job],
      is_nil(request.multipart_quiescence_not_before) or
        request.multipart_quiescence_not_before <= fragment("clock_timestamp()")
    )
    |> where([_request, job], is_nil(job.id))
    |> order_by([request, _job], asc: request.inserted_at, asc: request.id)
    |> limit(^limit)
    |> select([request, _job], request.id)
    |> Repo.all()
  end

  defp safe_insert_cleanup_request_job(insert_fun, cleanup_request_id) do
    case insert_fun.(cleanup_request_id) do
      {:ok, %Oban.Job{}} = success -> success
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_cleanup_delivery_result}
    end
  rescue
    _exception -> {:error, :cleanup_delivery_exception}
  catch
    _kind, _reason -> {:error, :cleanup_delivery_failure}
  end

  @doc false
  @spec retry_persisted_cleanup_request_by_id(pos_integer(), keyword()) ::
          :ok | :blocked | {:deferred, pos_integer()} | {:error, term()}
  def retry_persisted_cleanup_request_by_id(cleanup_request_id, opts \\ [])

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def retry_persisted_cleanup_request_by_id(cleanup_request_id, opts)
      when is_integer(cleanup_request_id) and cleanup_request_id > 0 and is_list(opts) do
    case Repo.get(StorageCleanupRequest, cleanup_request_id) do
      %StorageCleanupRequest{owner_kind: "storage_compensation", multipart_cleanup_phase: "blocked"} ->
        :blocked

      %StorageCleanupRequest{owner_kind: "storage_compensation"} = request ->
        case retry_persisted_cleanup_request(request, opts) do
          :ok -> :ok
          :deferred -> deferred_request_result(cleanup_request_id)
          :error -> failed_request_result(cleanup_request_id)
        end

      %StorageCleanupRequest{} ->
        {:error, :storage_cleanup_request_not_consumable}

      nil ->
        :ok
    end
  end

  def retry_persisted_cleanup_request_by_id(_cleanup_request_id, _opts), do: {:error, :invalid_storage_cleanup_request}

  defp failed_request_result(cleanup_request_id) do
    case Repo.get(StorageCleanupRequest, cleanup_request_id) do
      %StorageCleanupRequest{owner_kind: "storage_compensation", multipart_cleanup_phase: "blocked"} ->
        :blocked

      %StorageCleanupRequest{
        owner_kind: "storage_compensation",
        multipart_cleanup_next_attempt_at: %DateTime{} = next_at
      } ->
        {:deferred, seconds_until(next_at, TimeHelpers.now())}

      %StorageCleanupRequest{} ->
        {:error, :storage_cleanup_failed}

      nil ->
        :ok
    end
  end

  defp deferred_request_result(cleanup_request_id) do
    now = TimeHelpers.now()

    case Repo.get(StorageCleanupRequest, cleanup_request_id) do
      %StorageCleanupRequest{multipart_cleanup_next_attempt_at: %DateTime{} = next_at} = request ->
        if DateTime.after?(next_at, now),
          do: {:deferred, seconds_until(next_at, now)},
          else: deferred_quiescence_result(request, now)

      %StorageCleanupRequest{} = request ->
        deferred_quiescence_result(request, now)

      nil ->
        :ok
    end
  end

  defp deferred_quiescence_result(%StorageCleanupRequest{multipart_quiescence_not_before: %DateTime{} = not_before}, now) do
    if DateTime.after?(not_before, now),
      do: {:deferred, seconds_until(not_before, now)},
      else: {:deferred, 1}
  end

  defp deferred_quiescence_result(%StorageCleanupRequest{}, _now), do: {:deferred, 1}

  @doc "Returns aggregate backlog gauges for durable storage-compensation requests."
  @spec cleanup_request_backlog() :: %{
          pending_count: non_neg_integer(),
          due_count: non_neg_integer(),
          deferred_multipart_count: non_neg_integer(),
          blocked_multipart_count: non_neg_integer(),
          oldest_age_seconds: non_neg_integer(),
          oldest_due_age_seconds: non_neg_integer()
        }
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def cleanup_request_backlog do
    now = TimeHelpers.now()

    stats =
      Repo.one!(
        from(request in StorageCleanupRequest,
          where: request.owner_kind == "storage_compensation",
          select: %{
            pending_count: count(request.id),
            due_count:
              filter(
                count(request.id),
                (is_nil(request.multipart_cleanup_phase) or request.multipart_cleanup_phase != "blocked") and
                  (is_nil(request.multipart_cleanup_next_attempt_at) or
                     request.multipart_cleanup_next_attempt_at <= ^now) and
                  (is_nil(request.multipart_quiescence_not_before) or
                     request.multipart_quiescence_not_before <= ^now)
              ),
            deferred_multipart_count:
              filter(
                count(request.id),
                (is_nil(request.multipart_cleanup_phase) or request.multipart_cleanup_phase != "blocked") and
                  ((not is_nil(request.multipart_cleanup_next_attempt_at) and
                      request.multipart_cleanup_next_attempt_at > ^now) or
                     (not is_nil(request.multipart_quiescence_not_before) and
                        request.multipart_quiescence_not_before > ^now))
              ),
            blocked_multipart_count: filter(count(request.id), request.multipart_cleanup_phase == "blocked"),
            oldest_inserted_at: min(request.inserted_at),
            oldest_due_at:
              filter(
                min(
                  type(
                    fragment("COALESCE(?, ?)", request.multipart_quiescence_not_before, request.inserted_at),
                    :utc_datetime
                  )
                ),
                (is_nil(request.multipart_cleanup_phase) or request.multipart_cleanup_phase != "blocked") and
                  (is_nil(request.multipart_cleanup_next_attempt_at) or
                     request.multipart_cleanup_next_attempt_at <= ^now) and
                  (is_nil(request.multipart_quiescence_not_before) or
                     request.multipart_quiescence_not_before <= ^now)
              )
          }
        )
      )

    %{
      pending_count: stats.pending_count,
      due_count: stats.due_count,
      deferred_multipart_count: stats.deferred_multipart_count,
      blocked_multipart_count: stats.blocked_multipart_count,
      oldest_age_seconds: age_seconds(stats.oldest_inserted_at, now),
      oldest_due_age_seconds: age_seconds(stats.oldest_due_at, now)
    }
  end

  @doc "Emits aggregate durable cleanup backlog gauges without identifiers or payloads."
  @spec emit_cleanup_request_backlog() :: :ok
  def emit_cleanup_request_backlog do
    :telemetry.execute(
      [:storyarn, :assets, :storage_compensation, :backlog],
      Map.put(cleanup_request_backlog(), :observed_at_unix_seconds, DateTime.to_unix(TimeHelpers.now())),
      %{}
    )

    :ok
  end

  defp age_seconds(nil, _now), do: 0
  defp age_seconds(%NaiveDateTime{} = timestamp, now), do: age_seconds(DateTime.from_naive!(timestamp, "Etc/UTC"), now)
  defp age_seconds(timestamp, now), do: max(DateTime.diff(now, timestamp, :second), 0)

  @spec discard(reference()) :: :ok
  def discard(reference) when is_reference(reference) do
    Process.delete(key(reference))
    Process.delete(retained_key(reference))
    :ok
  end

  defp tracked(reference), do: Process.get(key(reference), [])
  defp retained(reference), do: Process.get(retained_key(reference), [])
  defp key(reference), do: {__MODULE__, reference}
  defp retained_key(reference), do: {__MODULE__, reference, :retained_after_commit}

  defp put_tracked(reference, cleanup_target) do
    storage_key = cleanup_target_storage_key(cleanup_target)

    Process.put(
      key(reference),
      [cleanup_target | Enum.reject(tracked(reference), &(cleanup_target_storage_key(&1) == storage_key))]
    )
  end

  defp persist_or_delete_cleanup(reference, storage_keys, enqueue_fun, delete_fun, persist_fun) do
    case call_enqueue(enqueue_fun, storage_keys) do
      :ok ->
        # Deletion is intentionally left to the bounded storage_cleanup queue.
        # Running remote I/O here would let concurrent request failures occupy
        # every Repo connection while holding advisory-lock transactions.
        discard(reference)

      {:error, enqueue_reason} ->
        case call_persist(persist_fun, storage_keys) do
          {:ok, _cleanup_request} ->
            # The recurring reconciler owns these keys now. As above, avoid
            # opportunistic remote deletion on the caller's DB connection.
            discard(reference)

          {:error, persistence_reason} ->
            handle_unpersisted_cleanup(
              reference,
              storage_keys,
              {:error, enqueue_reason},
              persistence_reason,
              delete_fun
            )
        end
    end
  end

  defp delete_or_persist_rollback_cleanup(reference, storage_keys, enqueue_fun, delete_fun, persist_fun) do
    case call_delete(delete_fun, storage_keys) do
      :ok ->
        discard(reference)

      {:error, failed_keys} ->
        failed_keys = normalize_failed_keys(failed_keys, storage_keys)
        retain(reference, failed_keys)
        persist_failed_rollback_cleanup(reference, failed_keys, enqueue_fun, persist_fun)
    end
  end

  defp persist_failed_rollback_cleanup(reference, failed_keys, enqueue_fun, persist_fun) do
    case call_enqueue(enqueue_fun, failed_keys) do
      :ok ->
        discard(reference)

      {:error, enqueue_reason} ->
        case call_persist(persist_fun, failed_keys) do
          {:ok, _cleanup_request} ->
            discard(reference)

          {:error, persistence_reason} ->
            report_unpersisted_cleanup(failed_keys, safe_error(enqueue_reason), persistence_reason)

            {:error,
             {:storage_cleanup_not_persisted,
              %{
                failed_keys: failed_keys,
                enqueue_error: safe_error(enqueue_reason),
                persistence_error: safe_error(persistence_reason)
              }}}
        end
    end
  end

  defp handle_unpersisted_cleanup(reference, storage_keys, enqueue_result, persistence_reason, delete_fun) do
    case call_delete(delete_fun, storage_keys) do
      :ok ->
        discard(reference)

      {:error, failed_keys} ->
        failed_keys = normalize_failed_keys(failed_keys, storage_keys)
        retain(reference, failed_keys)
        enqueue_error = enqueue_error(enqueue_result)
        report_unpersisted_cleanup(failed_keys, enqueue_error, persistence_reason)

        {:error,
         {:storage_cleanup_not_persisted,
          %{
            failed_keys: failed_keys,
            enqueue_error: enqueue_error,
            persistence_error: safe_error(persistence_reason)
          }}}
    end
  end

  defp retain(reference, storage_keys) do
    Process.put(key(reference), storage_keys)
    :ok
  end

  defp enqueue_error(:ok), do: nil
  defp enqueue_error({:error, reason}), do: safe_error(reason)

  defp enqueue_with_retry(storage_keys, insert_fun, attempts, retry_delay_ms) when attempts > 0 do
    case call_insert(insert_fun, storage_keys) do
      {:ok, _job} ->
        :ok

      {:error, reason} when attempts > 1 ->
        Logger.warning(
          "Could not enqueue copied asset cleanup; retrying error=#{safe_error(reason)} attempts_left=#{attempts - 1}"
        )

        Process.sleep(retry_delay_ms)
        enqueue_with_retry(storage_keys, insert_fun, attempts - 1, retry_delay_ms * 2)

      {:error, reason} ->
        Logger.error("Could not enqueue copied asset cleanup error=#{safe_error(reason)}")
        {:error, reason}
    end
  end

  defp insert_cleanup_request_job(cleanup_request_id) do
    %{"cleanup_request_id" => cleanup_request_id}
    |> DeleteStorageObjectsWorker.new()
    |> Oban.insert()
  end

  defp call_enqueue(enqueue_fun, storage_keys) do
    case enqueue_fun.(storage_keys) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      _result -> {:error, :unexpected_enqueue_result}
    end
  rescue
    error -> {:error, {:exception, error.__struct__}}
  catch
    kind, reason -> {:error, {kind, safe_error(reason)}}
  end

  defp call_insert(insert_fun, storage_keys) do
    case insert_fun.(storage_keys) do
      {:ok, _job} = success -> success
      {:error, reason} -> {:error, reason}
      _result -> {:error, :unexpected_insert_result}
    end
  rescue
    error -> {:error, {:exception, error.__struct__}}
  catch
    kind, reason -> {:error, {kind, safe_error(reason)}}
  end

  defp call_persist(persist_fun, storage_keys) do
    case persist_fun.(storage_keys) do
      {:ok, %StorageCleanupRequest{}} = success -> success
      {:error, reason} -> {:error, reason}
      _result -> {:error, :unexpected_persistence_result}
    end
  rescue
    error -> {:error, {:exception, error.__struct__}}
  catch
    kind, reason -> {:error, {kind, safe_error(reason)}}
  end

  defp call_delete(delete_fun, storage_keys) do
    case delete_fun.(storage_keys) do
      :ok ->
        :ok

      {:error, failed_keys} when is_list(failed_keys) ->
        {:error, normalize_failed_keys(failed_keys, storage_keys)}

      _result ->
        {:error, storage_keys}
    end
  rescue
    error ->
      Logger.error("Copied asset deletion raised error=#{safe_error(error)}")
      {:error, storage_keys}
  catch
    kind, reason ->
      Logger.error("Copied asset deletion failed error=#{safe_error({kind, reason})}")
      {:error, storage_keys}
  end

  defp normalize_failed_keys(failed_keys, storage_keys) do
    failed_keys = Enum.uniq(failed_keys)
    storage_key_set = MapSet.new(storage_keys)

    if failed_keys != [] and Enum.all?(failed_keys, &MapSet.member?(storage_key_set, &1)) do
      failed_keys
    else
      storage_keys
    end
  end

  @doc "Persists storage keys for the recurring cleanup reconciler."
  @spec persist_cleanup_request([String.t()]) ::
          {:ok, StorageCleanupRequest.t()} | {:error, term()}
  def persist_cleanup_request(cleanup_targets) when is_list(cleanup_targets) do
    cleanup_targets = normalize_cleanup_targets(cleanup_targets)

    case cleanup_targets do
      [] -> {:error, :no_valid_storage_keys}
      cleanup_targets -> insert_cleanup_request(cleanup_targets, %{}, :fallback)
    end
  end

  @doc "Persists a planned storage cleanup handoff without reporting a fallback."
  @spec persist_planned_cleanup_request([String.t()]) ::
          {:ok, StorageCleanupRequest.t()} | {:error, term()}
  def persist_planned_cleanup_request(cleanup_targets), do: persist_planned_cleanup_request(cleanup_targets, [])

  @doc false
  @spec persist_planned_cleanup_request([String.t()], keyword()) ::
          {:ok, StorageCleanupRequest.t()} | {:error, term()}
  def persist_planned_cleanup_request(cleanup_targets, opts) when is_list(cleanup_targets) and is_list(opts) do
    cleanup_targets = normalize_cleanup_targets(cleanup_targets)

    with true <- Keyword.keyword?(opts),
         {:ok, attrs} <- planned_cleanup_request_attrs(opts) do
      case cleanup_targets do
        [] -> {:error, :no_valid_storage_keys}
        cleanup_targets -> insert_cleanup_request(cleanup_targets, attrs, :planned_handoff)
      end
    else
      false -> {:error, :invalid_cleanup_options}
      {:error, _reason} = error -> error
    end
  end

  defp planned_cleanup_request_attrs(opts) do
    with true <- Enum.all?(Keyword.keys(opts), &(&1 in [:not_before, :provider_namespace_fingerprint])),
         {:ok, attrs} <- planned_namespace_attrs(Keyword.get(opts, :provider_namespace_fingerprint)),
         {:ok, attrs} <- planned_not_before_attrs(attrs, Keyword.get(opts, :not_before)) do
      {:ok, attrs}
    else
      false -> {:error, :invalid_cleanup_options}
      {:error, _reason} = error -> error
    end
  end

  defp planned_namespace_attrs(nil), do: {:ok, %{}}

  defp planned_namespace_attrs(fingerprint) do
    if Storage.valid_namespace_fingerprint?(fingerprint),
      do: {:ok, %{provider_namespace_fingerprint: fingerprint}},
      else: {:error, :invalid_cleanup_provider_namespace_fingerprint}
  end

  defp planned_not_before_attrs(attrs, nil), do: {:ok, attrs}

  defp planned_not_before_attrs(attrs, %DateTime{} = not_before) do
    now = database_clock_now()

    if DateTime.after?(not_before, now),
      do: {:ok, Map.merge(attrs, %{multipart_quiescence_started_at: now, multipart_quiescence_not_before: not_before})},
      else: {:ok, attrs}
  end

  defp planned_not_before_attrs(_attrs, _invalid), do: {:error, :invalid_cleanup_not_before}

  @doc false
  @spec persist_snapshot_lifecycle_cleanup([String.t()], Ecto.UUID.t(), String.t()) ::
          {:ok, StorageCleanupRequest.t()} | {:error, term()}
  def persist_snapshot_lifecycle_cleanup(cleanup_targets, owner_token, provider_namespace_fingerprint)
      when is_list(cleanup_targets) and is_binary(owner_token) and is_binary(provider_namespace_fingerprint) do
    cleanup_targets = normalize_cleanup_targets(cleanup_targets)

    case cleanup_targets do
      [] ->
        {:error, :no_valid_storage_keys}

      cleanup_targets ->
        insert_cleanup_request(
          cleanup_targets,
          %{
            owner_kind: "snapshot_lifecycle",
            owner_token: owner_token,
            provider_namespace_fingerprint: provider_namespace_fingerprint
          },
          :snapshot_lifecycle
        )
    end
  end

  def persist_snapshot_lifecycle_cleanup(_cleanup_targets, _owner_token, _provider_namespace_fingerprint),
    do: {:error, :invalid_snapshot_cleanup_owner}

  defp insert_cleanup_request(storage_keys, attrs, persistence_kind) do
    with {:ok, attrs} <- prepare_cleanup_request_attrs(storage_keys, attrs),
         {:ok, attrs} <- finalize_cleanup_request_attrs(storage_keys, attrs) do
      attrs = Map.put(attrs, :storage_keys, storage_keys)

      insert_result = %StorageCleanupRequest{} |> StorageCleanupRequest.changeset(attrs) |> Repo.insert()

      case insert_result do
        {:ok, cleanup_request} = success ->
          report_cleanup_request_persisted(cleanup_request, storage_keys, persistence_kind)

          success

        {:error, _changeset} = error ->
          error
      end
    end
  rescue
    error ->
      Logger.error("Could not persist #{cleanup_persistence_label(persistence_kind)} error=#{safe_error(error)}")

      {:error, {:exception, error.__struct__}}
  catch
    kind, reason ->
      Logger.error("Could not persist #{cleanup_persistence_label(persistence_kind)} error=#{safe_error({kind, reason})}")

      {:error, {kind, safe_error(reason)}}
  end

  defp prepare_cleanup_request_attrs(storage_keys, attrs) do
    if multipart_cleanup_keys(storage_keys) == [] do
      {:ok, drop_unused_provider_namespace(attrs)}
    else
      case Map.get(attrs, :provider_namespace_fingerprint) do
        fingerprint when is_binary(fingerprint) ->
          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
          if Storage.valid_namespace_fingerprint?(fingerprint),
            do: {:ok, Map.put_new(attrs, :multipart_cleanup_phase, "discover")},
            else: {:error, :invalid_cleanup_provider_namespace_fingerprint}

        nil ->
          capture_missing_provider_namespace(attrs)
      end
    end
  rescue
    _exception -> {:error, :multipart_cleanup_provider_namespace_unavailable}
  catch
    _kind, _reason -> {:error, :multipart_cleanup_provider_namespace_unavailable}
  end

  defp drop_unused_provider_namespace(%{owner_kind: "snapshot_lifecycle"} = attrs), do: attrs
  defp drop_unused_provider_namespace(attrs), do: Map.delete(attrs, :provider_namespace_fingerprint)

  defp finalize_cleanup_request_attrs(_storage_keys, attrs), do: {:ok, attrs}

  defp capture_missing_provider_namespace(attrs) do
    case Storage.namespace_fingerprint() do
      {:ok, fingerprint} when is_binary(fingerprint) ->
        {:ok,
         attrs
         |> Map.put(:provider_namespace_fingerprint, fingerprint)
         |> Map.put(:multipart_cleanup_phase, "discover")}

      _unavailable ->
        {:error, :multipart_cleanup_provider_namespace_unavailable}
    end
  end

  # Planned handoffs are often inserted inside a wider transaction. Reporting
  # here could claim durability for a row that the outer transaction later
  # rolls back; their owners emit post-commit lifecycle events instead.
  defp report_cleanup_request_persisted(_cleanup_request, _storage_keys, :planned_handoff), do: :ok
  defp report_cleanup_request_persisted(_cleanup_request, _storage_keys, :snapshot_lifecycle), do: :ok

  defp report_cleanup_request_persisted(cleanup_request, storage_keys, :fallback) do
    Logger.warning(
      "Persisted copied asset cleanup fallback request_id=#{cleanup_request.id} storage_key_count=#{length(storage_keys)}"
    )

    :telemetry.execute(
      [:storyarn, :assets, :storage_compensation, :fallback_persisted],
      %{count: 1, storage_key_count: length(storage_keys)},
      %{request_id: cleanup_request.id}
    )
  end

  defp cleanup_persistence_label(:planned_handoff), do: "planned storage cleanup request"
  defp cleanup_persistence_label(:snapshot_lifecycle), do: "snapshot lifecycle cleanup request"
  defp cleanup_persistence_label(:fallback), do: "copied asset cleanup fallback"

  defp retry_persisted_cleanup_request(cleanup_request, opts) do
    multipart? = multipart_cleanup_keys(cleanup_request.storage_keys) != []
    cleanup_opts = if multipart?, do: Keyword.put(opts, :consume?, true), else: opts

    case delete_cleanup_request_keys(cleanup_request.id, cleanup_request.storage_keys, cleanup_opts) do
      :ok ->
        if multipart? do
          :ok
        else
          cleanup_request
          |> Repo.delete()
          |> persisted_retry_result()
        end

      {:deferred, _seconds} ->
        :deferred

      {:error, failed_keys} ->
        if multipart? do
          :error
        else
          cleanup_request
          |> rotate_persisted_cleanup_request(failed_keys)
          |> persisted_retry_result(:error)
        end
    end
  end

  defp rotate_persisted_cleanup_request(cleanup_request, failed_keys) do
    Repo.transact(fn ->
      with {:ok, replacement} <-
             %StorageCleanupRequest{}
             |> StorageCleanupRequest.changeset(%{storage_keys: failed_keys})
             |> Repo.insert(),
           {:ok, _deleted_request} <- Repo.delete(cleanup_request) do
        {:ok, replacement}
      end
    end)
  end

  defp persisted_retry_result({:ok, _request}), do: :ok
  defp persisted_retry_result({:error, _changeset}), do: :error
  defp persisted_retry_result({:ok, _request}, result), do: result
  defp persisted_retry_result({:error, _changeset}, _result), do: :error

  defp authorize_multipart_cleanup_targets(cleanup_targets) do
    Enum.reduce_while(cleanup_targets, :ok, fn storage_key, :ok ->
      case authorize_multipart_cleanup_target(storage_key) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp authorize_multipart_cleanup_target(storage_key) do
    if Storage.multipart_cleanup_key?(storage_key) do
      case multipart_cleanup_object_policy(storage_key) do
        policy when policy in [:delete, :retain] -> :ok
        {:error, _reason} = error -> error
      end
    else
      {:error, :multipart_cleanup_target_not_deletable}
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp multipart_cleanup_object_policy(cleanup_target) do
    storage_key = cleanup_target_storage_key(cleanup_target)
    force_delete? = force_delete_target?(cleanup_target)

    cond do
      not valid_cleanup_target?(cleanup_target) ->
        {:error, :invalid_multipart_cleanup_target}

      active_restore_storage_owner?(storage_key) ->
        {:error, :storage_key_owned_by_active_reservation}

      active_workspace_snapshot_import_storage_owner?(storage_key) ->
        {:error, :storage_key_owned_by_active_workspace_snapshot_import}

      committed_asset_key?(storage_key) ->
        :retain

      committed_template_storage_key?(storage_key) ->
        :retain

      committed_snapshot_storage_key?(storage_key) ->
        :retain

      Storage.multipart_cleanup_key?(storage_key) ->
        :delete

      match?({:ok, _project_id}, StorageKeyLock.project_blob_id(storage_key)) ->
        conservative_project_blob_cleanup_policy(storage_key, force_delete?)

      true ->
        :delete
    end
  end

  defp conservative_project_blob_cleanup_policy(storage_key, true) do
    {:ok, project_id, expected_hash} = StorageKeyLock.project_blob_identity(storage_key)

    case stored_object_hash(storage_key) do
      {:ok, ^expected_hash} ->
        if committed_project?(project_id), do: :retain, else: :delete

      {:ok, _invalid_hash} ->
        :delete

      {:error, reason} ->
        if storage_not_found?(reason),
          do: :delete,
          else: {:error, :force_cleanup_identity_verification_failed}
    end
  end

  defp conservative_project_blob_cleanup_policy(storage_key, false) do
    {:ok, project_id} = StorageKeyLock.project_blob_id(storage_key)
    if committed_project?(project_id), do: :retain, else: :delete
  end

  defp safe_deferred_storage_delete(cleanup_target, restore_cleanup_owner) do
    storage_key = cleanup_target_storage_key(cleanup_target)
    force_delete? = force_delete_target?(cleanup_target)

    StorageKeyLock.with_storage_key_lock(storage_key, fn ->
      deferred_storage_delete(storage_key, force_delete?, restore_cleanup_owner)
    end)
  rescue
    error ->
      Logger.error("Copied asset deletion raised error=#{safe_error(error)}")
      {:error, :delete_exception}
  catch
    kind, reason ->
      Logger.error("Copied asset deletion failed error=#{safe_error({kind, reason})}")
      {:error, :delete_failure}
  end

  defp delete_owned_storage_key(storage_key, force_delete?) do
    if Repo.in_transaction?() do
      delete_owned_storage_key_in_transaction(storage_key, force_delete?)
    else
      StorageKeyLock.with_storage_key_lock(storage_key, fn ->
        deferred_storage_delete(storage_key, force_delete?)
      end)
    end
  end

  # Only StorageKeyLock's wrapper-owned transaction can reach this branch. A
  # caller-owned transaction may see an uncommitted Project row, so it must
  # leave the force target tracked for post-transaction cleanup.
  defp delete_owned_storage_key_in_transaction(storage_key, true) do
    if StorageKeyLock.wrapper_owned_transaction_lock_held?(storage_key),
      do: deferred_storage_delete(storage_key, true),
      else: {:error, :storage_cleanup_requires_post_transaction}
  end

  defp delete_owned_storage_key_in_transaction(storage_key, false) do
    cond do
      active_restore_storage_owner?(storage_key) ->
        {:error, :storage_key_owned_by_active_restore}

      active_workspace_snapshot_import_storage_owner?(storage_key) ->
        {:error, :storage_key_owned_by_active_workspace_snapshot_import}

      committed_asset_key?(storage_key) ->
        retain_committed_asset(storage_key)

      true ->
        delete_storage_object(storage_key)
    end
  end

  defp deferred_storage_delete(storage_key, force_delete?) do
    deferred_storage_delete(storage_key, force_delete?, nil)
  end

  defp deferred_storage_delete(storage_key, force_delete?, restore_cleanup_owner) do
    cond do
      active_restore_storage_owner?(storage_key, restore_cleanup_owner) ->
        {:error, :storage_key_owned_by_active_restore}

      active_workspace_snapshot_import_storage_owner?(storage_key) ->
        {:error, :storage_key_owned_by_active_workspace_snapshot_import}

      committed_asset_key?(storage_key) ->
        retain_committed_asset(storage_key)

      committed_template_storage_key?(storage_key) ->
        retain_committed_template_storage(storage_key)

      committed_snapshot_storage_key?(storage_key) ->
        retain_committed_snapshot_storage(storage_key)

      force_delete? ->
        delete_if_still_invalid(storage_key)

      match?({:ok, _project_id}, StorageKeyLock.project_blob_id(storage_key)) ->
        delete_uncommitted_project_blob(storage_key)

      true ->
        delete_storage_object(storage_key)
    end
  end

  defp delete_uncommitted_project_blob(storage_key) do
    {:ok, project_id} = StorageKeyLock.project_blob_id(storage_key)

    if Repo.exists?(from project in Project, where: project.id == ^project_id),
      do: retain_committed_project_blob(project_id),
      else: delete_storage_object(storage_key)
  end

  defp delete_if_still_invalid(storage_key) do
    case StorageKeyLock.project_blob_identity(storage_key) do
      {:ok, project_id, expected_hash} ->
        storage_key
        |> stored_object_hash()
        |> handle_force_delete_hash(storage_key, project_id, expected_hash)

      :error ->
        delete_storage_object(storage_key)
    end
  end

  defp handle_force_delete_hash({:ok, expected_hash}, storage_key, project_id, expected_hash) do
    if committed_project?(project_id),
      do: retain_repaired_project_blob(project_id),
      else: delete_storage_object(storage_key)
  end

  defp handle_force_delete_hash({:ok, _invalid_hash}, storage_key, _project_id, _expected_hash) do
    delete_storage_object(storage_key)
  end

  defp handle_force_delete_hash({:error, reason}, _storage_key, _project_id, _expected_hash) do
    if storage_not_found?(reason), do: :ok, else: {:error, reason}
  end

  defp stored_object_hash(storage_key) do
    with {:ok, stat} <- Storage.stat(storage_key),
         {:ok, chunks} <- Storage.stream(storage_key, 0, stat.size, etag: stat.etag) do
      StorageHash.sha256_chunks(chunks)
    end
  end

  defp storage_not_found?(:enoent), do: true
  defp storage_not_found?({:http_error, 404, _response}), do: true
  defp storage_not_found?(_reason), do: false

  # `Storage.delete/1` deliberately protects every project blob at the public
  # boundary. Compensation reaches the raw technical delete only after
  # validating the key, fencing it with `StorageKeyLock`, and proving that no
  # committed owner must retain it.
  defp delete_storage_object(storage_key) do
    if Storage.multipart_cleanup_key?(storage_key),
      do: {:error, :multipart_cleanup_requires_durable_request},
      else: Storage.delete_after_policy_check(storage_key)
  end

  defp committed_asset_key?(storage_key) do
    Repo.exists?(from asset in Asset, where: asset.key == ^storage_key)
  end

  defp active_restore_storage_owner?(storage_key), do: active_restore_storage_owner?(storage_key, nil)

  defp active_restore_storage_owner?(storage_key, restore_cleanup_owner) do
    storage_key
    |> active_restore_storage_owner_query()
    |> exclude_restore_cleanup_owner(restore_cleanup_owner)
    |> Repo.exists?()
  end

  defp active_restore_storage_owner_query(storage_key) do
    from reservation in StorageReservation,
      where:
        reservation.kind in ^@storage_reservation_record_kinds and reservation.status == "active" and
          not is_nil(reservation.storage_started_at) and
          fragment("? @> ARRAY[?]::text[]", reservation.cleanup_storage_keys, ^storage_key)
  end

  defp exclude_restore_cleanup_owner(query, {reservation_id, lease_token, generation}) do
    from reservation in query,
      where:
        reservation.id != ^reservation_id or reservation.lease_token != ^lease_token or
          reservation.generation != ^generation
  end

  defp exclude_restore_cleanup_owner(query, nil), do: query

  defp active_workspace_snapshot_import_storage_owner?(storage_key) do
    Repo.exists?(
      from import in WorkspaceSnapshotImport,
        where:
          import.status in ^WorkspaceSnapshotImport.active_statuses() and
            (fragment("? @> ARRAY[?]::varchar[]", import.staging_storage_keys, ^storage_key) or
               fragment("? @> ARRAY[?]::varchar[]", import.materialization_storage_keys, ^storage_key))
    )
  end

  defp normalize_restore_cleanup_owner(%StorageReservation{
         id: reservation_id,
         lease_token: lease_token,
         generation: generation
       })
       when is_integer(reservation_id) and reservation_id > 0 and is_binary(lease_token) and is_integer(generation) and
              generation > 0, do: {reservation_id, lease_token, generation}

  defp normalize_restore_cleanup_owner(_restore_cleanup_owner), do: nil

  defp committed_project?(project_id) do
    Repo.exists?(from project in Project, where: project.id == ^project_id)
  end

  defp committed_template_storage_key?(storage_key) do
    case template_storage_identity(storage_key) do
      {:artifact, :publication, _publication_id} ->
        committed_template_version_storage_key?(storage_key) or
          Repo.exists?(
            from publication in ProjectTemplatePublication,
              where:
                publication.snapshot_storage_key == ^storage_key or
                  publication.asset_manifest_storage_key == ^storage_key
          )

      {:artifact, _slug, _suffix} ->
        committed_template_version_storage_key?(storage_key)

      {:imported_blob, slug, suffix} ->
        asset_manifest_key = "project_templates/imports/#{slug}/#{suffix}/asset-manifest.json.gz"

        Repo.exists?(
          from version in ProjectTemplateVersion,
            where: version.asset_manifest_storage_key == ^asset_manifest_key
        )

      :error ->
        false
    end
  end

  defp committed_snapshot_storage_key?(storage_key) do
    case snapshot_archive_storage_identity(storage_key) do
      {:object, project_id, :ready, object_prefix, false} ->
        committed_snapshot_namespace?(project_id, object_prefix)

      _other ->
        false
    end
  end

  defp committed_snapshot_namespace?(project_id, object_prefix) do
    Repo.exists?(committed_snapshot_query(project_id, object_prefix)) or
      Repo.exists?(published_snapshot_claim_query(object_prefix))
  end

  defp committed_snapshot_query(project_id, object_prefix) do
    ProjectSnapshot
    |> where([snapshot], snapshot.project_id == ^project_id)
    |> where([snapshot], snapshot.object_prefix == ^object_prefix)
    |> where([snapshot], snapshot.format_version == 2)
    |> where([snapshot], snapshot.lifecycle_state in ["ready", "deleting"])
    |> where([snapshot], snapshot.accounting_version == 1)
    |> where([snapshot], not is_nil(snapshot.accounted_size_bytes))
  end

  defp published_snapshot_claim_query(object_prefix) do
    SnapshotObjectPublicationClaim
    |> where([claim], claim.object_prefix == ^object_prefix)
    |> where([claim], claim.status == "published")
  end

  defp committed_template_version_storage_key?(storage_key) do
    Repo.exists?(
      from version in ProjectTemplateVersion,
        where:
          version.snapshot_storage_key == ^storage_key or
            version.asset_manifest_storage_key == ^storage_key
    )
  end

  defp cleanup_one(cleanup_target, cleanup_opts) do
    tracker = new()
    put_tracked(tracker, cleanup_target)
    cleanup(tracker, cleanup_opts)
  end

  defp in_transaction?(opts) do
    Keyword.get_lazy(opts, :in_transaction?, &Repo.in_transaction?/0) == true
  end

  # Content-addressed blobs are an immutable, project-scoped cache used by
  # snapshots even after their Asset row is gone. A delayed cleanup cannot
  # prove that a committed project has not adopted the deterministic key, so
  # retaining it is the only non-destructive outcome. Blobs belonging to
  # rolled-back projects are still removed because their Project row is absent.
  defp retain_committed_project_blob(project_id) do
    :telemetry.execute(
      [:storyarn, :assets, :storage_compensation, :project_blob_retained],
      %{count: 1},
      %{project_id: project_id}
    )

    :ok
  end

  defp retain_repaired_project_blob(project_id) do
    :telemetry.execute(
      [:storyarn, :assets, :storage_compensation, :project_blob_repaired],
      %{count: 1},
      %{project_id: project_id}
    )

    :ok
  end

  # A transaction can commit in PostgreSQL even when the client loses the
  # commit acknowledgement. Never compensate a unique object after a database
  # row has adopted its key, otherwise that ambiguous outcome would corrupt a
  # live Asset record.
  defp retain_committed_asset(_storage_key) do
    :telemetry.execute(
      [:storyarn, :assets, :storage_compensation, :asset_retained],
      %{count: 1},
      %{key_type: :asset}
    )

    :ok
  end

  defp retain_committed_template_storage(_storage_key) do
    :telemetry.execute(
      [:storyarn, :assets, :storage_compensation, :template_storage_retained],
      %{count: 1},
      %{key_type: :template_artifact}
    )

    :ok
  end

  defp retain_committed_snapshot_storage(_storage_key) do
    :telemetry.execute(
      [:storyarn, :assets, :storage_compensation, :snapshot_storage_retained],
      %{count: 1},
      %{key_type: :snapshot_object}
    )

    :ok
  end

  defp report_unpersisted_cleanup(failed_keys, enqueue_error, persistence_reason) do
    Logger.error(
      "Copied asset cleanup could not be completed or persisted failed_count=#{length(failed_keys)} enqueue_error=#{inspect(enqueue_error)} persistence_error=#{safe_error(persistence_reason)}"
    )

    :telemetry.execute(
      [:storyarn, :assets, :storage_compensation, :persistence_failed],
      %{count: 1, failed_count: length(failed_keys)},
      %{
        enqueue_error: enqueue_error,
        persistence_error: safe_error(persistence_reason)
      }
    )
  end

  defp valid_storage_key?(storage_key) when is_binary(storage_key) do
    String.valid?(storage_key) and
      (project_owned_storage_key?(storage_key) or template_storage_key?(storage_key) or
         snapshot_archive_storage_key?(storage_key) or storage_reservation_key?(storage_key) or
         String.match?(storage_key, @workspace_snapshot_import_key_pattern))
  end

  @doc false
  @spec template_storage_key?(term()) :: boolean()
  def template_storage_key?(storage_key) when is_binary(storage_key) do
    match?({_, _, _}, template_storage_identity(storage_key))
  end

  def template_storage_key?(_storage_key), do: false

  defp project_owned_storage_key?(storage_key) do
    project_blob_storage_key?(storage_key) or
      project_asset_storage_key?(storage_key) or
      project_thumbnail_storage_key?(storage_key) or
      project_conditional_copy_key?(storage_key)
  end

  defp project_blob_storage_key?(storage_key) do
    String.match?(storage_key, @blob_key_pattern) and
      match?({:ok, _project_id, _hash}, StorageKeyLock.project_blob_identity(storage_key))
  end

  defp project_asset_storage_key?(storage_key) do
    case String.split(storage_key, "/") do
      ["projects", project_id, "assets", asset_uuid, filename] ->
        valid_project_id?(project_id) and
          String.match?(asset_uuid, @asset_uuid_pattern) and
          filename not in [".", "..", ".storyarn-copy"] and
          String.match?(filename, @asset_filename_pattern)

      _parts ->
        false
    end
  end

  defp project_thumbnail_storage_key?(storage_key) do
    case String.split(storage_key, "/") do
      ["projects", project_id, "thumbnails", asset_uuid, filename] ->
        valid_project_id?(project_id) and
          String.match?(asset_uuid, @asset_uuid_pattern) and
          filename not in [".", "..", ".storyarn-copy"] and
          String.match?(filename, @asset_filename_pattern)

      _parts ->
        false
    end
  end

  defp project_conditional_copy_key?(storage_key) do
    case String.split(storage_key, "/") do
      ["projects", project_id, "blobs", ".storyarn-copy", suffix] ->
        valid_project_id?(project_id) and String.match?(suffix, @conditional_copy_suffix_pattern)

      ["projects", project_id, "assets", asset_uuid, ".storyarn-copy", suffix] ->
        valid_project_id?(project_id) and
          String.match?(asset_uuid, @asset_uuid_pattern) and
          String.match?(suffix, @conditional_copy_suffix_pattern)

      _parts ->
        false
    end
  end

  defp snapshot_archive_storage_key?(storage_key) do
    match?({:object, _project_id, _state, _object_prefix, _temporary?}, snapshot_archive_storage_identity(storage_key))
  end

  defp snapshot_archive_storage_identity(storage_key) do
    case String.split(storage_key, "/", trim: false) do
      ["projects", project_id, "snapshots", "archives", "v2", state, token | tail] ->
        with true <- valid_project_id?(project_id),
             {:ok, state} <- snapshot_state(state),
             true <- String.match?(token, @snapshot_token_pattern),
             {:ok, temporary?} <- snapshot_archive_tail(tail) do
          object_prefix =
            Enum.join(["projects", project_id, "snapshots", "archives", "v2", Atom.to_string(state), token], "/")

          {:object, String.to_integer(project_id), state, object_prefix, temporary?}
        else
          _invalid -> :error
        end

      _other ->
        :error
    end
  end

  defp snapshot_state("staging"), do: {:ok, :staging}
  defp snapshot_state("ready"), do: {:ok, :ready}
  defp snapshot_state(_state), do: :error

  defp snapshot_archive_tail([filename]) when filename in ["snapshot.zip", "manifest.json"], do: {:ok, false}

  defp snapshot_archive_tail([".storyarn-copy", suffix]) do
    if String.match?(suffix, @conditional_copy_suffix_pattern), do: {:ok, true}, else: :error
  end

  defp snapshot_archive_tail(_tail), do: :error

  defp storage_reservation_key?(storage_key) do
    case String.split(storage_key, "/", trim: false) do
      ["projects", project_id, "storage-reservations", "v1", kind, lease_token | tail] ->
        valid_project_id?(project_id) and
          kind in @storage_reservation_path_kinds and
          String.match?(lease_token, @storage_reservation_lease_pattern) and
          valid_storage_reservation_tail?(tail)

      _parts ->
        false
    end
  end

  defp valid_storage_reservation_tail?(tail) when is_list(tail) and tail != [] do
    relative_key = Enum.join(tail, "/")

    byte_size(relative_key) <= @max_storage_reservation_relative_key_bytes and
      length(tail) <= @max_storage_reservation_path_segments and
      valid_storage_reservation_segments?(tail)
  end

  defp valid_storage_reservation_tail?(_tail), do: false

  defp valid_storage_reservation_segments?(tail) do
    case Enum.split(tail, -2) do
      {parents, [".storyarn-copy", suffix]} ->
        String.match?(suffix, @conditional_copy_suffix_pattern) and
          Enum.all?(parents, &valid_storage_reservation_segment?/1)

      {_parents, _suffix} ->
        Enum.all?(tail, &valid_storage_reservation_segment?/1)
    end
  end

  defp valid_storage_reservation_segment?(segment) do
    String.match?(segment, @storage_reservation_path_segment_pattern)
  end

  defp valid_project_id?(project_id) do
    case Integer.parse(project_id) do
      {parsed_id, ""} -> parsed_id > 0 and parsed_id <= @max_project_id and Integer.to_string(parsed_id) == project_id
      _invalid -> false
    end
  end

  defp template_storage_identity(storage_key) do
    storage_key
    |> String.split("/")
    |> parse_template_storage_identity()
  end

  defp parse_template_storage_identity(["project_templates", "imports", slug, suffix, filename]) do
    if valid_template_namespace?(slug, suffix) and
         filename in ["snapshot.json.gz", "asset-manifest.json.gz"],
       do: {:artifact, slug, suffix},
       else: :error
  end

  defp parse_template_storage_identity(["project_templates", "imported_blobs", slug, suffix, hash, filename]) do
    if valid_template_namespace?(slug, suffix) and valid_template_filename?(filename),
      do: imported_blob_storage_identity(slug, suffix, hash),
      else: :error
  end

  defp parse_template_storage_identity(["project_template_publications", publication_id, filename])
       when publication_id != "" and filename not in ["", ".", ".."] do
    publication_storage_identity(publication_id, filename)
  end

  defp parse_template_storage_identity(_parts), do: :error

  defp valid_template_namespace?(slug, suffix) do
    String.match?(slug, @template_namespace_pattern) and
      String.match?(suffix, @template_namespace_pattern)
  end

  defp valid_template_filename?(filename) do
    filename == String.downcase(filename) and
      String.match?(filename, @template_filename_pattern)
  end

  defp imported_blob_storage_identity(slug, suffix, hash) do
    if String.match?(hash, ~r/\A[0-9a-f]{64}\z/),
      do: {:imported_blob, slug, suffix},
      else: :error
  end

  defp publication_storage_identity(publication_id, filename) do
    with {publication_id, ""} when publication_id > 0 <- Integer.parse(publication_id),
         true <- String.match?(filename, ~r/\A(?:snapshot|asset-manifest)-[0-9a-f]+\.json\.gz\z/) do
      {:artifact, :publication, publication_id}
    else
      _invalid -> :error
    end
  end

  # A provider object may only have one cleanup policy in a durable request.
  # Preserve first-seen provider-key order, while making the stricter
  # force-delete intent win when callers supplied both representations.
  defp normalize_cleanup_targets(cleanup_targets) do
    {provider_keys, targets_by_key} =
      Enum.reduce(cleanup_targets, {[], %{}}, fn cleanup_target, {provider_keys, targets_by_key} ->
        if valid_cleanup_target?(cleanup_target) do
          storage_key = cleanup_target_storage_key(cleanup_target)
          first_observation? = not Map.has_key?(targets_by_key, storage_key)

          selected_target =
            case Map.get(targets_by_key, storage_key) do
              nil ->
                cleanup_target

              existing ->
                # credo:disable-for-next-line Credo.Check.Refactor.Nesting
                cond do
                  force_delete_target?(existing) -> existing
                  force_delete_target?(cleanup_target) -> cleanup_target
                  true -> existing
                end
            end

          provider_keys = if first_observation?, do: [storage_key | provider_keys], else: provider_keys
          {provider_keys, Map.put(targets_by_key, storage_key, selected_target)}
        else
          {provider_keys, targets_by_key}
        end
      end)

    provider_keys
    |> Enum.reverse()
    |> Enum.map(&Map.fetch!(targets_by_key, &1))
  end

  defp valid_cleanup_target?(cleanup_target) when is_binary(cleanup_target) do
    cleanup_target
    |> cleanup_target_storage_key()
    |> valid_storage_key?()
  end

  defp valid_cleanup_target?(_cleanup_target), do: false

  defp force_delete_target(storage_key), do: @force_delete_prefix <> storage_key

  defp force_delete_target?(cleanup_target) when is_binary(cleanup_target),
    do: String.starts_with?(cleanup_target, @force_delete_prefix)

  defp force_delete_target?(_cleanup_target), do: false

  defp cleanup_target_storage_key(cleanup_target) when is_binary(cleanup_target) do
    String.replace_prefix(cleanup_target, @force_delete_prefix, "")
  end

  defp cleanup_target_storage_key(_cleanup_target), do: ""

  defp normalize_delete_attempts(attempts) when is_integer(attempts) and attempts > 0, do: attempts
  defp normalize_delete_attempts(_attempts), do: 1

  defp normalize_delete_retry_delay(delay_ms) when is_integer(delay_ms) and delay_ms >= 0, do: delay_ms
  defp normalize_delete_retry_delay(_delay_ms), do: @delete_retry_delay_ms

  defp delete_with_retry(storage_key, delete_fun, attempts, retry_delay_ms) when attempts > 0 do
    case call_single_delete(delete_fun, storage_key) do
      :ok ->
        :ok

      {:error, _reason} = error when attempts == 1 ->
        error

      {:error, _reason} ->
        Process.sleep(retry_delay_ms)
        delete_with_retry(storage_key, delete_fun, attempts - 1, retry_delay_ms * 2)
    end
  end

  defp call_single_delete(delete_fun, storage_key) do
    case delete_fun.(storage_key) do
      :ok -> :ok
      {:error, _reason} = error -> error
      _result -> {:error, :unexpected_delete_result}
    end
  rescue
    _error -> {:error, :delete_exception}
  catch
    _kind, _reason -> {:error, :delete_failure}
  end

  defp safe_error(reason) when is_atom(reason), do: reason
  defp safe_error(%module{}), do: module
  defp safe_error({reason, _details}) when is_atom(reason), do: reason
  defp safe_error(_reason), do: :unexpected_error
end
