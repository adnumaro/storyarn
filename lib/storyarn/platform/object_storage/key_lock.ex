defmodule Storyarn.Platform.ObjectStorage.KeyLock do
  @moduledoc "PostgreSQL advisory locks for policy-neutral object keys."

  alias Storyarn.Repo

  @lock_namespace 731_001
  @session_lock_namespace 731_002
  @max_lock_key 2_147_483_647
  @acquisition_timeout to_timeout(minute: 5)
  @lock_retry_delay_ms 25

  @doc """
  Serializes a storage mutation with the database transaction that adopts the
  same key.

  In particular, this fences ambiguous commit outcomes: compensating cleanup
  cannot inspect and delete a unique asset key until PostgreSQL has completed
  the writer's commit or rollback.

  When invoked inside an existing transaction, a lock-acquisition timeout is
  returned to the transaction owner. The owner must propagate or explicitly
  roll back that error; this helper never rolls back a transaction it did not
  start.
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

  @doc false
  @spec with_storage_key_locks([String.t()], (-> result), keyword()) ::
          result
          | {:error,
             :invalid_storage_key_lock_set
             | :storage_key_lock_timeout
             | :storage_key_locks_require_transaction}
        when result: term()
  def with_storage_key_locks(storage_keys, fun, opts \\ [])

  def with_storage_key_locks(storage_keys, fun, opts)
      when is_list(storage_keys) and is_function(fun, 0) and is_list(opts) do
    with {:ok, storage_keys} <- normalize_storage_keys(storage_keys),
         true <- Repo.in_transaction?() do
      acquire_transaction_locks_and_run(storage_keys, fun, acquisition_deadline(opts))
    else
      false -> {:error, :storage_key_locks_require_transaction}
      {:error, _reason} = error -> error
    end
  end

  def with_storage_key_locks(_storage_keys, _fun, _opts), do: {:error, :invalid_storage_key_lock_set}

  @doc false
  @spec wrapper_owned_transaction_lock_held?(String.t()) :: boolean()
  def wrapper_owned_transaction_lock_held?(storage_key) when is_binary(storage_key) do
    Process.get(wrapper_owned_transaction_lock_key(storage_key), 0) > 0
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

                callback_result =
                  with_wrapper_owned_transaction_lock(storage_key, fn ->
                    rollback_callback_error(fun.())
                  end)

                {:lock_acquired, callback_result}
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

  defp acquire_transaction_locks_and_run([], fun, _deadline), do: fun.()

  defp acquire_transaction_locks_and_run(storage_keys, fun, deadline) do
    lock_keys = storage_keys |> Enum.map(&lock_key/1) |> Enum.uniq() |> Enum.sort()

    case acquire_ordered_transaction_locks(lock_keys, deadline) do
      :ok -> fun.()
      :timeout -> {:error, :storage_key_lock_timeout}
    end
  end

  defp acquire_ordered_transaction_locks(lock_keys, deadline) do
    previous_statement_timeout =
      deadline
      |> remaining_acquisition_timeout()
      |> set_bounded_statement_timeout!()

    case ordered_transaction_lock_query(lock_keys, previous_statement_timeout) do
      {:ok, %{rows: [[count, _restored_timeout]]}} when count == length(lock_keys) ->
        :ok

      {:ok, result} ->
        raise "ordered storage-key lock query returned an unexpected result: #{inspect(result.rows)}"

      {:error, error} ->
        restore_statement_timeout!(previous_statement_timeout)

        if lock_acquisition_timeout?(error) do
          :timeout
        else
          raise error
        end
    end
  end

  defp ordered_transaction_lock_query(lock_keys, previous_statement_timeout) do
    Repo.query(
      """
      WITH RECURSIVE acquired(position, locked) AS (
        SELECT
          1,
          pg_advisory_xact_lock($1, ($2::integer[])[1])
        WHERE cardinality($2::integer[]) > 0

        UNION ALL

        SELECT
          acquired.position + 1,
          pg_advisory_xact_lock($1, ($2::integer[])[acquired.position + 1])
        FROM acquired
        WHERE acquired.position < cardinality($2::integer[])
      ),
      lock_count AS MATERIALIZED (
        SELECT count(*) AS count
        FROM acquired
      )
      SELECT
        lock_count.count,
        set_config('statement_timeout', $3, TRUE)
      FROM lock_count
      """,
      [@lock_namespace, lock_keys, previous_statement_timeout],
      mode: :savepoint,
      timeout: :infinity
    )
  end

  defp set_bounded_statement_timeout!(timeout_ms) do
    [[previous_timeout, current_timeout_ms]] =
      Repo.query!("""
      SELECT
        current_setting('statement_timeout'),
        settings.setting::bigint
      FROM pg_settings AS settings
      WHERE settings.name = 'statement_timeout'
      """).rows

    bounded_timeout_ms =
      if current_timeout_ms == 0,
        do: timeout_ms,
        else: min(current_timeout_ms, timeout_ms)

    Repo.query!("SELECT set_config('statement_timeout', $1, TRUE)", [Integer.to_string(bounded_timeout_ms)])
    previous_timeout
  end

  defp restore_statement_timeout!(previous_timeout) do
    Repo.query!("SELECT set_config('statement_timeout', $1, TRUE)", [previous_timeout])
  end

  defp remaining_acquisition_timeout(deadline) do
    max(deadline - System.monotonic_time(:millisecond), 1)
  end

  defp lock_acquisition_timeout?(%Postgrex.Error{postgres: %{code: code}}),
    do: code in [:lock_not_available, :query_canceled]

  defp lock_acquisition_timeout?(_error), do: false

  defp retry_transaction_lock(storage_key, fun, deadline) do
    if System.monotonic_time(:millisecond) < deadline do
      Process.sleep(@lock_retry_delay_ms)
      acquire_transaction_lock_and_run(storage_key, fun, deadline)
    else
      {:error, :storage_key_lock_timeout}
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

  defp normalize_storage_keys(storage_keys) do
    if Enum.all?(storage_keys, &(is_binary(&1) and &1 != "")) do
      {:ok, storage_keys |> Enum.uniq() |> Enum.sort()}
    else
      {:error, :invalid_storage_key_lock_set}
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

  defp with_wrapper_owned_transaction_lock(storage_key, fun) do
    marker_key = wrapper_owned_transaction_lock_key(storage_key)
    previous_count = Process.get(marker_key, 0)
    Process.put(marker_key, previous_count + 1)

    try do
      fun.()
    after
      if previous_count == 0,
        do: Process.delete(marker_key),
        else: Process.put(marker_key, previous_count)
    end
  end

  defp wrapper_owned_transaction_lock_key(storage_key) do
    {__MODULE__, :wrapper_owned_transaction_lock, storage_key}
  end
end
