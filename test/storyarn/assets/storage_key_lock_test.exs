defmodule Storyarn.Assets.StorageKeyLockTest do
  use Storyarn.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Assets.StorageKeyLock
  alias Storyarn.Repo

  @lock_key_limit 2_147_483_647
  @concurrency_timeout 5_000

  test "recognizes project blob keys without classifying temporary hard links as blobs" do
    hash = String.duplicate("a", 64)
    blob_key = "projects/42/blobs/#{hash}.png"

    assert {:ok, 42} = StorageKeyLock.project_blob_id(blob_key)
    assert :error = StorageKeyLock.project_blob_id("#{blob_key}.storyarn-copy-random")
    assert :error = StorageKeyLock.project_blob_id("projects/42/assets/#{hash}.png")
    assert :error = StorageKeyLock.project_blob_id("projects/42/blobs/not-a-hash.png")
  end

  test "marks only transaction locks owned by the wrapper" do
    storage_key = "projects/42/assets/#{Ecto.UUID.generate()}/owned-lock.png"

    refute StorageKeyLock.wrapper_owned_transaction_lock_held?(storage_key)

    assert :wrapper_owned =
             Sandbox.unboxed_run(Repo, fn ->
               StorageKeyLock.with_storage_key_lock(storage_key, fn ->
                 assert Repo.in_transaction?()
                 assert StorageKeyLock.wrapper_owned_transaction_lock_held?(storage_key)
                 :wrapper_owned
               end)
             end)

    refute StorageKeyLock.wrapper_owned_transaction_lock_held?(storage_key)

    assert {:ok, :caller_owned} =
             Sandbox.unboxed_run(Repo, fn ->
               Repo.transaction(fn ->
                 StorageKeyLock.with_storage_key_lock(storage_key, fn ->
                   refute StorageKeyLock.wrapper_owned_transaction_lock_held?(storage_key)
                   :caller_owned
                 end)
               end)
             end)

    assert_raise RuntimeError, "lock callback failed", fn ->
      Sandbox.unboxed_run(Repo, fn ->
        StorageKeyLock.with_storage_key_lock(storage_key, fn ->
          assert StorageKeyLock.wrapper_owned_transaction_lock_held?(storage_key)
          raise "lock callback failed"
        end)
      end)
    end

    refute StorageKeyLock.wrapper_owned_transaction_lock_held?(storage_key)
  end

  test "serializes concurrent owners of the same project blob key" do
    parent = self()
    hash = String.duplicate("b", 64)
    blob_key = "projects/42/blobs/#{hash}.png"

    first =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_project_blob_lock(blob_key, fn ->
            send(parent, {:lock_acquired, :first})

            receive do
              :release_first -> :ok
            end
          end)
        end)
      end)

    assert_receive {:lock_acquired, :first}

    second =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_project_blob_lock(blob_key, fn ->
            send(parent, {:lock_acquired, :second})
          end)
        end)
      end)

    refute_receive {:lock_acquired, :second}, 100
    send(first.pid, :release_first)

    assert :ok = Task.await(first)
    assert_receive {:lock_acquired, :second}
    assert {:lock_acquired, :second} = Task.await(second)
  end

  test "serializes cleanup behind the transaction adopting a unique asset key" do
    parent = self()
    asset_key = "projects/42/assets/#{Ecto.UUID.generate()}/portrait.png"

    writer =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_storage_key_lock(asset_key, fn ->
            send(parent, {:asset_lock_acquired, :writer})

            receive do
              :commit_writer -> :ok
            end
          end)
        end)
      end)

    assert_receive {:asset_lock_acquired, :writer}

    cleanup =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_storage_key_lock(asset_key, fn ->
            send(parent, {:asset_lock_acquired, :cleanup})
          end)
        end)
      end)

    refute_receive {:asset_lock_acquired, :cleanup}, 100
    send(writer.pid, :commit_writer)

    assert :ok = Task.await(writer)
    assert_receive {:asset_lock_acquired, :cleanup}
    assert {:asset_lock_acquired, :cleanup} = Task.await(cleanup)
  end

  test "bounds transaction-lock acquisition without timing out a long lock owner" do
    parent = self()
    asset_key = "projects/42/assets/#{Ecto.UUID.generate()}/bounded-lock.png"

    owner =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_storage_key_lock(asset_key, fn ->
            send(parent, :bounded_storage_lock_acquired)

            receive do
              :release_bounded_storage_lock -> :ok
            end
          end)
        end)
      end)

    assert_receive :bounded_storage_lock_acquired

    contender =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_storage_key_lock(
            asset_key,
            fn -> flunk("timed-out contender must not run") end,
            acquisition_timeout: 50
          )
        end)
      end)

    assert {:error, :storage_key_lock_timeout} = Task.await(contender)
    send(owner.pid, :release_bounded_storage_lock)
    assert :ok = Task.await(owner)

    assert :callback_finished =
             Sandbox.unboxed_run(Repo, fn ->
               StorageKeyLock.with_storage_key_lock(
                 asset_key,
                 fn ->
                   Process.sleep(75)
                   Repo.query!("SELECT 1")
                   :callback_finished
                 end,
                 acquisition_timeout: 10
               )
             end)
  end

  test "bounds storage-lock acquisition inside an existing transaction" do
    parent = self()
    asset_key = "projects/42/assets/#{Ecto.UUID.generate()}/bounded-in-transaction.png"

    owner =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_storage_key_lock(asset_key, fn ->
            send(parent, :transaction_owner_acquired)

            receive do
              :release_transaction_owner -> :ok
            end
          end)
        end)
      end)

    assert_receive :transaction_owner_acquired

    contender =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            result =
              StorageKeyLock.with_storage_key_lock(
                asset_key,
                fn -> flunk("timed-out transactional contender must not run") end,
                acquisition_timeout: 50
              )

            assert %{rows: [[1]]} = Repo.query!("SELECT 1")
            result
          end)
        end)
      end)

    assert {:ok, {:error, :storage_key_lock_timeout}} = Task.await(contender)
    send(owner.pid, :release_transaction_owner)
    assert :ok = Task.await(owner)
  end

  test "acquires a set of transaction locks with one bounded fence" do
    parent = self()
    blocked_key = "projects/42/assets/#{Ecto.UUID.generate()}/blocked.png"
    free_key = "projects/42/assets/#{Ecto.UUID.generate()}/free.png"

    owner =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_storage_key_lock(blocked_key, fn ->
            send(parent, :bulk_lock_blocker_acquired)

            receive do
              :release_bulk_lock_blocker -> :ok
            end
          end)
        end)
      end)

    assert_receive :bulk_lock_blocker_acquired

    assert {:ok, {:error, :storage_key_lock_timeout}} =
             Sandbox.unboxed_run(Repo, fn ->
               Repo.transaction(fn ->
                 StorageKeyLock.with_storage_key_locks(
                   [free_key, blocked_key, free_key],
                   fn -> flunk("the batch callback must not run while any key is locked") end,
                   acquisition_timeout: 50
                 )
               end)
             end)

    send(owner.pid, :release_bulk_lock_blocker)
    assert :ok = Task.await(owner)

    assert {:ok, :all_locked} =
             Sandbox.unboxed_run(Repo, fn ->
               Repo.transaction(fn ->
                 StorageKeyLock.with_storage_key_locks(
                   [free_key, blocked_key],
                   fn ->
                     Repo.query!("SELECT pg_sleep(0.075)")
                     :all_locked
                   end,
                   acquisition_timeout: 50
                 )
               end)
             end)
  end

  test "overlapping lock sets do not retain a failed attempt's partial locks" do
    parent = self()
    barrier = make_ref()
    [first_unique_key, second_unique_key, common_key] = ordered_storage_keys()

    first =
      overlapping_batch_task(
        :first,
        [first_unique_key, common_key],
        parent,
        barrier
      )

    second =
      overlapping_batch_task(
        :second,
        [second_unique_key, common_key],
        parent,
        barrier
      )

    assert_receive {^barrier, :ready, :first, first_pid}, @concurrency_timeout
    assert_receive {^barrier, :ready, :second, second_pid}, @concurrency_timeout
    send(first_pid, {barrier, :start})
    send(second_pid, {barrier, :start})

    assert_receive {^barrier, :acquired, winner, winner_pid}, @concurrency_timeout
    assert_receive {^barrier, :timed_out, loser, loser_pid}, @concurrency_timeout
    assert MapSet.new([winner, loser]) == MapSet.new([:first, :second])

    loser_unique_key =
      if loser == :first,
        do: first_unique_key,
        else: second_unique_key

    # The failed batch keeps its outer transaction open. Its unique key must
    # nevertheless be immediately available because the failed savepoint owns
    # no surviving partial advisory locks.
    assert :loser_unique_key_available =
             probe_storage_key_lock(loser_unique_key, :loser_unique_key_available, 100)

    # The successful batch still fences every key until its outer transaction
    # completes, including the key shared by both batches.
    assert {:error, :storage_key_lock_timeout} =
             probe_storage_key_lock(common_key, :common_key_must_stay_locked, 50)

    send(loser_pid, {barrier, :release})
    assert {:ok, {:timed_out, ^loser}} = Task.await(batch_task(loser, first, second), @concurrency_timeout)

    send(winner_pid, {barrier, :release})
    assert {:ok, {:acquired, ^winner}} = Task.await(batch_task(winner, first, second), @concurrency_timeout)
  end

  test "rejects transaction lock sets outside a transaction and malformed keys" do
    storage_key = "projects/42/assets/#{Ecto.UUID.generate()}/portrait.png"

    assert {:error, :storage_key_locks_require_transaction} =
             Sandbox.unboxed_run(Repo, fn ->
               StorageKeyLock.with_storage_key_locks([storage_key], fn -> flunk("must not run") end)
             end)

    assert {:ok, {:error, :invalid_storage_key_lock_set}} =
             Sandbox.unboxed_run(Repo, fn ->
               Repo.transaction(fn ->
                 StorageKeyLock.with_storage_key_locks([storage_key, ""], fn -> flunk("must not run") end)
               end)
             end)
  end

  defp overlapping_batch_task(label, storage_keys, parent, barrier) do
    Task.async(fn -> run_unboxed_overlapping_batch(label, storage_keys, parent, barrier) end)
  end

  defp run_unboxed_overlapping_batch(label, storage_keys, parent, barrier) do
    Sandbox.unboxed_run(Repo, fn ->
      run_overlapping_batch_transaction(label, storage_keys, parent, barrier)
    end)
  end

  defp run_overlapping_batch_transaction(label, storage_keys, parent, barrier) do
    Repo.transaction(fn -> run_overlapping_batch(label, storage_keys, parent, barrier) end)
  end

  defp run_overlapping_batch(label, storage_keys, parent, barrier) do
    send(parent, {barrier, :ready, label, self()})
    statement_timeout = current_statement_timeout()
    await_batch_message!(barrier, :start, :batch_start_timeout)

    result =
      StorageKeyLock.with_storage_key_locks(
        storage_keys,
        fn -> hold_acquired_batch(label, parent, barrier, statement_timeout) end,
        acquisition_timeout: 150
      )

    finish_overlapping_batch(result, label, parent, barrier, statement_timeout)
  end

  defp hold_acquired_batch(label, parent, barrier, statement_timeout) do
    assert_outer_transaction_usable!(statement_timeout)
    send(parent, {barrier, :acquired, label, self()})
    await_batch_message!(barrier, :release, :batch_release_timeout)
    {:acquired, label}
  end

  defp finish_overlapping_batch({:error, :storage_key_lock_timeout}, label, parent, barrier, statement_timeout) do
    assert_outer_transaction_usable!(statement_timeout)
    send(parent, {barrier, :timed_out, label, self()})
    await_batch_message!(barrier, :release, :batch_release_timeout)
    {:timed_out, label}
  end

  defp finish_overlapping_batch(result, _label, _parent, _barrier, _statement_timeout), do: result

  defp await_batch_message!(barrier, message, timeout_reason) do
    receive do
      {^barrier, ^message} -> :ok
    after
      @concurrency_timeout -> exit(timeout_reason)
    end
  end

  defp ordered_storage_keys do
    keys =
      for label <- [:first, :second, :common] do
        "projects/42/assets/#{Ecto.UUID.generate()}/#{label}.png"
      end

    case keys |> Enum.uniq_by(&storage_lock_key/1) |> Enum.sort_by(&storage_lock_key/1) do
      [first_unique_key, second_unique_key, common_key] ->
        [first_unique_key, second_unique_key, common_key]

      _collision ->
        ordered_storage_keys()
    end
  end

  defp storage_lock_key(storage_key), do: :erlang.phash2(storage_key, @lock_key_limit)

  defp probe_storage_key_lock(storage_key, result, acquisition_timeout) do
    task = Task.async(fn -> run_storage_key_lock_probe(storage_key, result, acquisition_timeout) end)
    Task.await(task, @concurrency_timeout)
  end

  defp run_storage_key_lock_probe(storage_key, result, acquisition_timeout) do
    callback = fn -> result end

    Sandbox.unboxed_run(Repo, fn ->
      StorageKeyLock.with_storage_key_lock(storage_key, callback, acquisition_timeout: acquisition_timeout)
    end)
  end

  defp assert_outer_transaction_usable!(statement_timeout) do
    %{rows: [[1]]} = Repo.query!("SELECT 1")
    [[^statement_timeout]] = Repo.query!("SHOW statement_timeout").rows
    :ok
  end

  defp current_statement_timeout do
    [[statement_timeout]] = Repo.query!("SHOW statement_timeout").rows
    statement_timeout
  end

  defp batch_task(:first, first, _second), do: first
  defp batch_task(:second, _first, second), do: second

  test "session locks serialize long callbacks without wrapping them in a transaction" do
    parent = self()
    lock_name = "template-installation:#{System.unique_integer([:positive])}"

    first =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_session_lock(lock_name, fn ->
            send(parent, {:session_lock_acquired, :first, Repo.in_transaction?()})

            receive do
              :release_first -> :ok
            end
          end)
        end)
      end)

    assert_receive {:session_lock_acquired, :first, false}

    second =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_session_lock(lock_name, fn ->
            send(parent, {:session_lock_acquired, :second, Repo.in_transaction?()})
          end)
        end)
      end)

    independent =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_session_lock(lock_name <> ":independent", fn ->
            send(parent, {:session_lock_acquired, :independent, Repo.in_transaction?()})
          end)
        end)
      end)

    refute_receive {:session_lock_acquired, :second, _in_transaction?}, 100
    assert_receive {:session_lock_acquired, :independent, false}
    assert {:session_lock_acquired, :independent, false} = Task.await(independent)

    send(first.pid, :release_first)

    assert :ok = Task.await(first)
    assert_receive {:session_lock_acquired, :second, false}
    assert {:session_lock_acquired, :second, false} = Task.await(second)
  end

  test "bounds session-lock acquisition without applying the deadline to its callback" do
    parent = self()
    lock_name = "bounded-template-installation:#{System.unique_integer([:positive])}"

    owner =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_session_lock(lock_name, fn ->
            send(parent, :bounded_session_lock_acquired)

            receive do
              :release_bounded_session_lock -> :ok
            end
          end)
        end)
      end)

    assert_receive :bounded_session_lock_acquired

    contender =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_session_lock(
            lock_name,
            fn -> flunk("timed-out contender must not run") end,
            acquisition_timeout: 50
          )
        end)
      end)

    assert {:error, :session_lock_timeout} = Task.await(contender)
    send(owner.pid, :release_bounded_session_lock)
    assert :ok = Task.await(owner)

    assert :callback_finished =
             Sandbox.unboxed_run(Repo, fn ->
               StorageKeyLock.with_session_lock(
                 lock_name,
                 fn ->
                   Process.sleep(75)
                   Repo.query!("SELECT 1")
                   :callback_finished
                 end,
                 acquisition_timeout: 10
               )
             end)
  end

  test "rejects invalid acquisition timeouts" do
    assert_raise ArgumentError, ~r/acquisition_timeout/, fn ->
      Sandbox.unboxed_run(Repo, fn ->
        StorageKeyLock.with_session_lock("invalid-timeout", fn -> :ok end, acquisition_timeout: :infinity)
      end)
    end
  end
end
