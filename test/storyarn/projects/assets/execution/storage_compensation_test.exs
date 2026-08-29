defmodule Storyarn.Projects.Assets.StorageCompensationTest do
  use Storyarn.DataCase, async: true

  import ExUnit.CaptureLog
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.VersioningFixtures

  alias Storyarn.Commercial.Billing.StorageCleanupInventory
  alias Storyarn.Commercial.Billing.StorageReservation
  alias Storyarn.Platform.ObjectStorage
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageCleanupPersistenceError
  alias Storyarn.Projects.Assets.StorageCleanupRequest
  alias Storyarn.Projects.Assets.StorageCompensation
  alias Storyarn.Projects.Assets.StorageKeyLock
  alias Storyarn.Projects.Persistence.StorageReservationRecord
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectTemplates.ProjectTemplate
  alias Storyarn.Projects.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.Projects.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Projects.Versioning.SnapshotObjectPublicationClaim

  test "retries cleanup job persistence before returning an error" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)
    storage_key = cleanup_asset_key("retry-persistence")

    insert_fun = fn _storage_keys ->
      attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})
      if attempt < 3, do: {:error, :database_unavailable}, else: {:ok, %{id: 1}}
    end

    log =
      capture_log([level: :info], fn ->
        assert :ok =
                 StorageCompensation.enqueue_cleanup(
                   [storage_key],
                   insert_fun: insert_fun,
                   retry_delay_ms: 0
                 )
      end)

    assert Agent.get(attempts, & &1) == 3
    assert log =~ "retrying"
  end

  test "persists failed keys in the fallback outbox when job persistence fails" do
    tracker = StorageCompensation.new()
    storage_key = cleanup_asset_key("fallback-outbox")
    :ok = StorageCompensation.track(tracker, storage_key)

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn _keys -> {:error, :oban_unavailable} end,
               delete_fun: fn keys -> {:error, keys} end
             )

    assert %StorageCleanupRequest{storage_keys: [^storage_key]} =
             Repo.one(from request in StorageCleanupRequest, where: request.storage_keys == ^[storage_key])
  end

  test "propagates failed keys when no durable cleanup path is available" do
    tracker = StorageCompensation.new()
    storage_key = cleanup_asset_key("no-durable-path")
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
                 :ok
               end,
               delete_fun: fn keys ->
                 send(parent, {:unexpected_retained_delete, keys})
                 :ok
               end
             )

    assert_receive {:retained_cleanup_enqueued, [^storage_key]}
    refute_receive {:unexpected_retained_delete, [^storage_key]}
  end

  test "cleanup! raises when the cleanup cannot be completed or persisted" do
    tracker = StorageCompensation.new()
    storage_key = cleanup_asset_key("cleanup-raises")
    :ok = StorageCompensation.track(tracker, storage_key)

    assert_raise StorageCleanupPersistenceError, fn ->
      StorageCompensation.cleanup!(tracker,
        enqueue_fun: fn _keys -> {:error, :oban_unavailable} end,
        persist_fun: fn _keys -> {:error, :database_unavailable} end,
        delete_fun: fn keys -> {:error, keys} end
      )
    end
  end

  test "hands cleanup to durable queue without caller-side remote deletion" do
    tracker = StorageCompensation.new()
    storage_key = cleanup_asset_key("remote-handoff")
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
    refute_receive {:delete_attempted, [^storage_key]}
  end

  test "rollback cleanup deletes immediately without enqueueing when deletion succeeds" do
    tracker = StorageCompensation.new()
    storage_key = cleanup_asset_key("rollback-immediate")
    parent = self()
    :ok = StorageCompensation.track(tracker, storage_key)

    assert :ok =
             StorageCompensation.cleanup_after_rollback(tracker,
               delete_fun: fn keys ->
                 send(parent, {:rollback_delete_attempted, keys})
                 :ok
               end,
               enqueue_fun: fn keys ->
                 send(parent, {:unexpected_rollback_enqueue, keys})
                 :ok
               end
             )

    assert_receive {:rollback_delete_attempted, [^storage_key]}
    refute_receive {:unexpected_rollback_enqueue, [^storage_key]}
  end

  test "rollback cleanup durably hands off only keys that could not be deleted" do
    tracker = StorageCompensation.new()
    deleted_key = cleanup_asset_key("rollback-deleted")
    failed_key = cleanup_asset_key("rollback-failed")
    parent = self()
    :ok = StorageCompensation.track(tracker, deleted_key)
    :ok = StorageCompensation.track(tracker, failed_key)

    assert :ok =
             StorageCompensation.cleanup_after_rollback(tracker,
               delete_fun: fn keys ->
                 send(parent, {:rollback_delete_attempted, keys})
                 {:error, [failed_key]}
               end,
               enqueue_fun: fn keys ->
                 send(parent, {:rollback_cleanup_enqueued, keys})
                 :ok
               end
             )

    assert_receive {:rollback_delete_attempted, attempted_keys}
    assert MapSet.new(attempted_keys) == MapSet.new([deleted_key, failed_key])
    assert_receive {:rollback_cleanup_enqueued, [^failed_key]}
  end

  test "successful transaction cleanup retains adopted keys and hands off only partial writes" do
    tracker = StorageCompensation.new()
    retained_key = cleanup_asset_key("committed")
    partial_key = cleanup_asset_key("partial")
    parent = self()

    :ok = StorageCompensation.track(tracker, retained_key)
    :ok = StorageCompensation.retain_after_commit(tracker, retained_key)
    :ok = StorageCompensation.track(tracker, partial_key)

    assert :ok =
             StorageCompensation.cleanup_unretained(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:cleanup_persisted, keys})
                 :ok
               end,
               delete_fun: fn keys ->
                 send(parent, {:delete_attempted, keys})
                 :ok
               end
             )

    assert_receive {:cleanup_persisted, [^partial_key]}
    refute_receive {:delete_attempted, [^partial_key]}
    refute_receive {:cleanup_persisted, [^retained_key]}
  end

  test "pre-commit cleanup handoff keeps rollback compensation until commit is confirmed" do
    tracker = StorageCompensation.new()
    retained_key = cleanup_asset_key("precommit-retained")
    partial_key = cleanup_asset_key("precommit-partial")
    parent = self()

    :ok = StorageCompensation.retain_after_commit(tracker, retained_key)
    :ok = StorageCompensation.track(tracker, partial_key)

    assert :ok =
             StorageCompensation.prepare_unretained_cleanup(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:pre_commit_cleanup_persisted, keys})
                 :ok
               end
             )

    assert_receive {:pre_commit_cleanup_persisted, [^partial_key]}

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:rollback_cleanup_persisted, keys})
                 :ok
               end
             )

    assert_receive {:rollback_cleanup_persisted, rollback_keys}
    assert MapSet.new(rollback_keys) == MapSet.new([retained_key, partial_key])
  end

  test "pre-commit cleanup handoff failure leaves the tracker available to the rollback path" do
    tracker = StorageCompensation.new()
    partial_key = cleanup_asset_key("precommit-failure")
    parent = self()

    :ok = StorageCompensation.track(tracker, partial_key)

    assert {:error,
            {:storage_cleanup_handoff_not_persisted,
             %{
               cleanup_targets: [^partial_key],
               enqueue_error: :oban_unavailable,
               persistence_error: :database_unavailable
             }}} =
             StorageCompensation.prepare_unretained_cleanup(tracker,
               enqueue_fun: fn _keys -> {:error, :oban_unavailable} end,
               persist_fun: fn _keys -> {:error, :database_unavailable} end
             )

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:rollback_cleanup_persisted, keys})
                 :ok
               end
             )

    assert_receive {:rollback_cleanup_persisted, [^partial_key]}
  end

  test "rollback cleanup includes keys previously marked for retention" do
    tracker = StorageCompensation.new()
    storage_key = cleanup_asset_key("rolled-back")
    parent = self()

    :ok = StorageCompensation.retain_after_commit(tracker, storage_key)

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:rollback_cleanup, keys})
                 :ok
               end
             )

    assert_receive {:rollback_cleanup, [^storage_key]}
  end

  test "untracking removes a retained key without leaving duplicate cleanup ownership" do
    tracker = StorageCompensation.new()
    storage_key = cleanup_asset_key("adopted")
    parent = self()

    :ok = StorageCompensation.track(tracker, storage_key)
    :ok = StorageCompensation.retain_after_commit(tracker, storage_key)
    :ok = StorageCompensation.untrack(tracker, storage_key)

    assert :ok =
             StorageCompensation.cleanup_unretained(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:unexpected_cleanup, keys})
                 :ok
               end
             )

    refute_receive {:unexpected_cleanup, _keys}
  end

  test "preserves force-delete intent across transactional cleanup handoff" do
    tracker = StorageCompensation.new()
    storage_key = "projects/1/blobs/#{String.duplicate("d", 64)}.png"
    parent = self()

    :ok = StorageCompensation.track_force_delete(tracker, storage_key)

    assert {:error, :storage_cleanup_requires_post_transaction} =
             StorageCompensation.delete_force_tracked_or_enqueue(tracker, storage_key,
               delete_fun: fn ^storage_key -> {:error, :storage_unavailable} end,
               delete_attempts: 1,
               in_transaction?: true
             )

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn targets ->
                 send(parent, {:force_cleanup_enqueued, targets})
                 :ok
               end
             )

    assert_receive {:force_cleanup_enqueued, [cleanup_target]}
    refute cleanup_target == storage_key
    assert String.ends_with?(cleanup_target, storage_key)
  end

  test "force cleanup deletes a verified-invalid canonical blob for a committed project" do
    user = user_fixture()
    project = project_fixture(user)
    storage_key = "projects/#{project.id}/blobs/#{String.duplicate("e", 64)}.png"
    tracker = StorageCompensation.new()
    parent = self()

    assert {:ok, _url} = Storage.upload(storage_key, "corrupt", "image/png")
    on_exit(fn -> Storage.delete(storage_key) end)

    :ok = StorageCompensation.track_force_delete(tracker, storage_key)

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn targets ->
                 send(parent, {:force_cleanup_enqueued, targets})
                 :ok
               end
             )

    assert_receive {:force_cleanup_enqueued, [cleanup_target]}
    assert :ok = StorageCompensation.delete_storage_keys([cleanup_target])
    assert {:error, :enoent} = Storage.download(storage_key)
  end

  test "force cleanup preserves a canonical blob repaired before the worker runs" do
    user = user_fixture()
    project = project_fixture(user)
    repaired_content = "repaired canonical content"
    hash = :sha256 |> :crypto.hash(repaired_content) |> Base.encode16(case: :lower)
    storage_key = "projects/#{project.id}/blobs/#{hash}.png"
    tracker = StorageCompensation.new()
    parent = self()

    assert {:ok, _url} = Storage.upload(storage_key, "corrupt", "image/png")
    on_exit(fn -> Storage.delete(storage_key) end)

    :ok = StorageCompensation.track_force_delete(tracker, storage_key)

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn targets ->
                 send(parent, {:force_cleanup_enqueued, targets})
                 :ok
               end
             )

    assert_receive {:force_cleanup_enqueued, [cleanup_target]}

    assert {:ok, _url} = Storage.upload(storage_key, repaired_content, "image/png")
    assert :ok = StorageCompensation.delete_storage_keys([cleanup_target])
    assert {:ok, ^repaired_content} = Storage.download(storage_key)
  end

  test "force cleanup rechecks repaired bytes inside a lock-owned transaction" do
    user = user_fixture()
    project = project_fixture(user)
    repaired_content = "repaired while waiting for the canonical blob lock"
    hash = :sha256 |> :crypto.hash(repaired_content) |> Base.encode16(case: :lower)
    storage_key = "projects/#{project.id}/blobs/#{hash}.png"
    tracker = StorageCompensation.new()

    assert {:ok, _url} = Storage.upload(storage_key, repaired_content, "image/png")
    on_exit(fn -> Storage.delete(storage_key) end)

    assert :ok =
             StorageKeyLock.with_storage_key_lock(storage_key, fn ->
               StorageCompensation.delete_force_tracked_or_enqueue(tracker, storage_key)
             end)

    assert {:ok, ^repaired_content} = Storage.download(storage_key)
    assert :ok = StorageCompensation.cleanup(tracker)
  end

  test "failed force delete inside a lock-owned transaction keeps cleanup ownership" do
    user = user_fixture()
    project = project_fixture(user)
    storage_key = "projects/#{project.id}/blobs/#{String.duplicate("d", 64)}.png"
    tracker = StorageCompensation.new()
    parent = self()

    assert {:ok, _url} = Storage.upload(storage_key, "corrupt", "image/png")
    on_exit(fn -> Storage.delete(storage_key) end)

    assert {:error, :storage_cleanup_requires_post_transaction} =
             StorageKeyLock.with_storage_key_lock(storage_key, fn ->
               StorageCompensation.delete_force_tracked_or_enqueue(tracker, storage_key,
                 delete_fun: fn ^storage_key -> {:error, :storage_unavailable} end,
                 delete_attempts: 1,
                 enqueue_fun: fn targets ->
                   send(parent, {:premature_force_cleanup_handoff, targets})
                   :ok
                 end
               )
             end)

    refute_receive {:premature_force_cleanup_handoff, _targets}

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn targets ->
                 send(parent, {:force_cleanup_enqueued, targets})
                 :ok
               end
             )

    assert_receive {:force_cleanup_enqueued, [cleanup_target]}
    assert String.ends_with?(cleanup_target, storage_key)
  end

  test "caller-owned transaction lock keeps force cleanup tracked until an inserted project rolls back" do
    user = user_fixture()
    repaired_content = "repaired before transaction rollback"
    hash = :sha256 |> :crypto.hash(repaired_content) |> Base.encode16(case: :lower)
    tracker = StorageCompensation.new()
    parent = self()

    assert {:error, {project_id, storage_key}} =
             Repo.transaction(fn ->
               project = project_fixture(user)
               storage_key = "projects/#{project.id}/blobs/#{hash}.png"

               assert {:ok, _url} = Storage.upload(storage_key, repaired_content, "image/png")
               on_exit(fn -> Storage.delete(storage_key) end)

               assert {:error, :storage_cleanup_requires_post_transaction} =
                        StorageKeyLock.with_storage_key_lock(storage_key, fn ->
                          StorageCompensation.delete_force_tracked_or_enqueue(tracker, storage_key)
                        end)

               Repo.rollback({project.id, storage_key})
             end)

    refute Repo.get(Project, project_id)

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn targets ->
                 send(parent, {:force_cleanup_enqueued, targets})
                 :ok
               end
             )

    assert_receive {:force_cleanup_enqueued, [cleanup_target]}
    assert :ok = StorageCompensation.delete_storage_keys([cleanup_target])
    assert {:error, :enoent} = Storage.download(storage_key)
  end

  test "a committed Asset row still protects its exact key from force cleanup" do
    user = user_fixture()
    project = project_fixture(user)
    storage_key = cleanup_asset_key("nonstandard-key", project.id)
    tracker = StorageCompensation.new()
    parent = self()

    _asset =
      asset_fixture(project, user, %{
        filename: "nonstandard-key.png",
        content_type: "image/png",
        size: byte_size("committed"),
        key: storage_key,
        url: Storage.get_url(storage_key)
      })

    assert {:ok, _url} = Storage.upload(storage_key, "committed", "image/png")
    on_exit(fn -> Storage.delete(storage_key) end)

    :ok = StorageCompensation.track_force_delete(tracker, storage_key)

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn targets ->
                 send(parent, {:force_cleanup_enqueued, targets})
                 :ok
               end
             )

    assert_receive {:force_cleanup_enqueued, [cleanup_target]}
    assert :ok = StorageCompensation.delete_storage_keys([cleanup_target])
    assert {:ok, "committed"} = Storage.download(storage_key)
  end

  test "enqueues durable cleanup when an immediate delete fails" do
    storage_key = cleanup_blob_key("orphan")
    parent = self()

    assert :ok =
             StorageCompensation.delete_or_enqueue(storage_key,
               delete_fun: fn ^storage_key -> {:error, :temporarily_unavailable} end,
               delete_retry_delay_ms: 0,
               in_transaction?: false,
               enqueue_fun: fn keys ->
                 send(parent, {:cleanup_enqueued, keys})
                 :ok
               end
             )

    assert_receive {:cleanup_enqueued, [^storage_key]}
  end

  test "does not enqueue cleanup when an immediate deletion retry succeeds" do
    storage_key = cleanup_blob_key("recovered-orphan")
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
               in_transaction?: false,
               enqueue_fun: fn keys ->
                 send(parent, {:cleanup_enqueued, keys})
                 :ok
               end
             )

    assert Agent.get(attempts, & &1) == 2
    refute_receive {:cleanup_enqueued, _keys}
  end

  test "treats nonpositive delete attempts as one before enqueuing" do
    storage_key = cleanup_blob_key("no-retries-orphan")
    parent = self()
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    assert :ok =
             StorageCompensation.delete_or_enqueue(storage_key,
               delete_fun: fn ^storage_key ->
                 Agent.update(attempts, &(&1 + 1))
                 {:error, :temporarily_unavailable}
               end,
               delete_attempts: 0,
               in_transaction?: false,
               enqueue_fun: fn keys ->
                 send(parent, {:cleanup_enqueued, keys})
                 :ok
               end
             )

    assert Agent.get(attempts, & &1) == 1
    assert_receive {:cleanup_enqueued, [^storage_key]}
  end

  test "persists failed immediate cleanup when queue insertion also fails" do
    storage_key = cleanup_blob_key("persisted-orphan")

    assert :ok =
             StorageCompensation.delete_or_enqueue(storage_key,
               delete_fun: fn ^storage_key -> {:error, :temporarily_unavailable} end,
               delete_retry_delay_ms: 0,
               in_transaction?: false,
               enqueue_fun: fn [^storage_key] -> {:error, :oban_unavailable} end
             )

    assert %StorageCleanupRequest{storage_keys: [^storage_key]} =
             Repo.one(from request in StorageCleanupRequest, where: request.storage_keys == ^[storage_key])
  end

  test "untracks an object after handing failed deletion to durable cleanup" do
    tracker = StorageCompensation.new()
    storage_key = cleanup_blob_key("handed-off-orphan")
    parent = self()
    :ok = StorageCompensation.track(tracker, storage_key)

    assert :ok =
             StorageCompensation.delete_tracked_or_enqueue(tracker, storage_key,
               delete_fun: fn ^storage_key -> {:error, :storage_unavailable} end,
               delete_attempts: 1,
               in_transaction?: false,
               enqueue_fun: fn [^storage_key] ->
                 send(parent, {:cleanup_enqueued, storage_key})
                 :ok
               end
             )

    assert_receive {:cleanup_enqueued, ^storage_key}

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:unexpected_tracker_cleanup, keys})
                 :ok
               end
             )

    refute_receive {:unexpected_tracker_cleanup, _keys}
  end

  test "keeps an object tracked when deletion and durable handoff both fail" do
    tracker = StorageCompensation.new()
    storage_key = cleanup_blob_key("unhanded-orphan")
    parent = self()
    :ok = StorageCompensation.track(tracker, storage_key)

    assert {:error, {:storage_cleanup_not_persisted, %{failed_keys: [^storage_key]}}} =
             StorageCompensation.delete_tracked_or_enqueue(tracker, storage_key,
               delete_fun: fn ^storage_key -> {:error, :storage_unavailable} end,
               delete_attempts: 1,
               in_transaction?: false,
               enqueue_fun: fn [^storage_key] -> {:error, :oban_unavailable} end,
               persist_fun: fn [^storage_key] -> {:error, :database_unavailable} end
             )

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:tracker_cleanup_retried, keys})
                 :ok
               end,
               delete_fun: fn keys -> {:error, keys} end
             )

    assert_receive {:tracker_cleanup_retried, [^storage_key]}
  end

  test "retains the tracker for cleanup after a transactional delete failure" do
    tracker = StorageCompensation.new()
    storage_key = cleanup_blob_key("transactional-orphan")
    parent = self()
    :ok = StorageCompensation.track(tracker, storage_key)

    assert {:error, :storage_cleanup_requires_post_transaction} =
             StorageCompensation.delete_tracked_or_enqueue(tracker, storage_key,
               delete_fun: fn ^storage_key -> {:error, :storage_unavailable} end,
               delete_attempts: 1,
               in_transaction?: true,
               enqueue_fun: fn [^storage_key] ->
                 send(parent, {:unexpected_transactional_enqueue, storage_key})
                 :ok
               end
             )

    refute_receive {:unexpected_transactional_enqueue, ^storage_key}

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:post_rollback_cleanup, keys})
                 :ok
               end,
               delete_fun: fn keys -> {:error, keys} end
             )

    assert_receive {:post_rollback_cleanup, [^storage_key]}
  end

  test "untracks an object deleted successfully inside a transaction" do
    tracker = StorageCompensation.new()
    storage_key = cleanup_blob_key("deleted-in-transaction")
    parent = self()
    :ok = StorageCompensation.track(tracker, storage_key)

    assert :ok =
             StorageCompensation.delete_tracked_or_enqueue(tracker, storage_key,
               delete_fun: fn ^storage_key -> :ok end,
               in_transaction?: true
             )

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:unexpected_cleanup, keys})
                 :ok
               end
             )

    refute_receive {:unexpected_cleanup, _keys}
  end

  test "deferred cleanup preserves content-addressed blobs for committed projects" do
    user = user_fixture()
    project = project_fixture(user)
    hash = String.duplicate("a", 64)
    storage_key = "projects/#{project.id}/blobs/#{hash}.png"

    assert {:ok, _url} = Storage.upload(storage_key, "adoptable", "image/png")
    on_exit(fn -> Storage.delete(storage_key) end)

    assert :ok = StorageCompensation.delete_storage_keys([storage_key])
    assert {:ok, "adoptable"} = Storage.download(storage_key)
  end

  test "deferred cleanup removes partial ready objects while their snapshot is not committed" do
    user = user_fixture()
    project = project_fixture(user)
    prefix = "projects/#{project.id}/snapshots/archives/v2/ready/PENDING123456789"
    storage_key = prefix <> "/snapshot.zip"

    pending_project_snapshot_fixture(project, %{version_number: 1, object_prefix: prefix})

    assert {:ok, _url} = Storage.upload(storage_key, "partial", "application/zip")
    assert :ok = StorageCompensation.delete_storage_keys([storage_key])
    assert {:error, :enoent} = Storage.download(storage_key)
  end

  test "deferred cleanup retains ready snapshot objects with durable accounting ownership" do
    user = user_fixture()
    project = project_fixture(user)
    prefix = "projects/#{project.id}/snapshots/archives/v2/ready/COMMITTED1234567"
    storage_key = prefix <> "/snapshot.zip"
    checksum = String.duplicate("a", 64)

    snapshot =
      full_project_snapshot_fixture(project, %{
        version_number: 1,
        object_prefix: prefix,
        archive_storage_key: storage_key,
        project_size_bytes: 1,
        project_checksum: checksum,
        manifest_size_bytes: 1,
        manifest_checksum: checksum,
        asset_blob_size_bytes: 0,
        asset_count: 0,
        blob_count: 0
      })

    assert {:ok, _url} = Storage.upload(storage_key, "p", "application/zip")
    on_exit(fn -> ObjectStorage.delete(storage_key) end)

    assert :ok = StorageCompensation.delete_storage_keys([storage_key])
    assert {:ok, "p"} = Storage.download(storage_key)

    snapshot
    |> Ecto.Changeset.change(integrity_state: "corrupt")
    |> Repo.update!()

    assert :ok = StorageCompensation.delete_storage_keys([storage_key])
    assert {:ok, "p"} = Storage.download(storage_key)
  end

  test "a published claim fences ready cleanup before snapshot accounting commits" do
    user = user_fixture()
    project = project_fixture(user)

    published_prefix =
      "projects/#{project.id}/snapshots/archives/v2/ready/PUBLISHEDCLAIM01"

    poisoned_prefix =
      "projects/#{project.id}/snapshots/archives/v2/ready/POISONEDCLAIM001"

    published_snapshot =
      pending_project_snapshot_fixture(project, %{
        version_number: 1,
        object_prefix: published_prefix
      })

    poisoned_snapshot =
      pending_project_snapshot_fixture(project, %{
        version_number: 2,
        object_prefix: poisoned_prefix
      })

    insert_snapshot_publication_claim!(project, published_snapshot, "published")
    insert_snapshot_publication_claim!(project, poisoned_snapshot, "poisoned")

    published_key = published_prefix <> "/snapshot.zip"
    poisoned_key = poisoned_prefix <> "/snapshot.zip"

    assert {:ok, _url} = Storage.upload(published_key, "published", "application/zip")
    assert {:ok, _url} = Storage.upload(poisoned_key, "poisoned", "application/zip")

    on_exit(fn ->
      ObjectStorage.delete(published_key)
      ObjectStorage.delete(poisoned_key)
    end)

    assert :ok = StorageCompensation.delete_storage_keys([published_key])
    assert {:ok, "published"} = Storage.download(published_key)

    assert :ok = StorageCompensation.delete_storage_keys([poisoned_key])
    assert {:error, :enoent} = Storage.download(poisoned_key)
  end

  test "deferred cleanup preserves unique storage adopted by a committed asset" do
    user = user_fixture()
    project = project_fixture(user)

    storage_key =
      "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/commit-ack.png"

    _asset =
      asset_fixture(project, user, %{
        filename: "commit-ack.png",
        content_type: "image/png",
        size: byte_size("committed"),
        key: storage_key,
        url: Storage.get_url(storage_key)
      })

    assert {:ok, _url} = Storage.upload(storage_key, "committed", "image/png")
    on_exit(fn -> Storage.delete(storage_key) end)

    assert :ok = StorageCompensation.delete_storage_keys([storage_key])
    assert {:ok, "committed"} = Storage.download(storage_key)
  end

  test "deferred cleanup deletes unique asset storage with no database owner" do
    missing_project_id = 9_100_000_000 + System.unique_integer([:positive])

    storage_key =
      "projects/#{missing_project_id}/assets/#{Ecto.UUID.generate()}/orphan.png"

    assert {:ok, _url} = Storage.upload(storage_key, "orphan", "image/png")
    on_exit(fn -> Storage.delete(storage_key) end)

    assert :ok = StorageCompensation.delete_storage_keys([storage_key])
    assert {:error, :enoent} = Storage.download(storage_key)
  end

  test "stale normal and force cleanup defer while a later restore owns the exact keys" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = full_project_snapshot_fixture(project)

    normal_key =
      "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/normal-cleanup.png"

    force_key =
      "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/force-cleanup.png"

    transactional_key =
      "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/transactional-cleanup.png"

    assert {:ok, _url} = Storage.upload(normal_key, "normal", "image/png")
    assert {:ok, _url} = Storage.upload(force_key, "force", "image/png")
    assert {:ok, _url} = Storage.upload(transactional_key, "transactional", "image/png")

    on_exit(fn ->
      ObjectStorage.delete(normal_key)
      ObjectStorage.delete(force_key)
      ObjectStorage.delete(transactional_key)
    end)

    reservation =
      insert_active_restore_reservation!(project, snapshot, [
        normal_key,
        force_key,
        transactional_key
      ])

    force_tracker = StorageCompensation.new()
    :ok = StorageCompensation.track_force_delete(force_tracker, force_key)
    [force_target] = StorageCompensation.pending_cleanup_targets(force_tracker)
    transactional_tracker = StorageCompensation.new()
    :ok = StorageCompensation.track(transactional_tracker, transactional_key)

    assert {:error, [^normal_key]} = StorageCompensation.delete_storage_keys([normal_key])
    assert {:error, [^force_target]} = StorageCompensation.delete_storage_keys([force_target])

    assert {:ok, {:error, :storage_cleanup_requires_post_transaction}} =
             Repo.transaction(fn ->
               StorageCompensation.delete_tracked_or_enqueue(
                 transactional_tracker,
                 transactional_key,
                 delete_attempts: 1
               )
             end)

    assert {:ok, "normal"} = Storage.download(normal_key)
    assert {:ok, "force"} = Storage.download(force_key)
    assert {:ok, "transactional"} = Storage.download(transactional_key)

    cleanup_request =
      Repo.insert!(%StorageCleanupRequest{
        storage_keys: [normal_key, force_key, transactional_key]
      })

    now = TimeHelpers.now()

    reservation
    |> StorageReservation.release_changeset("restore attempt settled", %{
      generation: reservation.generation + 1,
      settled_at: now,
      cleanup_status: "owned",
      cleanup_reference: "storage_cleanup_request:#{cleanup_request.id}",
      accounting_version: 1,
      accounting_measured_at: now
    })
    |> Repo.update!()

    assert :ok = StorageCompensation.delete_storage_keys([normal_key])
    assert :ok = StorageCompensation.delete_storage_keys([force_target])

    assert {:ok, :ok} =
             Repo.transaction(fn ->
               StorageCompensation.delete_tracked_or_enqueue(
                 transactional_tracker,
                 transactional_key,
                 delete_attempts: 1
               )
             end)

    assert {:error, :enoent} = Storage.download(normal_key)
    assert {:error, :enoent} = Storage.download(force_key)
    assert {:error, :enoent} = Storage.download(transactional_key)
    assert :ok = StorageCompensation.cleanup(transactional_tracker)
  end

  test "rollback cleanup bypasses only its exact restore reservation owner" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = full_project_snapshot_fixture(project)
    owned_key = cleanup_asset_key("owned-restore-rollback", project.id)
    concurrently_owned_key = cleanup_asset_key("concurrent-restore-rollback", project.id)

    assert {:ok, _url} = Storage.upload(owned_key, "owned", "image/png")
    assert {:ok, _url} = Storage.upload(concurrently_owned_key, "concurrent", "image/png")

    on_exit(fn ->
      ObjectStorage.delete(owned_key)
      ObjectStorage.delete(concurrently_owned_key)
    end)

    platform_owner =
      insert_active_restore_reservation!(project, snapshot, [
        owned_key,
        concurrently_owned_key
      ])

    owner = Repo.get!(StorageReservationRecord, platform_owner.id)

    _concurrent_owner =
      insert_active_restore_reservation!(project, snapshot, [concurrently_owned_key])

    tracker = StorageCompensation.new()
    :ok = StorageCompensation.track_force_delete(tracker, owned_key)
    :ok = StorageCompensation.track_force_delete(tracker, concurrently_owned_key)

    [owned_target, concurrent_target] =
      tracker
      |> StorageCompensation.pending_cleanup_targets()
      |> Enum.sort_by(&String.contains?(&1, "concurrent-restore-rollback"))

    assert {:error, [^concurrent_target]} =
             StorageCompensation.delete_storage_keys(
               [owned_target, concurrent_target],
               restore_cleanup_owner: owner
             )

    assert {:error, :enoent} = Storage.download(owned_key)
    assert {:ok, "concurrent"} = Storage.download(concurrently_owned_key)
  end

  test "deferred cleanup deletes content-addressed blobs whose project rolled back" do
    missing_project_id = 9_000_000_000 + System.unique_integer([:positive])
    hash = String.duplicate("b", 64)
    storage_key = "projects/#{missing_project_id}/blobs/#{hash}.png"

    assert {:ok, _url} = Storage.upload(storage_key, "orphan", "image/png")
    on_exit(fn -> Storage.delete(storage_key) end)

    assert :ok = StorageCompensation.delete_storage_keys([storage_key])
    assert {:error, :enoent} = Storage.download(storage_key)
  end

  test "deferred cleanup preserves imported template artifacts adopted by a committed version" do
    user = user_fixture()
    project = project_fixture(user)
    suffix = "commit-ack-#{System.unique_integer([:positive])}"
    snapshot_key = "project_templates/imports/portable/#{suffix}/snapshot.json.gz"
    manifest_key = "project_templates/imports/portable/#{suffix}/asset-manifest.json.gz"

    imported_blob_key =
      "project_templates/imported_blobs/portable/#{suffix}/#{String.duplicate("d", 64)}/portrait.png"

    template =
      %ProjectTemplate{owner_id: user.id, source_project_id: project.id}
      |> ProjectTemplate.create_changeset(%{
        "name" => "Portable",
        "slug" => "portable-#{suffix}",
        "visibility" => "private",
        "status" => "active"
      })
      |> Repo.insert!()

    _version =
      %ProjectTemplateVersion{
        project_template_id: template.id,
        source_project_id: project.id,
        published_by_id: user.id
      }
      |> ProjectTemplateVersion.create_changeset(%{
        "version_number" => 1,
        "snapshot_storage_key" => snapshot_key,
        "asset_manifest_storage_key" => manifest_key,
        "checksum" => String.duplicate("e", 64),
        "entity_counts" => %{},
        "preview" => %{},
        "audit_report" => %{},
        "published_at" => DateTime.utc_now(:second)
      })
      |> Repo.insert!()

    for key <- [snapshot_key, manifest_key, imported_blob_key] do
      assert {:ok, _url} = Storage.upload(key, "committed", "application/octet-stream")
      on_exit(fn -> Storage.delete(key) end)
    end

    assert :ok =
             StorageCompensation.delete_storage_keys([
               snapshot_key,
               manifest_key,
               imported_blob_key
             ])

    for key <- [snapshot_key, manifest_key, imported_blob_key] do
      assert {:ok, "committed"} = Storage.download(key)
    end
  end

  test "deferred cleanup preserves publication artifacts adopted by a committed version" do
    user = user_fixture()
    project = project_fixture(user)
    publication_id = System.unique_integer([:positive])
    snapshot_key = "project_template_publications/#{publication_id}/snapshot-deadbeef.json.gz"

    manifest_key =
      "project_template_publications/#{publication_id}/asset-manifest-cafebabe.json.gz"

    template =
      %ProjectTemplate{owner_id: user.id, source_project_id: project.id}
      |> ProjectTemplate.create_changeset(%{
        "name" => "Published",
        "slug" => "published-#{publication_id}",
        "visibility" => "private",
        "status" => "active"
      })
      |> Repo.insert!()

    _version =
      %ProjectTemplateVersion{
        project_template_id: template.id,
        source_project_id: project.id,
        published_by_id: user.id
      }
      |> ProjectTemplateVersion.create_changeset(%{
        "version_number" => 1,
        "snapshot_storage_key" => snapshot_key,
        "asset_manifest_storage_key" => manifest_key,
        "checksum" => String.duplicate("a", 64),
        "entity_counts" => %{},
        "preview" => %{},
        "audit_report" => %{},
        "published_at" => DateTime.utc_now(:second)
      })
      |> Repo.insert!()

    for key <- [snapshot_key, manifest_key] do
      assert {:ok, _url} = Storage.upload(key, "committed", "application/octet-stream")
      on_exit(fn -> Storage.delete(key) end)
    end

    assert :ok = StorageCompensation.delete_storage_keys([snapshot_key, manifest_key])

    for key <- [snapshot_key, manifest_key] do
      assert {:ok, "committed"} = Storage.download(key)
    end
  end

  test "deferred cleanup preserves artifacts adopted directly by a committed publication" do
    user = user_fixture()
    project = project_fixture(user)

    publication =
      %ProjectTemplatePublication{
        owner_id: user.id,
        requested_by_id: user.id,
        source_project_id: project.id
      }
      |> ProjectTemplatePublication.create_changeset(%{
        "mode" => "new",
        "status" => "queued",
        "name" => "Committed publication"
      })
      |> Repo.insert!()

    snapshot_key =
      "project_template_publications/#{publication.id}/snapshot-deadbeef.json.gz"

    manifest_key =
      "project_template_publications/#{publication.id}/asset-manifest-cafebabe.json.gz"

    _publication =
      publication
      |> Ecto.Changeset.change(
        status: "published",
        snapshot_storage_key: snapshot_key,
        asset_manifest_storage_key: manifest_key,
        checksum: String.duplicate("a", 64),
        completed_at: DateTime.utc_now(:second)
      )
      |> Repo.update!()

    for key <- [snapshot_key, manifest_key] do
      assert {:ok, _url} = Storage.upload(key, "committed", "application/octet-stream")
      on_exit(fn -> Storage.delete(key) end)
    end

    assert :ok = StorageCompensation.delete_storage_keys([snapshot_key, manifest_key])

    for key <- [snapshot_key, manifest_key] do
      assert {:ok, "committed"} = Storage.download(key)
    end
  end

  test "deferred cleanup deletes unreferenced publication artifacts" do
    publication_id = System.unique_integer([:positive])

    storage_keys = [
      "project_template_publications/#{publication_id}/snapshot-deadbeef.json.gz",
      "project_template_publications/#{publication_id}/asset-manifest-cafebabe.json.gz"
    ]

    for key <- storage_keys do
      assert {:ok, _url} = Storage.upload(key, "orphan", "application/octet-stream")
      on_exit(fn -> Storage.delete(key) end)
    end

    assert :ok = StorageCompensation.delete_storage_keys(storage_keys)

    for key <- storage_keys do
      assert {:error, :enoent} = Storage.download(key)
    end
  end

  test "deferred cleanup deletes unreferenced imported template storage" do
    suffix = "rolled-back-#{System.unique_integer([:positive])}"

    storage_keys = [
      "project_templates/imports/portable/#{suffix}/snapshot.json.gz",
      "project_templates/imports/portable/#{suffix}/asset-manifest.json.gz",
      "project_templates/imported_blobs/portable/#{suffix}/#{String.duplicate("f", 64)}/portrait.png"
    ]

    for key <- storage_keys do
      assert {:ok, _url} = Storage.upload(key, "orphan", "application/octet-stream")
      on_exit(fn -> Storage.delete(key) end)
    end

    assert :ok = StorageCompensation.delete_storage_keys(storage_keys)

    for key <- storage_keys do
      assert {:error, :enoent} = Storage.download(key)
    end
  end

  test "deferred cleanup still deletes unique conditional-copy temporaries for committed projects" do
    user = user_fixture()
    project = project_fixture(user)
    asset_uuid = Ecto.UUID.generate()

    storage_keys = [
      "projects/#{project.id}/blobs/.storyarn-copy/AAAAAAAAAAAAAAAA",
      "projects/#{project.id}/assets/#{asset_uuid}/.storyarn-copy/BBBBBBBBBBBBBBBB"
    ]

    upload_dir =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()

    for storage_key <- storage_keys do
      path = Path.join(upload_dir, storage_key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "temporary")
      on_exit(fn -> Storage.delete(storage_key) end)
    end

    assert :ok = StorageCompensation.delete_storage_keys(storage_keys)

    for storage_key <- storage_keys do
      refute File.exists?(Path.join(upload_dir, storage_key))
    end
  end

  test "persists and deletes strictly scoped reservation namespace objects" do
    project_id = 9_300_000_000 + System.unique_integer([:positive])
    lease_token = Ecto.UUID.generate()

    storage_keys =
      for kind <- ~w(snapshot-build restore-staging snapshot-export),
          suffix <- ["payload.bin", "nested/metadata.json"] do
        "projects/#{project_id}/storage-reservations/v1/#{kind}/#{lease_token}/#{suffix}"
      end

    conditional_copy_key =
      "projects/#{project_id}/storage-reservations/v1/restore-staging/#{lease_token}/nested/.storyarn-copy/AAAAAAAAAAAAAAAA"

    for storage_key <- storage_keys do
      assert {:ok, _url} = Storage.upload(storage_key, "temporary", "application/octet-stream")
      on_exit(fn -> Storage.delete(storage_key) end)
    end

    upload_dir =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()

    conditional_copy_path = Path.join(upload_dir, conditional_copy_key)
    File.mkdir_p!(Path.dirname(conditional_copy_path))
    File.write!(conditional_copy_path, "conditional")
    on_exit(fn -> Storage.delete(conditional_copy_key) end)

    cleanup_keys = storage_keys ++ [conditional_copy_key]

    assert {:ok, %StorageCleanupRequest{storage_keys: persisted_keys}} =
             StorageCompensation.persist_cleanup_request(cleanup_keys)

    assert MapSet.new(persisted_keys) == MapSet.new(cleanup_keys)
    assert :ok = StorageCompensation.delete_storage_keys(cleanup_keys)

    for storage_key <- storage_keys do
      assert {:error, :enoent} = Storage.download(storage_key)
    end

    refute File.exists?(conditional_copy_path)
  end

  test "does not report planned snapshot lifecycle cleanup as a fallback" do
    parent = self()
    handler_id = "snapshot-lifecycle-cleanup-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :assets, :storage_compensation, :fallback_persisted],
        fn event, measurements, metadata, _config ->
          send(parent, {:fallback_persisted, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    owner_token = Ecto.UUID.generate()
    assert {:ok, provider_namespace_fingerprint} = Storage.namespace_fingerprint()
    token = "plannedCleanup01"

    storage_keys = [
      "projects/1/snapshots/archives/v2/ready/#{token}/manifest.json",
      "projects/1/snapshots/archives/v2/staging/#{token}/manifest.json"
    ]

    log =
      capture_log(fn ->
        assert {:ok,
                %StorageCleanupRequest{
                  id: cleanup_request_id,
                  owner_kind: "snapshot_lifecycle",
                  owner_token: ^owner_token,
                  provider_namespace_fingerprint: ^provider_namespace_fingerprint,
                  storage_keys: persisted_keys
                }} =
                 StorageCompensation.persist_snapshot_lifecycle_cleanup(
                   storage_keys,
                   owner_token,
                   provider_namespace_fingerprint
                 )

        assert MapSet.new(persisted_keys) == MapSet.new(storage_keys)
        assert :ok = StorageCompensation.retry_persisted_cleanup_requests()
        assert Repo.get(StorageCleanupRequest, cleanup_request_id)
      end)

    refute log =~ "fallback"
    refute_receive {:fallback_persisted, _, _, _}
  end

  test "delete_or_enqueue! raises when no durable cleanup path is available" do
    storage_key = cleanup_blob_key("unrecoverable-orphan")

    error =
      assert_raise StorageCleanupPersistenceError, fn ->
        StorageCompensation.delete_or_enqueue!(storage_key,
          delete_fun: fn ^storage_key -> {:error, :storage_unavailable} end,
          delete_attempts: 1,
          in_transaction?: false,
          enqueue_fun: fn [^storage_key] -> {:error, :oban_unavailable} end,
          persist_fun: fn [^storage_key] -> {:error, :database_unavailable} end
        )
      end

    assert {:storage_cleanup_not_persisted,
            %{
              failed_keys: [^storage_key],
              enqueue_error: :oban_unavailable,
              persistence_error: :database_unavailable
            }} = error.reason
  end

  test "delete_or_enqueue_all! attempts every key before raising aggregated failures" do
    storage_keys = [
      cleanup_asset_key("unrecoverable-one"),
      cleanup_blob_key("unrecoverable-two")
    ]

    {:ok, attempts} = Agent.start_link(fn -> [] end)

    error =
      assert_raise StorageCleanupPersistenceError, fn ->
        StorageCompensation.delete_or_enqueue_all!(storage_keys,
          delete_fun: fn storage_key ->
            Agent.update(attempts, &[storage_key | &1])
            {:error, :storage_unavailable}
          end,
          delete_attempts: 1,
          in_transaction?: false,
          enqueue_fun: fn _storage_keys -> {:error, :oban_unavailable} end,
          persist_fun: fn _storage_keys -> {:error, :database_unavailable} end
        )
      end

    assert Enum.sort(Agent.get(attempts, & &1)) == Enum.sort(storage_keys)

    assert {:storage_cleanup_failures, failures} = error.reason
    assert Enum.map(failures, &elem(&1, 0)) == storage_keys
    assert Enum.all?(failures, fn {_storage_key, reason} -> match?({:storage_cleanup_not_persisted, _}, reason) end)
  end

  test "accepts blob keys for deletion retries" do
    storage_key = cleanup_blob_key("deletion-retry-#{System.unique_integer([:positive])}")
    assert {:ok, _url} = Storage.upload(storage_key, "blob", "image/png")

    assert :ok = StorageCompensation.delete_storage_keys([storage_key])
    assert {:error, :enoent} = Storage.download(storage_key)
  end

  test "rejects malformed project keys before immediate deletion or durable enqueue" do
    hash = String.duplicate("a", 64)
    uuid = Ecto.UUID.generate()
    lease_token = Ecto.UUID.generate()
    reservation_prefix = "projects/1/storage-reservations/v1/restore-staging/#{lease_token}"

    invalid_keys = [
      "projects/01/blobs/#{hash}.png",
      "projects/9223372036854775808/blobs/#{hash}.png",
      "projects/1/blobs/#{String.upcase(hash)}.png",
      "projects/1/blobs/#{hash}...",
      "projects/1/blobs/#{hash}.pn\\g",
      "projects/1/blobs/#{hash}.png#{<<0>>}",
      "projects/1/assets/not-a-uuid/file.png",
      "projects/1/assets/#{uuid}/.storyarn-copy",
      "projects/1/assets/#{uuid}/nested/file.png",
      "projects/1/archive/assets/#{uuid}/file.png",
      "project_templates/imported_blobs/../run/#{hash}/file.png",
      "project_templates/imported_blobs/demo/../#{hash}/file.png",
      "project_templates/imported_blobs/demo/run/#{String.upcase(hash)}/file.png",
      "project_templates/imported_blobs/demo/run/#{hash}/Unsafe Name.png",
      "project_templates/imported_blobs/demo/run/#{hash}/nested/file.png",
      "project_templates/imports/../run/snapshot.json.gz",
      "project_templates/imports/demo/../snapshot.json.gz",
      "project_templates/imports/demo/run/snapshot.json.gz.bak",
      "projects/01/storage-reservations/v1/restore-staging/#{lease_token}/payload.bin",
      "projects/9223372036854775808/storage-reservations/v1/restore-staging/#{lease_token}/payload.bin",
      "projects/1/storage-reservations/v2/restore-staging/#{lease_token}/payload.bin",
      "projects/1/storage-reservations/v1/unknown/#{lease_token}/payload.bin",
      "projects/1/storage-reservations/v1/restore_staging/#{lease_token}/payload.bin",
      "projects/1/storage-reservations/v1/restore-staging/not-a-uuid/payload.bin",
      "projects/1/storage-reservations/v1/restore-staging/AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA/payload.bin",
      reservation_prefix,
      reservation_prefix <> "/",
      reservation_prefix <> "/../payload.bin",
      reservation_prefix <> "/nested//payload.bin",
      reservation_prefix <> "/unsafe name.bin",
      reservation_prefix <> "/nested\\payload.bin",
      reservation_prefix <> "/#{String.duplicate("a", 129)}",
      reservation_prefix <> "/#{Enum.join(List.duplicate(String.duplicate("a", 110), 5), "/")}",
      reservation_prefix <> "/#{Enum.join(List.duplicate("part", 17), "/")}",
      reservation_prefix <> "/.storyarn-copy",
      reservation_prefix <> "/.storyarn-copy/short",
      reservation_prefix <> "/.storyarn-copy/AAAAAAAAAAAAAAAA/extra",
      reservation_prefix <> "/nested/.storyarn-copy/AAAAAAAAAAAAAAAA/extra"
    ]

    for storage_key <- invalid_keys do
      assert {:error, :invalid_storage_key} =
               StorageCompensation.delete_or_enqueue(storage_key,
                 delete_fun: fn key ->
                   send(self(), {:unexpected_delete, key})
                   :ok
                 end
               )
    end

    assert :ok =
             StorageCompensation.enqueue_cleanup(invalid_keys,
               insert_fun: fn keys ->
                 send(self(), {:unexpected_enqueue, keys})
                 :ok
               end
             )

    assert {:error, :no_valid_storage_keys} =
             StorageCompensation.persist_cleanup_request(invalid_keys)

    refute_receive {:unexpected_delete, _key}
    refute_receive {:unexpected_enqueue, _keys}
  end

  test "does not delete a safe but non-canonical project object" do
    storage_key =
      "projects/1/archive/assets/unintended-#{System.unique_integer([:positive])}.png"

    assert {:ok, _url} = Storage.upload(storage_key, "unintended", "image/png")
    on_exit(fn -> Storage.delete(storage_key) end)

    assert :ok = StorageCompensation.delete_storage_keys([storage_key])
    assert {:ok, "unintended"} = Storage.download(storage_key)
  end

  test "rotates a failing persisted request so newer cleanup is not starved" do
    blocked_key = cleanup_asset_key("blocked")
    removable_key = cleanup_asset_key("removable")

    upload_dir =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()

    blocked_path = Path.join(upload_dir, blocked_key)

    File.mkdir_p!(blocked_path)
    assert {:ok, _url} = Storage.upload(removable_key, "removable", "image/png")

    on_exit(fn ->
      File.rmdir(blocked_path)
      Storage.delete(removable_key)
    end)

    blocked_request = Repo.insert!(%StorageCleanupRequest{storage_keys: [blocked_key]})
    removable_request = Repo.insert!(%StorageCleanupRequest{storage_keys: [removable_key]})

    assert {:error, 1} = StorageCompensation.retry_persisted_cleanup_requests(1)
    refute Repo.get(StorageCleanupRequest, blocked_request.id)
    assert Repo.get(StorageCleanupRequest, removable_request.id)

    assert :ok = StorageCompensation.retry_persisted_cleanup_requests(1)
    refute Repo.get(StorageCleanupRequest, removable_request.id)
    assert {:error, :enoent} = Storage.download(removable_key)
  end

  test "keeps v2 cleanup receipt through empty, late multipart, and a second durable empty pass" do
    token = "QuiescenceTest01"

    storage_keys = [
      "projects/1/snapshots/archives/v2/staging/#{token}/snapshot.zip",
      "projects/1/snapshots/archives/v2/staging/#{token}/manifest.json"
    ]

    request = Repo.insert!(%StorageCleanupRequest{storage_keys: storage_keys})

    {:ok, provider} =
      Agent.start_link(fn ->
        %{aborted_count: 0, delete_calls: 0, inventory_calls: 0, inventory: :empty}
      end)

    delete_fun = fn ^storage_keys ->
      Agent.get_and_update(provider, fn state ->
        result = {:ok, %{aborted_count: state.aborted_count}}
        {result, Map.update!(state, :delete_calls, fn count -> count + 1 end)}
      end)
    end

    inventory_fun = fn storage_key ->
      assert storage_key in storage_keys

      Agent.get_and_update(provider, fn state ->
        result =
          case state.inventory do
            :empty -> {:ok, 0}
            :late -> {:ok, 1}
            :error -> {:error, :provider_unavailable}
          end

        {result, Map.update!(state, :inventory_calls, fn count -> count + 1 end)}
      end)
    end

    retry_opts = [delete_fun: delete_fun, inventory_fun: inventory_fun]

    assert :ok = StorageCompensation.retry_persisted_cleanup_requests(100, retry_opts)

    assert %StorageCleanupRequest{
             multipart_quiescence_started_at: %DateTime{},
             multipart_quiescence_not_before: %DateTime{}
           } = Repo.get!(StorageCleanupRequest, request.id)

    assert Agent.get(provider, &Map.take(&1, [:delete_calls, :inventory_calls])) == %{
             delete_calls: 1,
             inventory_calls: 0
           }

    assert :ok = StorageCompensation.retry_persisted_cleanup_requests(100, retry_opts)

    assert Agent.get(provider, &Map.take(&1, [:delete_calls, :inventory_calls])) == %{
             delete_calls: 1,
             inventory_calls: 0
           }

    expire_multipart_quiescence!(request.id)
    failed_markers = cleanup_request_quiescence(request.id)
    Agent.update(provider, &Map.put(&1, :inventory, :error))

    assert {:error, 1} = StorageCompensation.retry_persisted_cleanup_requests(100, retry_opts)
    assert cleanup_request_quiescence(request.id) == failed_markers

    Agent.update(provider, &Map.put(&1, :inventory, :late))
    assert :ok = StorageCompensation.retry_persisted_cleanup_requests(100, retry_opts)

    reset_markers = cleanup_request_quiescence(request.id)
    refute reset_markers == failed_markers

    assert Agent.get(provider, &Map.take(&1, [:delete_calls, :inventory_calls])) == %{
             delete_calls: 2,
             inventory_calls: 3
           }

    assert :ok = StorageCompensation.retry_persisted_cleanup_requests(100, retry_opts)

    assert Agent.get(provider, &Map.take(&1, [:delete_calls, :inventory_calls])) == %{
             delete_calls: 2,
             inventory_calls: 3
           }

    expire_multipart_quiescence!(request.id)
    expired_after_late_markers = cleanup_request_quiescence(request.id)
    Agent.update(provider, &Map.put(&1, :inventory, :empty))
    Agent.update(provider, &Map.put(&1, :aborted_count, 1))

    assert :ok = StorageCompensation.retry_persisted_cleanup_requests(100, retry_opts)
    assert Repo.get(StorageCleanupRequest, request.id)

    post_inventory_abort_markers = cleanup_request_quiescence(request.id)
    refute post_inventory_abort_markers == expired_after_late_markers

    assert Agent.get(provider, &Map.take(&1, [:delete_calls, :inventory_calls])) == %{
             delete_calls: 3,
             inventory_calls: 5
           }

    assert :ok = StorageCompensation.retry_persisted_cleanup_requests(100, retry_opts)

    assert Agent.get(provider, &Map.take(&1, [:delete_calls, :inventory_calls])) == %{
             delete_calls: 3,
             inventory_calls: 5
           }

    expire_multipart_quiescence!(request.id)
    Agent.update(provider, &Map.put(&1, :aborted_count, 0))

    assert :ok = StorageCompensation.retry_persisted_cleanup_requests(100, retry_opts)
    refute Repo.get(StorageCleanupRequest, request.id)

    assert Agent.get(provider, &Map.take(&1, [:delete_calls, :inventory_calls])) == %{
             delete_calls: 4,
             inventory_calls: 7
           }
  end

  test "does not consume a compensation receipt whose quiescence window resets before confirm" do
    key = "projects/1/snapshots/archives/v2/staging/QuiescenceRace01/snapshot.zip"
    now = TimeHelpers.now()

    request =
      Repo.insert!(%StorageCleanupRequest{
        storage_keys: [key],
        multipart_quiescence_started_at: DateTime.add(now, -2, :second),
        multipart_quiescence_not_before: DateTime.add(now, -1, :second)
      })

    test_process = self()

    cleanup =
      Task.async(fn ->
        StorageCompensation.delete_cleanup_request_keys(request.id, [key],
          consume?: true,
          inventory_fun: fn ^key -> {:ok, 0} end,
          delete_fun: fn [^key] ->
            send(test_process, :multipart_delete_ready_to_confirm)
            receive do: (:confirm -> {:ok, %{aborted_count: 0}})
          end
        )
      end)

    assert_receive :multipart_delete_ready_to_confirm

    reset_started_at = TimeHelpers.now()
    reset_not_before = DateTime.add(reset_started_at, Storage.multipart_cleanup_quiescence_seconds(), :second)

    {1, nil} =
      Repo.update_all(
        from(row in StorageCleanupRequest, where: row.id == ^request.id),
        set: [
          multipart_quiescence_started_at: reset_started_at,
          multipart_quiescence_not_before: reset_not_before
        ]
      )

    send(cleanup.pid, :confirm)

    assert {:deferred, seconds} = Task.await(cleanup)

    quiescence_seconds = Storage.multipart_cleanup_quiescence_seconds()
    assert seconds in (quiescence_seconds - 1)..quiescence_seconds

    assert %StorageCleanupRequest{
             multipart_quiescence_started_at: ^reset_started_at,
             multipart_quiescence_not_before: ^reset_not_before
           } = Repo.get!(StorageCleanupRequest, request.id)
  end

  defp insert_snapshot_publication_claim!(project, snapshot, status) do
    lease_token = Ecto.UUID.generate()
    now = TimeHelpers.now()

    reservation =
      Repo.insert!(%StorageReservation{
        workspace_id: project.workspace_id,
        project_id: project.id,
        project_snapshot_id: snapshot.id,
        workspace_id_snapshot: project.workspace_id,
        project_id_snapshot: project.id,
        project_snapshot_id_snapshot: snapshot.id,
        idempotency_key: "storage-compensation-claim:#{Ecto.UUID.generate()}",
        kind: "snapshot_build",
        status: "active",
        storage_namespace: "projects/#{project.id}/storage-reservations/v1/snapshot-build/#{lease_token}",
        cleanup_object_prefix: snapshot.object_prefix,
        reserved_bytes: 1,
        lease_token: lease_token,
        generation: 1,
        expires_at: DateTime.add(now, 3_600, :second),
        accounting_version: 1,
        accounting_measured_at: now,
        inserted_at: now,
        updated_at: now
      })

    Repo.insert!(%SnapshotObjectPublicationClaim{
      object_prefix: snapshot.object_prefix,
      claim_token: Ecto.UUID.generate(),
      inventory_digest: String.duplicate("d", 64),
      storage_reservation_id_snapshot: reservation.id,
      storage_reservation_lease_token: reservation.lease_token,
      status: status,
      lease_expires_at: nil,
      inserted_at: now,
      updated_at: now
    })
  end

  defp cleanup_asset_key(label, project_id \\ 1) do
    "projects/#{project_id}/assets/#{Ecto.UUID.generate()}/#{label}.png"
  end

  defp insert_active_restore_reservation!(project, snapshot, cleanup_storage_keys) do
    lease_token = Ecto.UUID.generate()
    now = TimeHelpers.now()

    namespace =
      "projects/#{project.id}/storage-reservations/v1/restore-staging/#{lease_token}"

    reservation =
      %StorageReservation{}
      |> StorageReservation.create_changeset(%{
        workspace_id: project.workspace_id,
        project_id: project.id,
        project_snapshot_id: snapshot.id,
        idempotency_key: "storage-compensation-restore:#{lease_token}",
        kind: "restore_staging",
        storage_namespace: namespace,
        cleanup_object_prefix: namespace,
        reserved_bytes: 1,
        lease_token: lease_token,
        generation: 1,
        expires_at: DateTime.add(now, 3_600, :second),
        accounting_version: 1,
        accounting_measured_at: now
      })
      |> Repo.insert!()

    canonical_keys = Enum.sort(cleanup_storage_keys)
    digest = StorageCleanupInventory.digest(canonical_keys)

    reservation
    |> StorageReservation.storage_started_changeset(
      now,
      digest,
      length(canonical_keys),
      canonical_keys
    )
    |> Repo.update!()
  end

  defp cleanup_blob_key(label, project_id \\ 1) do
    hash = :sha256 |> :crypto.hash(label) |> Base.encode16(case: :lower)
    "projects/#{project_id}/blobs/#{hash}.png"
  end

  defp expire_multipart_quiescence!(cleanup_request_id) do
    now = TimeHelpers.now()

    {1, nil} =
      Repo.update_all(
        from(request in StorageCleanupRequest, where: request.id == ^cleanup_request_id),
        set: [
          multipart_quiescence_started_at: DateTime.add(now, -2, :second),
          multipart_quiescence_not_before: DateTime.add(now, -1, :second)
        ]
      )

    :ok
  end

  defp cleanup_request_quiescence(cleanup_request_id) do
    request = Repo.get!(StorageCleanupRequest, cleanup_request_id)
    {request.multipart_quiescence_started_at, request.multipart_quiescence_not_before}
  end
end
