defmodule Storyarn.Assets.StorageCompensationTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import ExUnit.CaptureLog

  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupPersistenceError
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Workers.DeleteStorageObjectsWorker
  alias Storyarn.Workers.RetryStorageCleanupRequestsWorker

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
    storage_key = "projects/1/assets/tmp/orphan.png"
    parent = self()

    assert :ok =
             StorageCompensation.delete_or_enqueue(storage_key,
               delete_fun: fn ^storage_key -> {:error, :temporarily_unavailable} end,
               delete_retry_delay_ms: 0,
               enqueue_fun: fn keys ->
                 send(parent, {:cleanup_enqueued, keys})
                 :ok
               end
             )

    assert_receive {:cleanup_enqueued, [^storage_key]}
  end

  test "does not enqueue cleanup when an immediate deletion retry succeeds" do
    storage_key = "projects/1/assets/tmp/recovered-orphan.png"
    parent = self()
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    delete_fun = fn ^storage_key ->
      attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})
      if attempt == 1, do: {:error, :temporarily_unavailable}, else: :ok
    end

    assert :ok =
             StorageCompensation.delete_or_enqueue(storage_key,
               delete_fun: delete_fun,
               delete_retry_delay_ms: 0,
               enqueue_fun: fn keys ->
                 send(parent, {:cleanup_enqueued, keys})
                 :ok
               end
             )

    assert Agent.get(attempts, & &1) == 2
    refute_receive {:cleanup_enqueued, _keys}
  end

  test "treats nonpositive delete attempts as one before enqueuing" do
    storage_key = "projects/1/assets/tmp/no-retries-orphan.png"
    parent = self()
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    assert :ok =
             StorageCompensation.delete_or_enqueue(storage_key,
               delete_fun: fn ^storage_key ->
                 Agent.update(attempts, &(&1 + 1))
                 {:error, :temporarily_unavailable}
               end,
               delete_attempts: 0,
               enqueue_fun: fn keys ->
                 send(parent, {:cleanup_enqueued, keys})
                 :ok
               end
             )

    assert Agent.get(attempts, & &1) == 1
    assert_receive {:cleanup_enqueued, [^storage_key]}
  end

  test "persists failed immediate cleanup when queue insertion also fails" do
    storage_key = "projects/1/assets/tmp/persisted-orphan.png"

    assert :ok =
             StorageCompensation.delete_or_enqueue(storage_key,
               delete_fun: fn ^storage_key -> {:error, :temporarily_unavailable} end,
               delete_retry_delay_ms: 0,
               enqueue_fun: fn [^storage_key] -> {:error, :oban_unavailable} end
             )

    assert %StorageCleanupRequest{storage_keys: [^storage_key]} = Repo.one(StorageCleanupRequest)
  end

  test "recoverable blobs never reach synchronous cleanup callbacks" do
    storage_key = "projects/1/blobs/#{System.unique_integer([:positive])}.png"
    assert {:ok, _url} = Storage.upload(storage_key, "recovery blob", "image/png")
    parent = self()

    assert :ok =
             StorageCompensation.delete_or_enqueue(storage_key,
               delete_fun: fn _key ->
                 send(parent, :direct_delete_attempted)
                 :ok
               end,
               enqueue_fun: fn _keys ->
                 send(parent, :cleanup_enqueued)
                 :ok
               end
             )

    assert :ok =
             StorageCompensation.enqueue_cleanup([storage_key],
               insert_fun: fn _keys ->
                 send(parent, :cleanup_job_inserted)
                 {:ok, %{id: 1}}
               end
             )

    tracker = StorageCompensation.new()
    :ok = StorageCompensation.track(tracker, storage_key)

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn _keys ->
                 send(parent, :tracked_cleanup_enqueued)
                 :ok
               end,
               delete_fun: fn _keys ->
                 send(parent, :tracked_delete_attempted)
                 :ok
               end
             )

    assert :ok = StorageCompensation.delete_storage_keys([storage_key])

    refute_receive :direct_delete_attempted
    refute_receive :cleanup_enqueued
    refute_receive :cleanup_job_inserted
    refute_receive :tracked_cleanup_enqueued
    refute_receive :tracked_delete_attempted
    assert {:ok, "recovery blob"} = Storage.download(storage_key)
  end

  test "mixed legacy jobs delete temporary assets but preserve blobs" do
    suffix = System.unique_integer([:positive])
    asset_key = "projects/1/assets/tmp/#{suffix}.png"
    blob_key = "projects/1/blobs/#{suffix}.png"

    assert {:ok, _url} = Storage.upload(asset_key, "temporary copy", "image/png")
    assert {:ok, _url} = Storage.upload(blob_key, "queued recovery blob", "image/png")

    request = Repo.insert!(%StorageCleanupRequest{storage_keys: [asset_key, blob_key]})

    assert :ok =
             perform_job(DeleteStorageObjectsWorker, %{
               "storage_keys" => [asset_key, blob_key]
             })

    assert :ok = perform_job(RetryStorageCleanupRequestsWorker, %{})

    refute Repo.get(StorageCleanupRequest, request.id)
    assert {:error, :enoent} = Storage.download(asset_key)
    assert {:ok, "queued recovery blob"} = Storage.download(blob_key)
  end

  test "the common storage boundary refuses direct blob deletion" do
    storage_key = "projects/1/blobs/#{System.unique_integer([:positive])}.png"
    assert {:ok, _url} = Storage.upload(storage_key, "protected blob", "image/png")

    assert {:error, :recoverable_blob} = Storage.delete(storage_key)
    assert {:ok, "protected blob"} = Storage.download(storage_key)
  end

  test "invalid or traversal-like keys never reach deletion callbacks" do
    parent = self()

    invalid_keys = [
      "projects/1/assets/../blobs/recovery.png",
      "projects/1/assets/./copy.png",
      "projects/not-an-id/assets/tmp/copy.png",
      "projects/1/assets/",
      "other/1/assets/tmp/copy.png",
      "projects/1/assets/tmp\\copy.png",
      "projects/1/assets/tmp/copy.png" <> <<0>>,
      "projects/1/assets/tmp/" <> <<255>>
    ]

    for invalid_key <- invalid_keys do
      assert :ok =
               StorageCompensation.delete_or_enqueue(invalid_key,
                 delete_fun: fn _key ->
                   send(parent, :invalid_delete_attempted)
                   {:error, :temporarily_unavailable}
                 end,
                 delete_attempts: 1,
                 enqueue_fun: fn _keys ->
                   send(parent, :invalid_cleanup_enqueued)
                   :ok
                 end
               )

      assert :ok =
               StorageCompensation.enqueue_cleanup([invalid_key],
                 insert_fun: fn _keys ->
                   send(parent, :invalid_cleanup_job_inserted)
                   {:ok, %{id: 1}}
                 end
               )

      tracker = StorageCompensation.new()
      :ok = StorageCompensation.track(tracker, invalid_key)

      assert :ok =
               StorageCompensation.cleanup(tracker,
                 enqueue_fun: fn _keys ->
                   send(parent, :invalid_tracked_cleanup_enqueued)
                   :ok
                 end,
                 delete_fun: fn _keys ->
                   send(parent, :invalid_tracked_delete_attempted)
                   :ok
                 end
               )
    end

    refute_receive :invalid_delete_attempted
    refute_receive :invalid_cleanup_enqueued
    refute_receive :invalid_cleanup_job_inserted
    refute_receive :invalid_tracked_cleanup_enqueued
    refute_receive :invalid_tracked_delete_attempted
  end
end
