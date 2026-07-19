defmodule Storyarn.Workers.RetryStorageCleanupRequestsWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Workers.RetryStorageCleanupRequestsWorker

  test "deletes copied objects and their durable cleanup request" do
    storage_key =
      "projects/1/assets/#{Ecto.UUID.generate()}/cleanup-test.png"

    assert {:ok, _url} = Storage.upload(storage_key, "copied asset", "image/png")
    on_exit(fn -> Storage.delete(storage_key) end)

    request = Repo.insert!(%StorageCleanupRequest{storage_keys: [storage_key]})

    assert :ok = perform_job(RetryStorageCleanupRequestsWorker, %{})
    refute Repo.get(StorageCleanupRequest, request.id)
    assert {:error, :enoent} = Storage.download(storage_key)
  end
end
