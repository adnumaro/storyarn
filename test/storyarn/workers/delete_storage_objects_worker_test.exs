defmodule Storyarn.Workers.DeleteStorageObjectsWorkerTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Workers.DeleteStorageObjectsWorker

  test "moves exhausted storage cleanup to the recurring durable reconciler" do
    storage_key =
      "projects/1/assets/undeletable-#{System.unique_integer([:positive])}/object.png"

    storage_path =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()
      |> Path.join(storage_key)

    File.mkdir_p!(storage_path)
    on_exit(fn -> File.rmdir(storage_path) end)

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
    assert %{changes: %{queue: "storage_cleanup"}} =
             DeleteStorageObjectsWorker.new(%{"storage_keys" => ["projects/1/assets/a/file.png"]})
  end
end
