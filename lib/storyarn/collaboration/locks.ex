defmodule Storyarn.Collaboration.Locks do
  @moduledoc """
  GenServer-based entity locking system.

  Uses ETS for fast reads with auto-expiration. Keys are `{scope, entity_id}`
  where scope is an editor_scope tuple like `{:flow, 1}` or `{:sheet, 5}`.

  Scope is always an editor_scope tuple like `{:flow, 1}` or `{:sheet, 5}`.
  """

  use GenServer

  require Logger

  @table_name :storyarn_node_locks
  @lock_timeout_ms 30_000
  @cleanup_interval_ms 10_000

  @type lock_info :: %{
          user_id: integer(),
          user_email: String.t(),
          user_color: String.t(),
          locked_at: integer(),
          expires_at: integer()
        }

  # =============================================================================
  # Client API
  # =============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Attempts to acquire a lock on an entity.
  Returns {:ok, lock_info} if successful, {:error, :already_locked, lock_info} if locked by another user.
  """
  def acquire(scope, entity_id, user) do
    GenServer.call(__MODULE__, {:acquire, scope, entity_id, user})
  end

  @doc """
  Releases a lock on an entity. Only the lock holder can release.
  """
  def release(scope, entity_id, user_id) do
    GenServer.call(__MODULE__, {:release, scope, entity_id, user_id})
  end

  @doc """
  Releases all locks held by a user in a scope.
  Called when user disconnects.
  """
  def release_all(scope, user_id) do
    GenServer.call(__MODULE__, {:release_all, scope, user_id})
  end

  @doc """
  Refreshes the lock timeout (heartbeat).
  """
  def refresh(scope, entity_id, user_id) do
    GenServer.call(__MODULE__, {:refresh, scope, entity_id, user_id})
  end

  @doc """
  Gets the current lock holder for an entity, if any.
  """
  def get_lock(scope, entity_id) do
    GenServer.call(__MODULE__, {:get_lock, scope, entity_id})
  end

  @doc """
  Gets all locks for a scope.
  """
  def list_locks(scope) do
    GenServer.call(__MODULE__, {:list_locks, scope})
  end

  @doc """
  Checks if an entity is locked by a different user.
  """
  def locked_by_other?(scope, entity_id, user_id) do
    case get_lock(scope, entity_id) do
      {:ok, %{user_id: lock_user_id}} -> lock_user_id != user_id
      {:error, :not_locked} -> false
    end
  end

  @doc """
  Clears all locks. For testing purposes only.
  """
  @spec clear_all() :: :ok
  def clear_all do
    GenServer.call(__MODULE__, :clear_all)
  end

  # =============================================================================
  # Server callbacks
  # =============================================================================

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:acquire, scope, entity_id, user}, _from, state) do
    key = {scope, entity_id}
    now = System.monotonic_time(:millisecond)
    expires_at = now + @lock_timeout_ms

    result =
      case :ets.lookup(@table_name, key) do
        [{^key, lock_info}] ->
          try_acquire_existing(key, lock_info, user, now, expires_at)

        [] ->
          acquire_new_lock(key, user, now, expires_at)
      end

    {:reply, result, state}
  end

  def handle_call({:release, scope, entity_id, user_id}, _from, state) do
    key = {scope, entity_id}

    case :ets.lookup(@table_name, key) do
      [{^key, %{user_id: ^user_id}}] ->
        :ets.delete(@table_name, key)
        {:reply, :ok, state}

      [{^key, _lock_info}] ->
        {:reply, {:error, :not_lock_holder}, state}

      [] ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:release_all, scope, user_id}, _from, state) do
    :ets.foldl(
      fn
        {{^scope, _entity_id} = key, %{user_id: ^user_id}}, _acc ->
          :ets.delete(@table_name, key)

        _, acc ->
          acc
      end,
      nil,
      @table_name
    )

    {:reply, :ok, state}
  end

  def handle_call({:refresh, scope, entity_id, user_id}, _from, state) do
    key = {scope, entity_id}
    now = System.monotonic_time(:millisecond)
    expires_at = now + @lock_timeout_ms

    case :ets.lookup(@table_name, key) do
      [{^key, %{user_id: ^user_id} = lock_info}] ->
        updated_lock = %{lock_info | expires_at: expires_at}
        :ets.insert(@table_name, {key, updated_lock})
        {:reply, :ok, state}

      [{^key, _lock_info}] ->
        {:reply, {:error, :not_lock_holder}, state}

      [] ->
        {:reply, {:error, :not_lock_holder}, state}
    end
  end

  def handle_call({:get_lock, scope, entity_id}, _from, state) do
    key = {scope, entity_id}
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table_name, key) do
      [{^key, lock_info}] ->
        if lock_info.expires_at > now do
          {:reply, {:ok, lock_info}, state}
        else
          :ets.delete(@table_name, key)
          {:reply, {:error, :not_locked}, state}
        end

      [] ->
        {:reply, {:error, :not_locked}, state}
    end
  end

  def handle_call({:list_locks, scope}, _from, state) do
    now = System.monotonic_time(:millisecond)

    locks =
      :ets.foldl(
        fn
          {{^scope, entity_id}, lock_info}, acc ->
            if lock_info.expires_at > now do
              Map.put(acc, entity_id, lock_info)
            else
              acc
            end

          _, acc ->
            acc
        end,
        %{},
        @table_name
      )

    {:reply, locks, state}
  end

  def handle_call(:clear_all, _from, state) do
    :ets.delete_all_objects(@table_name)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    now = System.monotonic_time(:millisecond)
    expired_count = cleanup_expired_locks(now)

    if expired_count > 0 do
      Logger.debug("Cleaned up #{expired_count} expired entity locks")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  # =============================================================================
  # Private functions
  # =============================================================================

  defp try_acquire_existing(key, lock_info, user, now, expires_at) do
    cond do
      lock_info.expires_at <= now ->
        acquire_new_lock(key, user, now, expires_at)

      lock_info.user_id == user.id ->
        updated_lock = %{lock_info | expires_at: expires_at}
        :ets.insert(@table_name, {key, updated_lock})
        {:ok, updated_lock}

      true ->
        {:error, :already_locked, lock_info}
    end
  end

  defp acquire_new_lock(key, user, now, expires_at) do
    lock_info = create_lock_info(user, now, expires_at)
    :ets.insert(@table_name, {key, lock_info})
    {:ok, lock_info}
  end

  defp create_lock_info(user, locked_at, expires_at) do
    %{
      user_id: user.id,
      user_email: user.email,
      user_color: Storyarn.Collaboration.Colors.for_user(user.id),
      locked_at: locked_at,
      expires_at: expires_at
    }
  end

  defp cleanup_expired_locks(now) do
    expired =
      :ets.foldl(
        fn {key, lock_info}, acc ->
          if lock_info.expires_at <= now do
            :ets.delete(@table_name, key)
            [{key, lock_info} | acc]
          else
            acc
          end
        end,
        [],
        @table_name
      )

    # Notify subscribers about expired locks
    # Uses PubSub directly to avoid circular dependency with Collaboration facade
    for {{scope, entity_id}, lock_info} <- expired do
      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        "#{elem(scope, 0)}:#{elem(scope, 1)}:locks",
        {:lock_change, :lock_expired,
         %{
           entity_id: entity_id,
           user_id: lock_info.user_id,
           user_email: lock_info.user_email
         }}
      )
    end

    length(expired)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired, @cleanup_interval_ms)
  end
end
