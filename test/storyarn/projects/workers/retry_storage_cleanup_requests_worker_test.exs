defmodule Storyarn.Workers.RetryStorageCleanupRequestsWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import ExUnit.CaptureLog

  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageCleanupRequest
  alias Storyarn.Workers.RetryStorageCleanupRequestsWorker

  test "deletes copied objects and their durable cleanup request" do
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
    refute Repo.get(StorageCleanupRequest, request.id)
    assert {:error, :enoent} = Storage.download(storage_key)

    assert_receive {
      [:storyarn, :assets, :storage_compensation, :backlog],
      %{
        pending_count: 0,
        due_count: 0,
        deferred_multipart_count: 0,
        oldest_age_seconds: 0,
        observed_at_unix_seconds: observed_at
      },
      %{}
    }

    assert is_integer(observed_at)
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
