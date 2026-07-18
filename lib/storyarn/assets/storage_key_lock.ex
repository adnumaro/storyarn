defmodule Storyarn.Assets.StorageKeyLock do
  @moduledoc false

  alias Storyarn.Repo

  @lock_namespace 731_001
  @session_lock_namespace 731_002
  @max_lock_key 2_147_483_647
  @max_project_id 9_223_372_036_854_775_807
  @acquisition_timeout to_timeout(minute: 5)
  @lock_retry_delay_ms 25
  @temporary_copy_marker ".storyarn-copy-"

  @spec with_project_blob_lock(String.t(), (-> result)) :: result when result: term()
  def with_project_blob_lock(storage_key, fun) when is_binary(storage_key) and is_function(fun, 0) do
    with_project_blob_lock(storage_key, fun, [])
  end

  @doc false
  @spec with_project_blob_lock(String.t(), (-> result), keyword()) :: result when result: term()
  def with_project_blob_lock(storage_key, fun, opts)
      when is_binary(storage_key) and is_function(fun, 0) and is_list(opts) do
    case project_blob_id(storage_key) do
      {:ok, _project_id} ->
        with_storage_key_lock(storage_key, fun, opts)

      :error ->
        fun.()
    end
  end

  @doc """
  Serializes a storage mutation with the database transaction that adopts the
  same key.

  In particular, this fences ambiguous commit outcomes: compensating cleanup
  cannot inspect and delete a unique asset key until PostgreSQL has completed
  the writer's commit or rollback.
  """
  @spec with_storage_key_lock(String.t(), (-> result)) :: result when result: term()
  def with_storage_key_lock(storage_key, fun) when is_binary(storage_key) and is_function(fun, 0) do
    with_storage_key_lock(storage_key, fun, [])
  end

  @doc false
  @spec with_storage_key_lock(String.t(), (-> result), keyword()) :: result when result: term()
  def with_storage_key_lock(storage_key, fun, opts)
      when is_binary(storage_key) and is_function(fun, 0) and is_list(opts) do
    deadline = acquisition_deadline(opts)

    if Repo.in_transaction?() do
      acquire_transaction_lock_and_run(storage_key, fun, deadline)
    else
      acquire_and_run(storage_key, fun, deadline)
    end
  end

  @doc """
  Serializes a longer workflow without wrapping the callback in a database
  transaction.

  A PostgreSQL session advisory lock is held on one checked-out connection,
  while contending callers poll without occupying pool connections. This is
  suitable for at-least-once workers that need multiple independently
  committed transactions under one idempotency fence.
  """
  @spec with_session_lock(String.t(), (-> result)) :: result when result: term()
  def with_session_lock(lock_name, fun) when is_binary(lock_name) and is_function(fun, 0) do
    with_session_lock(lock_name, fun, [])
  end

  @doc false
  @spec with_session_lock(String.t(), (-> result), keyword()) :: result when result: term()
  def with_session_lock(lock_name, fun, opts) when is_binary(lock_name) and is_function(fun, 0) and is_list(opts) do
    deadline = acquisition_deadline(opts)
    acquire_session_lock_and_run(lock_name, fun, deadline)
  end

  @spec project_blob_id(String.t()) :: {:ok, pos_integer()} | :error
  def project_blob_id(storage_key) when is_binary(storage_key) do
    case project_blob_identity(storage_key) do
      {:ok, project_id, _hash} -> {:ok, project_id}
      :error -> :error
    end
  end

  @spec project_blob_identity(String.t()) ::
          {:ok, pos_integer(), String.t()} | :error
  def project_blob_identity(storage_key) when is_binary(storage_key) do
    case Regex.run(
           ~r|\Aprojects/([1-9]\d*)/blobs/([0-9a-f]{64})\.([^/]+)\z|,
           storage_key,
           capture: :all_but_first
         ) do
      [project_id, hash, extension] ->
        parse_project_blob_identity(project_id, hash, extension)

      _match ->
        :error
    end
  end

  defp parse_project_blob_identity(project_id, hash, extension) do
    with false <- String.contains?(extension, @temporary_copy_marker),
         {project_id, ""} when project_id > 0 and project_id <= @max_project_id <-
           Integer.parse(project_id) do
      {:ok, project_id, hash}
    else
      _invalid -> :error
    end
  end

  defp acquire_and_run(storage_key, fun, deadline) do
    case transaction_lock_attempt(storage_key, fun) do
      :checkout_unavailable ->
        retry_lock(storage_key, fun, deadline)

      result ->
        handle_transaction_lock_result(result, storage_key, fun, deadline)
    end
  end

  defp transaction_lock_attempt(storage_key, fun) do
    attempt_ref = make_ref()

    try do
      Repo.checkout(
        fn ->
          Process.put(attempt_ref, :connection_checked_out)

          Repo.transaction(
            fn ->
              if try_lock!(storage_key) do
                Process.put(attempt_ref, :callback_started)
                {:lock_acquired, rollback_callback_error(fun.())}
              else
                :lock_busy
              end
            end,
            timeout: :infinity
          )
        end,
        # Never queue with an infinite checkout deadline. An unavailable pool
        # is retried only until the acquisition deadline, while a successful
        # checkout has no deadline that could release the transaction lock in
        # the middle of a long storage callback.
        queue: false,
        timeout: :infinity
      )
    rescue
      error in DBConnection.ConnectionError ->
        if Process.get(attempt_ref) == :callback_started do
          reraise error, __STACKTRACE__
        else
          :checkout_unavailable
        end
    after
      Process.delete(attempt_ref)
    end
  end

  defp handle_transaction_lock_result({:ok, {:lock_acquired, callback_result}}, _storage_key, _fun, _deadline),
    do: callback_result

  defp handle_transaction_lock_result({:ok, :lock_busy}, storage_key, fun, deadline),
    do: retry_lock(storage_key, fun, deadline)

  defp handle_transaction_lock_result(
         {:error, {:storage_key_callback_error, callback_result}},
         _storage_key,
         _fun,
         _deadline
       ), do: callback_result

  defp handle_transaction_lock_result({:error, reason}, _storage_key, _fun, _deadline), do: {:error, reason}

  defp acquire_transaction_lock_and_run(storage_key, fun, deadline) do
    if try_lock!(storage_key) do
      fun.()
    else
      retry_transaction_lock(storage_key, fun, deadline)
    end
  end

  defp retry_transaction_lock(storage_key, fun, deadline) do
    if System.monotonic_time(:millisecond) < deadline do
      Process.sleep(@lock_retry_delay_ms)
      acquire_transaction_lock_and_run(storage_key, fun, deadline)
    else
      Repo.rollback(:storage_key_lock_timeout)
    end
  end

  defp retry_lock(storage_key, fun, deadline) do
    if System.monotonic_time(:millisecond) < deadline do
      Process.sleep(@lock_retry_delay_ms)
      acquire_and_run(storage_key, fun, deadline)
    else
      {:error, :storage_key_lock_timeout}
    end
  end

  defp try_lock!(storage_key) do
    case Repo.query!("SELECT pg_try_advisory_xact_lock($1, $2)", [
           @lock_namespace,
           lock_key(storage_key)
         ]) do
      %{rows: [[acquired?]]} when is_boolean(acquired?) -> acquired?
    end
  end

  defp lock_key(storage_key), do: :erlang.phash2(storage_key, @max_lock_key)

  defp acquire_session_lock_and_run(lock_name, fun, deadline) do
    case session_lock_attempt(lock_name, fun) do
      :checkout_unavailable ->
        retry_session_lock(lock_name, fun, deadline)

      {:lock_acquired, callback_result} ->
        callback_result

      :lock_busy ->
        retry_session_lock(lock_name, fun, deadline)
    end
  end

  defp session_lock_attempt(lock_name, fun) do
    attempt_ref = make_ref()

    try do
      Repo.checkout(
        fn ->
          Process.put(attempt_ref, :connection_checked_out)

          if try_session_lock!(lock_name) do
            try do
              Process.put(attempt_ref, :callback_started)
              {:lock_acquired, fun.()}
            after
              unlock_session!(lock_name)
            end
          else
            :lock_busy
          end
        end,
        # See acquire_and_run/3: checkout itself is non-blocking, then the
        # successful owner is allowed to keep the session for the whole
        # callback without a DBConnection deadline.
        queue: false,
        timeout: :infinity
      )
    rescue
      error in DBConnection.ConnectionError ->
        if Process.get(attempt_ref) == :callback_started do
          reraise error, __STACKTRACE__
        else
          :checkout_unavailable
        end
    after
      Process.delete(attempt_ref)
    end
  end

  defp retry_session_lock(lock_name, fun, deadline) do
    if System.monotonic_time(:millisecond) < deadline do
      Process.sleep(@lock_retry_delay_ms)
      acquire_session_lock_and_run(lock_name, fun, deadline)
    else
      {:error, :session_lock_timeout}
    end
  end

  defp try_session_lock!(lock_name) do
    case Repo.query!("SELECT pg_try_advisory_lock($1, $2)", [
           @session_lock_namespace,
           lock_key(lock_name)
         ]) do
      %{rows: [[acquired?]]} when is_boolean(acquired?) -> acquired?
    end
  end

  defp unlock_session!(lock_name) do
    case Repo.query!("SELECT pg_advisory_unlock($1, $2)", [
           @session_lock_namespace,
           lock_key(lock_name)
         ]) do
      %{rows: [[true]]} -> :ok
      %{rows: [[false]]} -> raise "session advisory lock was not held"
    end
  end

  defp acquisition_deadline(opts) do
    case Keyword.get(opts, :acquisition_timeout, @acquisition_timeout) do
      timeout when is_integer(timeout) and timeout >= 0 ->
        System.monotonic_time(:millisecond) + timeout

      invalid_timeout ->
        raise ArgumentError,
              ":acquisition_timeout must be a non-negative integer, got: #{inspect(invalid_timeout)}"
    end
  end

  defp rollback_callback_error(result) when is_tuple(result) and tuple_size(result) > 0 and elem(result, 0) == :error do
    Repo.rollback({:storage_key_callback_error, result})
  end

  defp rollback_callback_error(result), do: result
end
