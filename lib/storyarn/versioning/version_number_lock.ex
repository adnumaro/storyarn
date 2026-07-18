defmodule Storyarn.Versioning.VersionNumberLock do
  @moduledoc false

  alias Storyarn.Repo

  @entity_version_namespace 981_001
  @project_snapshot_namespace 981_002
  @max_lock_key 2_147_483_647

  @spec entity_version(String.t(), integer(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def entity_version(entity_type, entity_id, fun) when is_function(fun, 0) do
    transaction(@entity_version_namespace, {entity_type, entity_id}, fun)
  end

  @spec project_snapshot(integer(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def project_snapshot(project_id, fun) when is_function(fun, 0) do
    session_transaction(
      @project_snapshot_namespace,
      project_id,
      fun,
      isolation: :repeatable_read,
      timeout: to_timeout(minute: 5)
    )
  end

  defp transaction(namespace, key, fun) do
    Repo.transaction(fn ->
      transaction_lock!(namespace, key)

      run_transaction_fun(fun)
    end)
  end

  # The session lock must be acquired before opening the repeatable-read
  # transaction. Acquiring a transaction-scoped advisory lock from inside that
  # transaction could establish its MVCC snapshot while waiting for the
  # previous writer, causing it to miss the version that writer commits.
  defp session_transaction(namespace, key, fun, transaction_opts) do
    timeout = Keyword.fetch!(transaction_opts, :timeout)

    Repo.checkout(
      fn ->
        session_lock!(namespace, key, timeout)

        try do
          Repo.transaction(fn -> run_transaction_fun(fun) end, transaction_opts)
        after
          session_unlock!(namespace, key, timeout)
        end
      end,
      timeout: timeout
    )
  end

  defp run_transaction_fun(fun) do
    case fun.() do
      {:ok, result} -> result
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp transaction_lock!(namespace, key) do
    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [
      namespace,
      lock_key(key)
    ])

    :ok
  end

  defp session_lock!(namespace, key, timeout) do
    Repo.query!(
      "SELECT pg_advisory_lock($1, $2)",
      [namespace, lock_key(key)],
      timeout: timeout
    )

    :ok
  end

  defp session_unlock!(namespace, key, timeout) do
    %{rows: [[true]]} =
      Repo.query!(
        "SELECT pg_advisory_unlock($1, $2)",
        [namespace, lock_key(key)],
        timeout: timeout
      )

    :ok
  end

  defp lock_key(key), do: :erlang.phash2(key, @max_lock_key)
end
