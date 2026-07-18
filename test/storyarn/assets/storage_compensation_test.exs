defmodule Storyarn.Assets.StorageCompensationTest do
  use Storyarn.DataCase, async: true

  import ExUnit.CaptureLog
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupPersistenceError
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Assets.StorageKeyLock
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion

  test "retries cleanup job persistence before returning an error" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)
    storage_key = cleanup_asset_key("retry-persistence")

    insert_fun = fn _storage_keys ->
      attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})
      if attempt < 3, do: {:error, :database_unavailable}, else: {:ok, %{id: 1}}
    end

    log =
      capture_log(fn ->
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
      "project_templates/imports/demo/run/snapshot.json.gz.bak"
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

  defp cleanup_asset_key(label, project_id \\ 1) do
    "projects/#{project_id}/assets/#{Ecto.UUID.generate()}/#{label}.png"
  end

  defp cleanup_blob_key(label, project_id \\ 1) do
    hash = :sha256 |> :crypto.hash(label) |> Base.encode16(case: :lower)
    "projects/#{project_id}/blobs/#{hash}.png"
  end
end
