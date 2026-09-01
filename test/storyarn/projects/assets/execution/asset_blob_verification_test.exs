defmodule Storyarn.Projects.Assets.AssetBlobVerificationTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.AssetBlobVerification
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Assets.Storage

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project, user: user}
  end

  test "rejects an asset inventory spanning more than one project" do
    assert {:error, :invalid_asset_blob_inventory} =
             AssetBlobVerification.ensure_asset_blobs([
               %Asset{project_id: 1},
               %Asset{project_id: 2}
             ])
  end

  test "rejects conflicting snapshot identities for one blob hash", %{project: project} do
    blob_hash = String.duplicate("a", 64)

    assert {:error, :invalid_snapshot_asset_blob_inventory} =
             AssetBlobVerification.ensure_snapshot_asset_blobs(project.id, [
               snapshot_spec(blob_hash, 10, [1]),
               snapshot_spec(blob_hash, 11, [1])
             ])
  end

  test "reports a valid snapshot blob whose captured asset is absent", %{project: project} do
    blob_hash = String.duplicate("b", 64)

    assert {:error,
            {:snapshot_asset_blob_unavailable,
             %{
               asset_ids: [9_999_999_999],
               blob_hash: ^blob_hash,
               errors: [{nil, {:asset_blob_destination_missing, _storage_key}}]
             }}} =
             AssetBlobVerification.ensure_snapshot_asset_blobs(project.id, [
               snapshot_spec(blob_hash, 10, [9_999_999_999])
             ])
  end

  test "repairs a missing snapshot blob from the captured asset", %{project: project, user: user} do
    content = "captured snapshot asset bytes"

    assert {:ok, asset} =
             Assets.upload_binary_and_create_asset(
               content,
               %{filename: "snapshot.png", content_type: "image/png"},
               project,
               user
             )

    blob_key = BlobStore.blob_key(project.id, asset.blob_hash, "png")
    assert :ok = delete_storage_blob(blob_key)

    on_exit(fn ->
      Storage.delete(asset.key)
      delete_storage_blob(blob_key)
    end)

    assert {:ok, %{asset_count: 1, blob_count: 1, repaired_blob_count: 1}} =
             AssetBlobVerification.ensure_snapshot_asset_blobs(project.id, [
               snapshot_spec(asset.blob_hash, asset.size, [asset.id])
             ])

    assert {:ok, ^content} = Storage.download(blob_key)
  end

  defp snapshot_spec(blob_hash, size, asset_ids) do
    %{
      blob_hash: blob_hash,
      size: size,
      content_type: "image/png",
      sanitized_svg: false,
      asset_ids: asset_ids
    }
  end
end
