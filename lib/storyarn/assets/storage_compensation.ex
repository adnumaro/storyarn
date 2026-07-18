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

  @spec retry_persisted_cleanup_requests(pos_integer()) :: :ok | {:error, non_neg_integer()}
  def retry_persisted_cleanup_requests(limit \\ @persisted_cleanup_batch_size) when is_integer(limit) and limit > 0 do
    cleanup_requests =
      StorageCleanupRequest
      |> order_by([request], asc: request.inserted_at, asc: request.id)
      |> limit(^limit)
      |> Repo.all()

    failed_count = Enum.count(cleanup_requests, &(retry_persisted_cleanup_request(&1) == :error))

    :telemetry.execute(
      [:storyarn, :assets, :storage_compensation, :persisted_retry],
      %{count: length(cleanup_requests), failed_count: failed_count},
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
              enqueue_reason,
              persistence_reason,
              delete_fun
            )
        end
    end
  end

  defp handle_unpersisted_cleanup(reference, storage_keys, enqueue_reason, persistence_reason, delete_fun) do
    case call_delete(delete_fun, storage_keys) do
      :ok ->
        discard(reference)

      {:error, failed_keys} ->
        failed_keys = failed_keys |> Enum.filter(&valid_cleanup_target?/1) |> Enum.uniq()
        discard(reference)
        report_unpersisted_cleanup(failed_keys, enqueue_reason, persistence_reason)

        {:error,
         {:storage_cleanup_not_persisted,
          %{
            failed_keys: failed_keys,
            enqueue_error: safe_error(enqueue_reason),
            persistence_error: safe_error(persistence_reason)
          }}}
    end
  end

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
      {:ok, _request} = success -> success
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
      :ok -> :ok
      {:error, failed_keys} when is_list(failed_keys) -> {:error, failed_keys}
      _result -> {:error, storage_keys}
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

  @doc "Persists storage keys for the recurring cleanup reconciler."
  @spec persist_cleanup_request([String.t()]) ::
          {:ok, StorageCleanupRequest.t()} | {:error, term()}
  def persist_cleanup_request(cleanup_targets) when is_list(cleanup_targets) do
    cleanup_targets = cleanup_targets |> Enum.filter(&valid_cleanup_target?/1) |> Enum.uniq()

    case cleanup_targets do
      [] -> {:error, :no_valid_storage_keys}
      cleanup_targets -> insert_cleanup_request(cleanup_targets)
    end
  end

  defp insert_cleanup_request(storage_keys) do
    case Repo.insert(%StorageCleanupRequest{storage_keys: storage_keys}) do
      {:ok, cleanup_request} = success ->
        Logger.warning(
          "Persisted copied asset cleanup fallback request_id=#{cleanup_request.id} storage_key_count=#{length(storage_keys)}"
        )

        :telemetry.execute(
          [:storyarn, :assets, :storage_compensation, :fallback_persisted],
          %{count: 1, storage_key_count: length(storage_keys)},
          %{request_id: cleanup_request.id}
        )

        success

      {:error, _changeset} = error ->
        error
    end
  rescue
    error ->
      Logger.error("Could not persist copied asset cleanup fallback error=#{safe_error(error)}")
      {:error, {:exception, error.__struct__}}
  catch
    kind, reason ->
      Logger.error("Could not persist copied asset cleanup fallback error=#{safe_error({kind, reason})}")
      {:error, {kind, safe_error(reason)}}
  end

  defp retry_persisted_cleanup_request(cleanup_request) do
    case delete_storage_keys(cleanup_request.storage_keys) do
      :ok ->
        cleanup_request
        |> Repo.delete()
        |> persisted_retry_result()

      {:error, failed_keys} ->
        cleanup_request
        |> rotate_persisted_cleanup_request(failed_keys)
        |> persisted_retry_result(:error)
    end
  end

  defp rotate_persisted_cleanup_request(cleanup_request, failed_keys) do
    Repo.transact(fn ->
      with {:ok, replacement} <-
             Repo.insert(%StorageCleanupRequest{storage_keys: failed_keys}),
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
      else: Storage.delete(storage_key)
  end

  defp deferred_storage_delete(storage_key, force_delete?) do
    cond do
      committed_asset_key?(storage_key) ->
        retain_committed_asset(storage_key)

      committed_template_storage_key?(storage_key) ->
        retain_committed_template_storage(storage_key)

      force_delete? ->
        delete_if_still_invalid(storage_key)

      match?({:ok, _project_id}, StorageKeyLock.project_blob_id(storage_key)) ->
        {:ok, project_id} = StorageKeyLock.project_blob_id(storage_key)

        if Repo.exists?(from project in Project, where: project.id == ^project_id),
          do: retain_committed_project_blob(project_id),
          else: Storage.delete(storage_key)

      true ->
        Storage.delete(storage_key)
    end
  end

  defp delete_if_still_invalid(storage_key) do
    case StorageKeyLock.project_blob_identity(storage_key) do
      {:ok, project_id, expected_hash} ->
        storage_key
        |> stored_object_hash()
        |> handle_force_delete_hash(storage_key, project_id, expected_hash)

      :error ->
        Storage.delete(storage_key)
    end
  end

  defp handle_force_delete_hash({:ok, expected_hash}, storage_key, project_id, expected_hash) do
    if committed_project?(project_id),
      do: retain_repaired_project_blob(project_id),
      else: Storage.delete(storage_key)
  end

  defp handle_force_delete_hash({:ok, _invalid_hash}, storage_key, _project_id, _expected_hash) do
    Storage.delete(storage_key)
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

  defp report_unpersisted_cleanup(failed_keys, enqueue_reason, persistence_reason) do
    Logger.error(
      "Copied asset cleanup could not be completed or persisted failed_count=#{length(failed_keys)} enqueue_error=#{safe_error(enqueue_reason)} persistence_error=#{safe_error(persistence_reason)}"
    )

    :telemetry.execute(
      [:storyarn, :assets, :storage_compensation, :persistence_failed],
      %{count: 1, failed_count: length(failed_keys)},
      %{
        enqueue_error: safe_error(enqueue_reason),
        persistence_error: safe_error(persistence_reason)
      }
    )
  end

  defp valid_storage_key?(storage_key) when is_binary(storage_key) do
    String.valid?(storage_key) and
      (project_storage_key?(storage_key) or template_storage_key?(storage_key))
  end

  defp valid_storage_key?(_storage_key), do: false

  @doc false
  @spec template_storage_key?(term()) :: boolean()
  def template_storage_key?(storage_key) when is_binary(storage_key) do
    match?({_, _, _}, template_storage_identity(storage_key))
  end

  def template_storage_key?(_storage_key), do: false

  defp project_storage_key?(storage_key) do
    project_blob_storage_key?(storage_key) or
      project_asset_storage_key?(storage_key) or
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

  defp parse_template_storage_identity(["project_templates", "imports", slug, suffix, filename])
       when slug not in ["", ".", ".."] and suffix not in ["", ".", ".."] and
              filename in ["snapshot.json.gz", "asset-manifest.json.gz"] do
    {:artifact, slug, suffix}
  end

  defp parse_template_storage_identity(["project_templates", "imported_blobs", slug, suffix, hash, filename])
       when slug not in ["", ".", ".."] and suffix not in ["", ".", ".."] and byte_size(hash) == 64 and
              filename not in ["", ".", ".."] do
    imported_blob_storage_identity(slug, suffix, hash)
  end

  defp parse_template_storage_identity(["project_template_publications", publication_id, filename])
       when publication_id != "" and filename not in ["", ".", ".."] do
    publication_storage_identity(publication_id, filename)
  end

  defp parse_template_storage_identity(_parts), do: :error

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
