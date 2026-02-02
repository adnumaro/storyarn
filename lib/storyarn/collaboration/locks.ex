defmodule Storyarn.Collaboration.Locks do
  @moduledoc false

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

  # Client API

  @doc """
  Starts the Locks GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Attempts to acquire a lock on a node.
  Returns {:ok, lock_info} if successful, {:error, :already_locked, lock_info} if locked by another user.
  """
  @spec acquire(integer(), integer(), map()) ::
          {:ok, lock_info()} | {:error, :already_locked, lock_info()}
  def acquire(flow_id, node_id, user) do
    GenServer.call(__MODULE__, {:acquire, flow_id, node_id, user})
  end

  @doc """
  Releases a lock on a node.
  Only the lock holder can release the lock.
  """
  @spec release(integer(), integer(), integer()) :: :ok | {:error, :not_lock_holder}
  def release(flow_id, node_id, user_id) do
    GenServer.call(__MODULE__, {:release, flow_id, node_id, user_id})
  end

  @doc """
  Releases all locks held by a user in a flow.
  Called when user disconnects.
  """
  @spec release_all(integer(), integer()) :: :ok
  def release_all(flow_id, user_id) do
    GenServer.call(__MODULE__, {:release_all, flow_id, user_id})
  end

  @doc """
  Refreshes the lock timeout (heartbeat).
  """
  @spec refresh(integer(), integer(), integer()) :: :ok | {:error, :not_lock_holder}
  def refresh(flow_id, node_id, user_id) do
    GenServer.call(__MODULE__, {:refresh, flow_id, node_id, user_id})
  end

  @doc """
  Gets the current lock holder for a node, if any.
  """
  @spec get_lock(integer(), integer()) :: {:ok, lock_info()} | {:error, :not_locked}
  def get_lock(flow_id, node_id) do
    GenServer.call(__MODULE__, {:get_lock, flow_id, node_id})
  end

  @doc """
  Gets all locks for a flow.
  """
  @spec list_locks(integer()) :: %{integer() => lock_info()}
  def list_locks(flow_id) do
    GenServer.call(__MODULE__, {:list_locks, flow_id})
  end

  @doc """
  Checks if a node is locked by a different user.
  """
  @spec locked_by_other?(integer(), integer(), integer()) :: boolean()
  def locked_by_other?(flow_id, node_id, user_id) do
    case get_lock(flow_id, node_id) do
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

  # Server callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:acquire, flow_id, node_id, user}, _from, state) do
    key = {flow_id, node_id}
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

  def handle_call({:release, flow_id, node_id, user_id}, _from, state) do
    key = {flow_id, node_id}

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

  def handle_call({:release_all, flow_id, user_id}, _from, state) do
    # Find and delete all locks for this user in this flow
    :ets.foldl(
      fn
        {{^flow_id, _node_id} = key, %{user_id: ^user_id}}, _acc ->
          :ets.delete(@table_name, key)

        _, acc ->
          acc
      end,
      nil,
      @table_name
    )

    {:reply, :ok, state}
  end

  def handle_call({:refresh, flow_id, node_id, user_id}, _from, state) do
    key = {flow_id, node_id}
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

  def handle_call({:get_lock, flow_id, node_id}, _from, state) do
    key = {flow_id, node_id}
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

  def handle_call({:list_locks, flow_id}, _from, state) do
    now = System.monotonic_time(:millisecond)

    locks =
      :ets.foldl(
        fn
          {{^flow_id, node_id}, lock_info}, acc ->
            if lock_info.expires_at > now do
              Map.put(acc, node_id, lock_info)
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
      Logger.debug("Cleaned up #{expired_count} expired node locks")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  # Private functions

  defp try_acquire_existing(key, lock_info, user, now, expires_at) do
    cond do
      lock_info.expires_at <= now ->
        # Lock expired, acquire it
        acquire_new_lock(key, user, now, expires_at)

      lock_info.user_id == user.id ->
        # Same user, refresh the lock
        updated_lock = %{lock_info | expires_at: expires_at}
        :ets.insert(@table_name, {key, updated_lock})
        {:ok, updated_lock}

      true ->
        # Different user holds the lock
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
    :ets.foldl(
      fn {key, lock_info}, count ->
        if lock_info.expires_at <= now do
          :ets.delete(@table_name, key)
          count + 1
        else
          count
        end
      end,
      0,
      @table_name
    )
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired, @cleanup_interval_ms)
  end
end
