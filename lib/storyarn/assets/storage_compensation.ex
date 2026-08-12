defmodule Storyarn.Assets.StorageCompensation do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupPersistenceError
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Assets.StorageHash
  alias Storyarn.Assets.StorageKeyLock
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim
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
  @storage_reservation_kinds ~w(snapshot-build restore-staging snapshot-export)
  @storage_reservation_lease_pattern ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @storage_reservation_path_segment_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/
  @max_storage_reservation_relative_key_bytes 512
  @max_storage_reservation_path_segments 16
  @multipart_cleanup_evidence_key {__MODULE__, :multipart_cleanup_aborted_count}

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

  @spec cleanup(reference(), keyword()) :: :ok | {:error, term()}
  def cleanup(reference, opts \\ []) when is_reference(reference) do
    cleanup_targets = reference |> tracked() |> Enum.filter(&valid_cleanup_target?/1) |> Enum.uniq()
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
    cleanup_targets = reference |> tracked() |> Enum.filter(&valid_cleanup_target?/1) |> Enum.uniq()
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
    delete_fun = Keyword.get(opts, :delete_fun, &delete_storage_keys/1)
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

  defp unretained_cleanup_targets(reference) do
    retained_keys = reference |> retained() |> MapSet.new()

    reference
    |> tracked()
    |> Enum.reject(&MapSet.member?(retained_keys, cleanup_target_storage_key(&1)))
    |> Enum.filter(&valid_cleanup_target?/1)
    |> Enum.uniq()
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
    failed_targets =
      cleanup_targets
      |> Enum.filter(&valid_cleanup_target?/1)
      |> Enum.uniq()
      |> Enum.filter(fn cleanup_target ->
        case safe_deferred_storage_delete(cleanup_target) do
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
    previous = Process.get(@multipart_cleanup_evidence_key, :not_collecting)
    Process.put(@multipart_cleanup_evidence_key, 0)

    try do
      case delete_storage_keys(cleanup_targets) do
        :ok -> {:ok, %{aborted_count: Process.get(@multipart_cleanup_evidence_key, 0)}}
        {:error, failed_targets} -> {:error, failed_targets}
      end
    after
      restore_multipart_cleanup_evidence(previous)
    end
  end

  @doc false
  @spec delete_cleanup_request_keys(pos_integer(), [String.t()], keyword()) ::
          :ok | {:deferred, pos_integer()} | {:error, [String.t()]}
  def delete_cleanup_request_keys(cleanup_request_id, cleanup_targets, opts \\ [])

  def delete_cleanup_request_keys(cleanup_request_id, cleanup_targets, opts)
      when is_integer(cleanup_request_id) and cleanup_request_id > 0 and is_list(cleanup_targets) and is_list(opts) do
    delete_fun = Keyword.get(opts, :delete_fun, &delete_storage_keys_with_evidence/1)
    inventory_fun = Keyword.get(opts, :inventory_fun, &Storage.incomplete_multipart_upload_count/1)
    consume? = Keyword.get(opts, :consume?, false) == true

    if Keyword.keyword?(opts) and Enum.all?(Keyword.keys(opts), &(&1 in [:consume?, :delete_fun, :inventory_fun])) and
         is_function(delete_fun, 1) and is_function(inventory_fun, 1) do
      do_delete_cleanup_request_keys(cleanup_request_id, cleanup_targets, delete_fun, inventory_fun, consume?)
    else
      {:error, cleanup_targets}
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

  defp do_delete_cleanup_request_keys(cleanup_request_id, cleanup_targets, delete_fun, inventory_fun, consume?) do
    with {:ok, request} <- load_cleanup_request(cleanup_request_id),
         {:ok, cleanup_targets} <- validate_cleanup_request_targets(request, cleanup_targets) do
      dispatch_cleanup_request(request, cleanup_targets, delete_fun, inventory_fun, consume?)
    else
      {:error, _reason} -> {:error, cleanup_targets}
    end
  end

  defp dispatch_cleanup_request(request, cleanup_targets, delete_fun, inventory_fun, consume?) do
    case multipart_cleanup_keys(request.storage_keys) do
      [] ->
        normalize_cleanup_delete(call_multipart_delete(delete_fun, cleanup_targets))

      multipart_keys ->
        process_multipart_cleanup(
          request,
          cleanup_targets,
          multipart_keys,
          delete_fun,
          inventory_fun,
          consume?
        )
    end
  end

  defp normalize_cleanup_delete({:ok, _evidence}), do: :ok
  defp normalize_cleanup_delete({:error, failed_targets}), do: {:error, failed_targets}

  defp load_cleanup_request(cleanup_request_id) do
    case Repo.get(StorageCleanupRequest, cleanup_request_id) do
      %StorageCleanupRequest{} = request -> {:ok, request}
      nil -> {:error, :storage_cleanup_request_not_found}
    end
  end

  defp validate_cleanup_request_targets(request, cleanup_targets) do
    cleanup_targets = cleanup_targets |> Enum.filter(&valid_cleanup_target?/1) |> Enum.uniq()
    owned_targets = MapSet.new(request.storage_keys)

    cond do
      cleanup_targets == [] ->
        {:error, :empty_storage_cleanup_batch}

      not Enum.all?(cleanup_targets, &MapSet.member?(owned_targets, &1)) ->
        {:error, :storage_cleanup_batch_not_owned}

      not MapSet.subset?(
        request.storage_keys |> multipart_cleanup_keys() |> MapSet.new(),
        cleanup_targets |> multipart_cleanup_keys() |> MapSet.new()
      ) ->
        {:error, :multipart_cleanup_batch_incomplete}

      true ->
        {:ok, cleanup_targets}
    end
  end

  defp multipart_cleanup_keys(cleanup_targets) do
    cleanup_targets
    |> Enum.map(&cleanup_target_storage_key/1)
    |> Enum.filter(&Storage.multipart_cleanup_key?/1)
    |> Enum.uniq()
  end

  defp process_multipart_cleanup(request, cleanup_targets, multipart_keys, delete_fun, inventory_fun, consume?) do
    case cleanup_quiescence_state(request.id) do
      {:ok, :first_pass} ->
        run_first_multipart_cleanup(request.id, cleanup_targets, delete_fun)

      {:ok, {:deferred, seconds}} ->
        {:deferred, seconds}

      {:ok, {:verify, started_at, not_before}} ->
        verify_multipart_quiescence(
          request.id,
          cleanup_targets,
          multipart_keys,
          started_at,
          not_before,
          delete_fun,
          inventory_fun,
          consume?
        )

      {:error, _reason} ->
        {:error, cleanup_targets}
    end
  end

  defp run_first_multipart_cleanup(cleanup_request_id, cleanup_targets, delete_fun) do
    case call_multipart_delete(delete_fun, cleanup_targets) do
      {:ok, _evidence} -> reset_multipart_quiescence_window(cleanup_request_id, nil, nil, cleanup_targets)
      {:error, _failed_targets} -> {:error, cleanup_targets}
    end
  end

  defp verify_multipart_quiescence(
         cleanup_request_id,
         cleanup_targets,
         multipart_keys,
         started_at,
         not_before,
         delete_fun,
         inventory_fun,
         consume?
       ) do
    case exact_multipart_inventory(multipart_keys, inventory_fun) do
      {:ok, :empty} ->
        finish_empty_multipart_inventory(
          cleanup_request_id,
          cleanup_targets,
          started_at,
          not_before,
          delete_fun,
          consume?
        )

      {:ok, :present} ->
        clean_late_multipart_inventory(
          cleanup_request_id,
          cleanup_targets,
          started_at,
          not_before,
          delete_fun
        )

      {:error, _reason} ->
        {:error, cleanup_targets}
    end
  end

  defp exact_multipart_inventory(multipart_keys, inventory_fun) do
    Enum.reduce_while(multipart_keys, {:ok, :empty}, fn storage_key, {:ok, state} ->
      storage_key
      |> inventory_fun.()
      |> reduce_multipart_inventory(state)
    end)
  rescue
    error -> {:error, {:multipart_inventory_exception, error.__struct__}}
  catch
    kind, _reason -> {:error, {:multipart_inventory_failure, kind}}
  end

  defp reduce_multipart_inventory({:ok, count}, state) when is_integer(count) and count >= 0 do
    next_state = if count > 0, do: :present, else: state
    {:cont, {:ok, next_state}}
  end

  defp reduce_multipart_inventory({:error, reason}, _state), do: {:halt, {:error, reason}}

  defp reduce_multipart_inventory(_invalid, _state), do: {:halt, {:error, :invalid_multipart_inventory_result}}

  defp call_multipart_delete(delete_fun, cleanup_targets) do
    case delete_fun.(cleanup_targets) do
      :ok ->
        {:ok, %{aborted_count: 0}}

      {:ok, %{aborted_count: aborted_count}} when is_integer(aborted_count) and aborted_count >= 0 ->
        {:ok, %{aborted_count: aborted_count}}

      {:error, failed_targets} when is_list(failed_targets) ->
        {:error, normalize_failed_keys(failed_targets, cleanup_targets)}

      _invalid ->
        {:error, cleanup_targets}
    end
  rescue
    error ->
      Logger.error("Durable multipart object deletion raised error=#{safe_error(error)}")
      {:error, cleanup_targets}
  catch
    kind, reason ->
      Logger.error("Durable multipart object deletion failed error=#{safe_error({kind, reason})}")
      {:error, cleanup_targets}
  end

  defp finish_empty_multipart_inventory(cleanup_request_id, cleanup_targets, started_at, not_before, delete_fun, consume?) do
    case call_multipart_delete(delete_fun, cleanup_targets) do
      {:ok, %{aborted_count: 0}} ->
        confirm_multipart_quiescence(
          cleanup_request_id,
          started_at,
          not_before,
          cleanup_targets,
          consume?
        )

      {:ok, %{aborted_count: _positive_count}} ->
        reset_multipart_quiescence_window(
          cleanup_request_id,
          started_at,
          not_before,
          cleanup_targets
        )

      {:error, _failed_targets} ->
        {:error, cleanup_targets}
    end
  end

  defp clean_late_multipart_inventory(cleanup_request_id, cleanup_targets, started_at, not_before, delete_fun) do
    case call_multipart_delete(delete_fun, cleanup_targets) do
      {:ok, _evidence} ->
        reset_multipart_quiescence_window(
          cleanup_request_id,
          started_at,
          not_before,
          cleanup_targets
        )

      {:error, _failed_targets} ->
        {:error, cleanup_targets}
    end
  end

  defp cleanup_quiescence_state(cleanup_request_id) do
    Repo.transact(fn ->
      case lock_cleanup_request(cleanup_request_id) do
        %StorageCleanupRequest{} = request ->
          now = database_clock_now()
          {:ok, request_quiescence_state(request, now)}

        nil ->
          {:error, :storage_cleanup_request_not_found}
      end
    end)
  end

  defp request_quiescence_state(
         %StorageCleanupRequest{multipart_quiescence_started_at: nil, multipart_quiescence_not_before: nil},
         _now
       ), do: :first_pass

  defp request_quiescence_state(
         %StorageCleanupRequest{
           multipart_quiescence_started_at: %DateTime{} = started_at,
           multipart_quiescence_not_before: %DateTime{} = not_before
         },
         now
       ) do
    if DateTime.after?(not_before, now),
      do: {:deferred, seconds_until(not_before, now)},
      else: {:verify, started_at, not_before}
  end

  defp request_quiescence_state(_request, _now), do: {:invalid, :multipart_quiescence_shape}

  defp reset_multipart_quiescence_window(cleanup_request_id, expected_started_at, expected_not_before, cleanup_targets) do
    fn ->
      reset_locked_multipart_quiescence(cleanup_request_id, expected_started_at, expected_not_before)
    end
    |> Repo.transact()
    |> normalize_quiescence_result(cleanup_targets)
  end

  defp reset_locked_multipart_quiescence(cleanup_request_id, expected_started_at, expected_not_before) do
    case lock_cleanup_request(cleanup_request_id) do
      %StorageCleanupRequest{} = request ->
        maybe_reset_multipart_quiescence(request, expected_started_at, expected_not_before)

      nil ->
        {:error, :storage_cleanup_request_not_found}
    end
  end

  defp maybe_reset_multipart_quiescence(request, expected_started_at, expected_not_before) do
    now = database_clock_now()

    if quiescence_matches?(request, expected_started_at, expected_not_before),
      do: persist_reset_multipart_quiescence(request, now),
      else: defer_from_concurrent_quiescence(request, now)
  end

  defp persist_reset_multipart_quiescence(request, now) do
    not_before = DateTime.add(now, Storage.multipart_cleanup_quiescence_seconds(), :second)

    request
    |> StorageCleanupRequest.multipart_quiescence_changeset(now, not_before)
    |> Repo.update()
    |> case do
      {:ok, _request} -> {:ok, {:deferred, seconds_until(not_before, now)}}
      {:error, _changeset} -> {:error, :multipart_quiescence_not_persisted}
    end
  end

  defp confirm_multipart_quiescence(cleanup_request_id, started_at, not_before, cleanup_targets, consume?) do
    fn ->
      confirm_locked_multipart_quiescence(cleanup_request_id, started_at, not_before, consume?)
    end
    |> Repo.transact()
    |> normalize_confirm_quiescence(cleanup_targets)
  end

  defp confirm_locked_multipart_quiescence(cleanup_request_id, started_at, not_before, consume?) do
    case lock_cleanup_request(cleanup_request_id) do
      %StorageCleanupRequest{} = request ->
        decide_multipart_quiescence_confirmation(request, started_at, not_before, consume?)

      nil ->
        {:error, :storage_cleanup_request_not_found}
    end
  end

  defp decide_multipart_quiescence_confirmation(request, started_at, not_before, consume?) do
    now = database_clock_now()

    cond do
      not quiescence_matches?(request, started_at, not_before) ->
        defer_from_concurrent_quiescence(request, now)

      DateTime.after?(not_before, now) ->
        {:ok, {:deferred, seconds_until(not_before, now)}}

      consume? and request.owner_kind == "storage_compensation" ->
        consume_multipart_cleanup_receipt(request)

      consume? ->
        {:error, :multipart_cleanup_receipt_not_consumable}

      true ->
        {:ok, :confirmed}
    end
  end

  defp consume_multipart_cleanup_receipt(request) do
    case Repo.delete(request) do
      {:ok, _request} -> {:ok, :confirmed}
      {:error, _changeset} -> {:error, :multipart_cleanup_receipt_not_consumed}
    end
  end

  defp normalize_confirm_quiescence({:ok, :confirmed}, _cleanup_targets), do: :ok

  defp normalize_confirm_quiescence({:ok, {:deferred, seconds}}, _cleanup_targets), do: {:deferred, seconds}

  defp normalize_confirm_quiescence({:error, _reason}, cleanup_targets), do: {:error, cleanup_targets}

  defp lock_cleanup_request(cleanup_request_id) do
    Repo.one(
      from(request in StorageCleanupRequest,
        where: request.id == ^cleanup_request_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp quiescence_matches?(request, expected_started_at, expected_not_before) do
    request.multipart_quiescence_started_at == expected_started_at and
      request.multipart_quiescence_not_before == expected_not_before
  end

  defp defer_from_concurrent_quiescence(request, now) do
    case request_quiescence_state(request, now) do
      {:deferred, seconds} -> {:ok, {:deferred, seconds}}
      {:verify, _started_at, _not_before} -> {:ok, {:deferred, 1}}
      :first_pass -> {:error, :multipart_quiescence_changed}
      {:invalid, reason} -> {:error, reason}
    end
  end

  defp database_clock_now do
    %Postgrex.Result{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    DateTime.truncate(now, :second)
  end

  defp seconds_until(not_before, now), do: max(DateTime.diff(not_before, now, :second), 1)

  defp normalize_quiescence_result({:ok, {:deferred, seconds}}, _cleanup_targets), do: {:deferred, seconds}

  defp normalize_quiescence_result({:error, _reason}, cleanup_targets), do: {:error, cleanup_targets}

  @spec enqueue_cleanup([String.t()], keyword()) :: :ok | {:error, term()}
  def enqueue_cleanup(cleanup_targets, opts \\ []) when is_list(cleanup_targets) do
    cleanup_targets = cleanup_targets |> Enum.filter(&valid_cleanup_target?/1) |> Enum.uniq()
    insert_fun = Keyword.get(opts, :insert_fun, &insert_cleanup_job/1)
    attempts = Keyword.get(opts, :attempts, @enqueue_attempts)
    retry_delay_ms = Keyword.get(opts, :retry_delay_ms, @enqueue_retry_delay_ms)

    case cleanup_targets do
      [] ->
        :ok

      cleanup_targets ->
        enqueue_with_retry(cleanup_targets, insert_fun, attempts, retry_delay_ms)
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

  defp insert_cleanup_job(storage_keys) do
    storage_keys
    |> then(&%{"storage_keys" => &1})
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
    cleanup_targets = cleanup_targets |> Enum.filter(&valid_cleanup_target?/1) |> Enum.uniq()

    case cleanup_targets do
      [] -> {:error, :no_valid_storage_keys}
      cleanup_targets -> insert_cleanup_request(cleanup_targets, %{}, :fallback)
    end
  end

  @doc "Persists a planned storage cleanup handoff without reporting a fallback."
  @spec persist_planned_cleanup_request([String.t()]) ::
          {:ok, StorageCleanupRequest.t()} | {:error, term()}
  def persist_planned_cleanup_request(cleanup_targets) when is_list(cleanup_targets) do
    cleanup_targets = cleanup_targets |> Enum.filter(&valid_cleanup_target?/1) |> Enum.uniq()

    case cleanup_targets do
      [] -> {:error, :no_valid_storage_keys}
      cleanup_targets -> insert_cleanup_request(cleanup_targets, %{}, :planned_handoff)
    end
  end

  @doc false
  @spec persist_snapshot_lifecycle_cleanup([String.t()], Ecto.UUID.t(), String.t()) ::
          {:ok, StorageCleanupRequest.t()} | {:error, term()}
  def persist_snapshot_lifecycle_cleanup(cleanup_targets, owner_token, provider_namespace_fingerprint)
      when is_list(cleanup_targets) and is_binary(owner_token) and is_binary(provider_namespace_fingerprint) do
    cleanup_targets = cleanup_targets |> Enum.filter(&valid_cleanup_target?/1) |> Enum.uniq()

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
    attrs = Map.put(attrs, :storage_keys, storage_keys)

    case %StorageCleanupRequest{} |> StorageCleanupRequest.changeset(attrs) |> Repo.insert() do
      {:ok, cleanup_request} = success ->
        report_cleanup_request_persisted(cleanup_request, storage_keys, persistence_kind)

        success

      {:error, _changeset} = error ->
        error
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

  defp safe_deferred_storage_delete(cleanup_target) do
    storage_key = cleanup_target_storage_key(cleanup_target)
    force_delete? = force_delete_target?(cleanup_target)

    StorageKeyLock.with_storage_key_lock(storage_key, fn ->
      deferred_storage_delete(storage_key, force_delete?)
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
    if committed_asset_key?(storage_key),
      do: retain_committed_asset(storage_key),
      else: delete_storage_object(storage_key)
  end

  defp deferred_storage_delete(storage_key, force_delete?) do
    cond do
      committed_asset_key?(storage_key) ->
        retain_committed_asset(storage_key)

      committed_template_storage_key?(storage_key) ->
        retain_committed_template_storage(storage_key)

      committed_snapshot_storage_key?(storage_key) ->
        retain_committed_snapshot_storage(storage_key)

      force_delete? ->
        delete_if_still_invalid(storage_key)

      match?({:ok, _project_id}, StorageKeyLock.project_blob_id(storage_key)) ->
        {:ok, project_id} = StorageKeyLock.project_blob_id(storage_key)

        if Repo.exists?(from project in Project, where: project.id == ^project_id),
          do: retain_committed_project_blob(project_id),
          else: delete_storage_object(storage_key)

      true ->
        delete_storage_object(storage_key)
    end
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
  # boundary. Compensation reaches the adapter only after validating the key,
  # fencing it with `StorageKeyLock`, and proving that no committed owner must
  # retain it.
  defp delete_storage_object(storage_key) do
    with {:ok, aborted_count} <- Storage.abort_incomplete_multipart_uploads(storage_key),
         :ok <- Storage.adapter().delete(storage_key) do
      record_multipart_cleanup_evidence(aborted_count)
      report_aborted_multipart_uploads(aborted_count)
      :ok
    end
  end

  defp record_multipart_cleanup_evidence(aborted_count) when is_integer(aborted_count) and aborted_count >= 0 do
    case Process.get(@multipart_cleanup_evidence_key, :not_collecting) do
      count when is_integer(count) and count >= 0 ->
        Process.put(@multipart_cleanup_evidence_key, count + aborted_count)
        :ok

      :not_collecting ->
        :ok
    end
  end

  defp restore_multipart_cleanup_evidence(:not_collecting), do: Process.delete(@multipart_cleanup_evidence_key)

  defp restore_multipart_cleanup_evidence(previous), do: Process.put(@multipart_cleanup_evidence_key, previous)

  defp report_aborted_multipart_uploads(0), do: :ok

  defp report_aborted_multipart_uploads(count) when is_integer(count) and count > 0 do
    :telemetry.execute(
      [:storyarn, :assets, :storage_compensation, :multipart_aborted],
      %{count: count},
      %{}
    )
  end

  defp committed_asset_key?(storage_key) do
    Repo.exists?(from asset in Asset, where: asset.key == ^storage_key)
  end

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
         snapshot_archive_storage_key?(storage_key) or storage_reservation_key?(storage_key))
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
          kind in @storage_reservation_kinds and
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
