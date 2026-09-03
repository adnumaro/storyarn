defmodule Storyarn.Workers.RetryStorageCleanupRequestsWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import ExUnit.CaptureLog

  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageCleanupRequest
  alias Storyarn.Workers.DeleteStorageObjectsWorker
  alias Storyarn.Workers.RetryStorageCleanupRequestsWorker

  test "enqueues one per-request delivery without touching object storage" do
    storage_key =
      "projects/1/assets/#{Ecto.UUID.generate()}/cleanup-test.png"

    assert {:ok, _url} = Storage.upload(storage_key, "copied asset", "image/png")
    on_exit(fn -> Storage.delete(storage_key) end)

    request = Repo.insert!(%StorageCleanupRequest{storage_keys: [storage_key]})

    handler_id = "retry-storage-cleanup-backlog-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :assets, :storage_compensation, :backlog],
        fn event, measurements, metadata, pid ->
          send(pid, {event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert :ok = perform_job(RetryStorageCleanupRequestsWorker, %{})
    assert Repo.get(StorageCleanupRequest, request.id)
    assert {:ok, "copied asset"} = Storage.download(storage_key)
    assert_enqueued(worker: DeleteStorageObjectsWorker, args: %{cleanup_request_id: request.id})

    assert_receive {
      [:storyarn, :assets, :storage_compensation, :backlog],
      %{
        pending_count: 1,
        due_count: 1,
        deferred_multipart_count: 0,
        observed_at_unix_seconds: observed_at
      },
      %{}
    }

    assert is_integer(observed_at)
  end

  test "does not enqueue a duplicate delivery for the same cleanup request" do
    storage_key = "projects/1/assets/#{Ecto.UUID.generate()}/deduplicated.png"
    request = Repo.insert!(%StorageCleanupRequest{storage_keys: [storage_key]})

    assert :ok = perform_job(RetryStorageCleanupRequestsWorker, %{})
    assert :ok = perform_job(RetryStorageCleanupRequestsWorker, %{})

    assert [job] =
             all_enqueued(
               worker: DeleteStorageObjectsWorker,
               args: %{cleanup_request_id: request.id}
             )

    assert job.state == "available"
  end

  test "collapses retry exceptions before they reach Oban or logs" do
    private_canary = "private-storage-key-and-provider-body"

    log =
      capture_log(fn ->
        assert {:error, :storage_cleanup_failed} =
                 RetryStorageCleanupRequestsWorker.perform_with(
                   %Oban.Job{attempt: 1, max_attempts: 5},
                   fn -> raise "provider failure #{private_canary}" end,
                   fn -> :ok end
                 )
      end)

    assert log =~ "Persisted copied asset cleanup failed"
    assert log =~ "RuntimeError"
    refute log =~ private_canary
  end

  test "collapses invalid retry results without inspecting them" do
    private_canary = "private-cleanup-result"

    log =
      capture_log(fn ->
        assert {:error, :storage_cleanup_failed} =
                 RetryStorageCleanupRequestsWorker.perform_with(
                   %Oban.Job{attempt: 1, max_attempts: 5},
                   fn -> {:unexpected, private_canary} end,
                   fn -> :ok end
                 )
      end)

    assert log =~ "returned an invalid result"
    refute log =~ private_canary
  end
end
