defmodule Storyarn.Projects.Versioning.SnapshotAssetCaptureTest do
  use Storyarn.DataCase, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Versioning.SnapshotAssetCapture
  alias Storyarn.Repo

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  test "materializes and rematerializes a zero-byte asset without health state", %{
    project: project,
    user: user
  } do
    asset = asset_fixture(project, user, %{filename: "empty.jpg"})
    hash = BlobStore.compute_hash("")
    assert {:ok, _url} = Storage.upload(asset.key, "", "image/jpeg")

    Repo.update_all(
      from(candidate in Asset, where: candidate.id == ^asset.id),
      set: [size: 0, blob_hash: hash]
    )

    raw = Repo.get!(Asset, asset.id)

    assert {:ok, %{raw_assets: [^raw], effective_assets: [effective]} = inventory} =
             SnapshotAssetCapture.materialize([raw], project.id)

    refute Map.has_key?(inventory, :invalid_asset_ids)
    assert effective.size == 0
    assert effective.blob_hash == hash
    assert :ok = SnapshotAssetCapture.rematerialize(inventory)

    on_exit(fn ->
      Storage.delete(raw.key)
      Storage.delete(effective.key)
    end)
  end

  test "repairs only the effective byte identity while retaining the raw row", %{
    project: project,
    user: user
  } do
    asset = asset_fixture(project, user, %{filename: "legacy.jpg"})
    assert {:ok, _url} = Storage.upload(asset.key, "legacy bytes", "image/jpeg")

    Repo.update_all(
      from(candidate in Asset, where: candidate.id == ^asset.id),
      set: [content_type: "application/x-legacy", size: 999, blob_hash: "legacy-hash"]
    )

    raw = Repo.get!(Asset, asset.id)

    assert {:ok, %{raw_assets: [^raw], effective_assets: [effective]}} =
             SnapshotAssetCapture.materialize([raw], project.id)

    assert raw.content_type == "application/x-legacy"
    assert raw.size == 999
    assert raw.blob_hash == "legacy-hash"
    assert effective.content_type == "image/jpeg"
    assert effective.size == byte_size("legacy bytes")
    assert effective.blob_hash == BlobStore.compute_hash("legacy bytes")

    on_exit(fn ->
      Storage.delete(raw.key)
      Storage.delete(effective.key)
    end)
  end
end
