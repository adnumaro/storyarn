defmodule Storyarn.Assets.StorageCompensationTest do
  use Storyarn.DataCase, async: true

  import ExUnit.CaptureLog

  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupPersistenceError
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Assets.StorageCompensation

  test "retries cleanup job persistence before returning an error" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    insert_fun = fn _storage_keys ->
      attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})
      if attempt < 3, do: {:error, :database_unavailable}, else: {:ok, %{id: 1}}
    end

    log =
      capture_log(fn ->
        assert :ok =
                 StorageCompensation.enqueue_cleanup(
                   ["projects/1/assets/copy/file.png"],
                   insert_fun: insert_fun,
                   retry_delay_ms: 0
                 )
      end)

    assert Agent.get(attempts, & &1) == 3
    assert log =~ "retrying"
  end

  test "persists failed keys in the fallback outbox when job persistence fails" do
    tracker = StorageCompensation.new()
    storage_key = "projects/1/assets/copy/file.png"
    :ok = StorageCompensation.track(tracker, storage_key)

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn _keys -> {:error, :oban_unavailable} end,
               delete_fun: fn keys -> {:error, keys} end
             )

    assert %StorageCleanupRequest{storage_keys: [^storage_key]} = Repo.one(StorageCleanupRequest)
  end

  test "propagates failed keys when no durable cleanup path is available" do
    tracker = StorageCompensation.new()
    storage_key = "projects/1/assets/copy/file.png"
    :ok = StorageCompensation.track(tracker, storage_key)

    log =
      capture_log(fn ->
        assert {:error,
                {:storage_cleanup_not_persisted,
                 %{
                   failed_keys: [^storage_key],
                   enqueue_error: :oban_unavailable,
                   persistence_error: :database_unavailable
                 }}} =
                 StorageCompensation.cleanup(tracker,
                   enqueue_fun: fn _keys -> {:error, :oban_unavailable} end,
                   persist_fun: fn _keys -> {:error, :database_unavailable} end,
                   delete_fun: fn keys -> {:error, keys} end
                 )
      end)

    assert log =~ "could not be completed or persisted"

    assert :ok = StorageCompensation.cleanup(tracker)
  end

  test "cleanup! raises when the cleanup cannot be completed or persisted" do
    tracker = StorageCompensation.new()
    :ok = StorageCompensation.track(tracker, "projects/1/assets/copy/file.png")

    assert_raise StorageCleanupPersistenceError, fn ->
      StorageCompensation.cleanup!(tracker,
        enqueue_fun: fn _keys -> {:error, :oban_unavailable} end,
        persist_fun: fn _keys -> {:error, :database_unavailable} end,
        delete_fun: fn keys -> {:error, keys} end
      )
    end
  end

  test "persists cleanup before attempting an opportunistic delete" do
    tracker = StorageCompensation.new()
    storage_key = "projects/1/assets/copy/file.png"
    :ok = StorageCompensation.track(tracker, storage_key)
    parent = self()

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:cleanup_persisted, keys})
                 :ok
               end,
               delete_fun: fn keys ->
                 send(parent, {:delete_attempted, keys})
                 {:error, keys}
               end
             )

    assert_receive {:cleanup_persisted, [^storage_key]}
    assert_receive {:delete_attempted, [^storage_key]}
  end

  test "enqueues durable cleanup when an immediate delete fails" do
    storage_key = "projects/1/blobs/orphan.png"
    parent = self()

    assert :ok =
             StorageCompensation.delete_or_enqueue(storage_key,
               delete_fun: fn ^storage_key -> {:error, :temporarily_unavailable} end,
               enqueue_fun: fn keys ->
                 send(parent, {:cleanup_enqueued, keys})
                 :ok
               end
             )

    assert_receive {:cleanup_enqueued, [^storage_key]}
  end

  test "persists failed immediate cleanup when queue insertion also fails" do
    storage_key = "projects/1/blobs/persisted-orphan.png"

    assert :ok =
             StorageCompensation.delete_or_enqueue(storage_key,
               delete_fun: fn ^storage_key -> {:error, :temporarily_unavailable} end,
               enqueue_fun: fn [^storage_key] -> {:error, :oban_unavailable} end
             )

    assert %StorageCleanupRequest{storage_keys: [^storage_key]} = Repo.one(StorageCleanupRequest)
  end

  test "accepts blob keys for deletion retries" do
    storage_key = "projects/1/blobs/#{System.unique_integer([:positive])}.png"
    assert {:ok, _url} = Storage.upload(storage_key, "blob", "image/png")

    assert :ok = StorageCompensation.delete_storage_keys([storage_key])
    assert {:error, :enoent} = Storage.download(storage_key)
  end
end
