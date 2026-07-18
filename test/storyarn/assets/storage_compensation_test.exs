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
    parent = self()
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

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:retained_cleanup_enqueued, keys})
                 {:error, :still_unavailable}
               end,
               delete_fun: fn keys ->
                 send(parent, {:retained_delete_attempted, keys})
                 :ok
               end
             )

    assert_receive {:retained_cleanup_enqueued, [^storage_key]}
    assert_receive {:retained_delete_attempted, [^storage_key]}
    refute Repo.exists?(StorageCleanupRequest)
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

  test "persists an outbox before enqueueing or attempting an opportunistic delete" do
    tracker = StorageCompensation.new()
    storage_key = "projects/1/assets/copy/file.png"
    :ok = StorageCompensation.track(tracker, storage_key)
    parent = self()

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn keys ->
                 assert %StorageCleanupRequest{storage_keys: ^keys} = Repo.one(StorageCleanupRequest)
                 send(parent, {:cleanup_enqueued, keys})
                 :ok
               end,
               delete_fun: fn keys ->
                 assert %StorageCleanupRequest{storage_keys: ^keys} = Repo.one(StorageCleanupRequest)
                 send(parent, {:delete_attempted, keys})
                 {:error, keys}
               end
             )

    assert_receive {:cleanup_enqueued, [^storage_key]}
    assert_receive {:delete_attempted, [^storage_key]}
    assert %StorageCleanupRequest{storage_keys: [^storage_key]} = Repo.one(StorageCleanupRequest)
  end

  test "reconciles the outbox to only the keys that were not deleted" do
    tracker = StorageCompensation.new()
    deleted_key = "projects/1/assets/copy/deleted.png"
    failed_key = "projects/1/assets/copy/failed.png"
    :ok = StorageCompensation.track(tracker, deleted_key)
    :ok = StorageCompensation.track(tracker, failed_key)

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn _keys -> :ok end,
               delete_fun: fn _keys -> {:error, [failed_key]} end
             )

    assert %StorageCleanupRequest{storage_keys: [^failed_key]} = Repo.one(StorageCleanupRequest)
  end

  test "removes the outbox only after every key was deleted" do
    tracker = StorageCompensation.new()
    storage_key = "projects/1/assets/copy/deleted.png"
    :ok = StorageCompensation.track(tracker, storage_key)

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn _keys -> :ok end,
               delete_fun: fn _keys -> :ok end
             )

    refute Repo.exists?(StorageCleanupRequest)
  end

  test "a successful enqueue never substitutes an unavailable outbox" do
    tracker = StorageCompensation.new()
    storage_key = "projects/1/assets/copy/no-outbox.png"
    parent = self()
    :ok = StorageCompensation.track(tracker, storage_key)

    assert {:error,
            {:storage_cleanup_not_persisted,
             %{
               failed_keys: [^storage_key],
               enqueue_error: nil,
               persistence_error: :database_unavailable
             }}} =
             StorageCompensation.cleanup(tracker,
               persist_fun: fn _keys -> {:error, :database_unavailable} end,
               enqueue_fun: fn keys ->
                 send(parent, {:cleanup_enqueued_without_outbox, keys})
                 :ok
               end,
               delete_fun: fn keys -> {:error, keys} end
             )

    assert_receive {:cleanup_enqueued_without_outbox, [^storage_key]}

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:retained_after_enqueue, keys})
                 :ok
               end,
               delete_fun: fn _keys -> :ok end
             )

    assert_receive {:retained_after_enqueue, [^storage_key]}
  end

  test "unexpected delete results retain the full durable target set" do
    tracker = StorageCompensation.new()
    first_key = "projects/1/assets/copy/first.png"
    second_key = "projects/1/assets/copy/second.png"
    :ok = StorageCompensation.track(tracker, first_key)
    :ok = StorageCompensation.track(tracker, second_key)

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn _keys -> :ok end,
               delete_fun: fn _keys -> {:error, []} end
             )

    assert %StorageCleanupRequest{storage_keys: storage_keys} = Repo.one(StorageCleanupRequest)
    assert Enum.sort(storage_keys) == Enum.sort([first_key, second_key])
  end

  test "callback exceptions and unexpected results leave the outbox recoverable" do
    tracker = StorageCompensation.new()
    storage_key = "projects/1/assets/copy/callback-failure.png"
    :ok = StorageCompensation.track(tracker, storage_key)

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn _keys -> raise "queue unavailable" end,
               delete_fun: fn _keys -> :unexpected_delete_result end
             )

    assert %StorageCleanupRequest{storage_keys: [^storage_key]} = Repo.one(StorageCleanupRequest)
  end

  test "an unexpected persistence success cannot discard unpersisted targets" do
    tracker = StorageCompensation.new()
    storage_key = "projects/1/assets/copy/fake-persistence.png"
    parent = self()
    :ok = StorageCompensation.track(tracker, storage_key)

    assert {:error,
            {:storage_cleanup_not_persisted,
             %{
               failed_keys: [^storage_key],
               enqueue_error: nil,
               persistence_error: :unexpected_persistence_result
             }}} =
             StorageCompensation.cleanup(tracker,
               persist_fun: fn _keys -> {:ok, :not_an_outbox_record} end,
               enqueue_fun: fn _keys -> :ok end,
               delete_fun: fn _keys -> :unexpected_delete_result end
             )

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:fake_persistence_target_retained, keys})
                 :ok
               end,
               delete_fun: fn _keys -> :ok end
             )

    assert_receive {:fake_persistence_target_retained, [^storage_key]}
  end

  test "a reconciliation exception leaves the original outbox intact" do
    tracker = StorageCompensation.new()
    storage_key = "projects/1/assets/copy/reconcile-failure.png"
    :ok = StorageCompensation.track(tracker, storage_key)

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn _keys -> :ok end,
               delete_fun: fn keys -> {:error, keys} end,
               reconcile_fun: fn _request, _delete_result -> raise "database unavailable" end
             )

    assert %StorageCleanupRequest{storage_keys: [^storage_key]} = Repo.one(StorageCleanupRequest)
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
    assert %StorageCleanupRequest{storage_keys: [^storage_key]} = Repo.one(StorageCleanupRequest)
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

  test "template import blobs use durable cleanup after an immediate delete failure" do
    hash = String.duplicate("a", 64)
    storage_key = "project_templates/imported_blobs/demo-template/run-1/#{hash}/voice-over.mp3"

    assert :ok =
             StorageCompensation.delete_or_enqueue(storage_key,
               delete_fun: fn ^storage_key -> {:error, :temporarily_unavailable} end,
               delete_attempts: 1,
               enqueue_fun: fn [^storage_key] -> {:error, :oban_unavailable} end
             )

    assert %StorageCleanupRequest{storage_keys: [^storage_key]} = Repo.one(StorageCleanupRequest)
  end

  test "tracked template import artifacts follow the durable cleanup path" do
    snapshot_key = "project_templates/imports/demo-template/run-1/snapshot.json.gz"
    manifest_key = "project_templates/imports/demo-template/run-1/asset-manifest.json.gz"
    tracker = StorageCompensation.new()

    :ok = StorageCompensation.track(tracker, snapshot_key)
    :ok = StorageCompensation.track(tracker, manifest_key)

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn _keys -> {:error, :oban_unavailable} end,
               delete_fun: fn keys -> {:error, keys} end
             )

    assert %StorageCleanupRequest{storage_keys: storage_keys} = Repo.one(StorageCleanupRequest)
    assert Enum.sort(storage_keys) == Enum.sort([snapshot_key, manifest_key])
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
      "projects/1/assets/tmp/" <> <<255>>,
      "project_templates/imported_blobs/demo/run/../#{String.duplicate("a", 64)}/file.png",
      "project_templates/imported_blobs//run/#{String.duplicate("a", 64)}/file.png",
      "project_templates/imported_blobs/demo//#{String.duplicate("a", 64)}/file.png",
      "project_templates/imported_blobs/./run/#{String.duplicate("a", 64)}/file.png",
      "project_templates/imported_blobs/demo/../#{String.duplicate("a", 64)}/file.png",
      "project_templates/imported_blobs/demo/run/#{String.duplicate("a", 63)}/file.png",
      "project_templates/imported_blobs/demo/run/#{String.duplicate("A", 64)}/file.png",
      "project_templates/imported_blobs/demo/run/#{String.duplicate("a", 63)}g/file.png",
      "project_templates/imported_blobs/demo/run/#{String.duplicate("a", 64)}/.",
      "project_templates/imported_blobs/demo/run/#{String.duplicate("a", 64)}/..",
      "project_templates/imported_blobs/demo/run/#{String.duplicate("a", 64)}/Unsafe Name.png",
      "project_templates/imported_blobs/demo/run/#{String.duplicate("a", 64)}/nested/file.png",
      "project_templates/imports/demo/run/../snapshot.json.gz",
      "project_templates/imports//run/snapshot.json.gz",
      "project_templates/imports/demo//snapshot.json.gz",
      "project_templates/imports/./run/snapshot.json.gz",
      "project_templates/imports/demo/../snapshot.json.gz",
      "project_templates/imports/demo/run/snapshot.json",
      "project_templates/imports/demo/run/snapshot.json.gz.bak",
      "project_templates/imports/demo/run/manifest.json.gz",
      "project_templates/imports/demo/run/asset-manifest.json",
      "project_templates/imports/demo/run/nested/snapshot.json.gz",
      "project_template/imports/demo/run/snapshot.json.gz"
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
