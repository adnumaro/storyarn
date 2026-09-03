defmodule Storyarn.Workers.DeleteStorageObjectsWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  alias Storyarn.MultipartStorageSpy
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.StorageCleanupRequest
  alias Storyarn.Workers.DeleteStorageObjectsWorker

  @namespace_fingerprint String.duplicate("a", 64)

  test "moves exhausted storage cleanup to the recurring durable reconciler" do
    storage_key =
      "projects/1/assets/#{Ecto.UUID.generate()}/undeletable.png"

    storage_path =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()
      |> Path.join(storage_key)

    File.mkdir_p!(storage_path)
    on_exit(fn -> File.rmdir(storage_path) end)
    assert {:error, _reason} = File.rm(storage_path)

    job = %Oban.Job{
      args: %{"storage_keys" => [storage_key]},
      attempt: 5,
      max_attempts: 5
    }

    assert :ok = DeleteStorageObjectsWorker.perform(job)

    assert %StorageCleanupRequest{storage_keys: [^storage_key]} =
             Repo.one(from request in StorageCleanupRequest, where: request.storage_keys == ^[storage_key])
  end

  test "preserves force-delete intent when exhausted cleanup moves to the outbox" do
    storage_key =
      "projects/1/blobs/#{String.duplicate("a", 64)}.png"

    cleanup_target = "__storyarn_force_delete__:" <> storage_key

    storage_path =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()
      |> Path.join(storage_key)

    File.mkdir_p!(storage_path)
    on_exit(fn -> File.rmdir(storage_path) end)
    assert {:error, _reason} = File.rm(storage_path)

    job = %Oban.Job{
      args: %{"storage_keys" => [cleanup_target]},
      attempt: 5,
      max_attempts: 5
    }

    assert :ok = DeleteStorageObjectsWorker.perform(job)

    assert %StorageCleanupRequest{storage_keys: [^cleanup_target]} =
             Repo.one(
               from request in StorageCleanupRequest,
                 where: request.storage_keys == ^[cleanup_target]
             )
  end

  test "uses the bounded storage cleanup queue" do
    storage_key = "projects/1/assets/#{Ecto.UUID.generate()}/queued.png"

    assert %{changes: %{queue: "storage_cleanup"}} =
             DeleteStorageObjectsWorker.new(%{"storage_keys" => [storage_key]})
  end

  test "a legacy multipart delivery establishes the exact durable handoff without touching the provider" do
    original_storage = Application.fetch_env!(:storyarn, :storage)
    Application.put_env(:storyarn, :storage, adapter: MultipartStorageSpy)
    on_exit(fn -> Application.put_env(:storyarn, :storage, original_storage) end)

    storage_key =
      "projects/1/snapshots/archives/v2/staging/LegacyCutover001/snapshot.zip"

    job = %Oban.Job{args: %{"storage_keys" => [storage_key]}}

    assert :ok = DeleteStorageObjectsWorker.perform(job)

    assert %StorageCleanupRequest{
             storage_keys: [^storage_key],
             provider_namespace_fingerprint: @namespace_fingerprint,
             multipart_cleanup_phase: "discover"
           } = Repo.one(from request in StorageCleanupRequest, where: request.storage_keys == ^[storage_key])

    refute_received {:exact_multipart_inventory_dispatched, _, _}
    refute_received {:exact_multipart_abort_dispatched, _, _}
  end

  test "a persisted multipart backoff snoozes the same per-request delivery" do
    key = "projects/1/snapshots/archives/v2/staging/RetryBackoff0001/snapshot.zip"
    next_attempt_at = DateTime.add(TimeHelpers.now(), 60, :second)

    request =
      %StorageCleanupRequest{}
      |> StorageCleanupRequest.changeset(%{
        storage_keys: [key],
        provider_namespace_fingerprint: @namespace_fingerprint,
        multipart_cleanup_phase: "discover",
        multipart_cleanup_next_attempt_at: next_attempt_at
      })
      |> Repo.insert!()

    assert {:snooze, seconds} =
             DeleteStorageObjectsWorker.perform(%Oban.Job{
               args: %{"cleanup_request_id" => request.id}
             })

    assert seconds in 1..60
    assert Repo.get!(StorageCleanupRequest, request.id).multipart_cleanup_next_attempt_at == next_attempt_at
  end

  test "a blocked multipart request completes its delivery and remains visible" do
    key = "projects/1/snapshots/archives/v2/staging/BlockedCleanup01/snapshot.zip"

    request =
      %StorageCleanupRequest{}
      |> StorageCleanupRequest.changeset(%{
        storage_keys: [key],
        provider_namespace_fingerprint: @namespace_fingerprint,
        multipart_cleanup_phase: "blocked",
        multipart_cleanup_last_error_code: "multipart_residue_budget_exhausted"
      })
      |> Repo.insert!()

    assert :ok =
             DeleteStorageObjectsWorker.perform(%Oban.Job{
               args: %{"cleanup_request_id" => request.id}
             })

    assert Repo.get!(StorageCleanupRequest, request.id).multipart_cleanup_phase == "blocked"
  end

  test "per-request deliveries are unique while incomplete" do
    args = %{"cleanup_request_id" => System.unique_integer([:positive])}

    assert {:ok, %Oban.Job{conflict?: false}} = args |> DeleteStorageObjectsWorker.new() |> Oban.insert()
    assert {:ok, %Oban.Job{conflict?: true}} = args |> DeleteStorageObjectsWorker.new() |> Oban.insert()
  end
end
