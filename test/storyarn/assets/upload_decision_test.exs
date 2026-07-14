defmodule Storyarn.Assets.UploadDecisionTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.UploadPolicy
  alias Storyarn.Billing
  alias Storyarn.Repo

  @test_png_path "test/fixtures/images/quadrant_map.png"

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project, user: user}
  end

  test "reuses a source image and creates purpose-specific variants", %{
    project: project,
    user: user
  } do
    binary = File.read!(@test_png_path)
    source_hash = BlobStore.compute_hash(binary)

    assert {:ok, banner_asset, %{action: :created_variant}} =
             Assets.upload_binary_for_purpose(
               binary,
               %{filename: "source.png", content_type: "image/png", purpose: :banner},
               project,
               user
             )

    assert banner_asset.content_type == "image/webp"
    assert banner_asset.metadata["variant_profile"] == "sheet_banner_1920x640"
    assert banner_asset.metadata["source_blob_hash"] == source_hash

    assert {:ok, decision} =
             Assets.inspect_upload(project, %{
               "purpose" => "avatar",
               "hash" => source_hash,
               "size" => byte_size(binary),
               "width" => 1024,
               "height" => 768,
               "content_type" => "image/png",
               "filename" => "source.png"
             })

    assert decision.source_exists
    assert decision.requires_variant
    assert decision.action == :create_variant_from_existing_original

    assert {:ok, avatar_asset, %{action: :created_variant}} =
             Assets.materialize_upload_variant(project, user, %{
               "purpose" => "avatar",
               "hash" => source_hash
             })

    assert avatar_asset.content_type == "image/webp"
    assert avatar_asset.metadata["variant_profile"] == "sheet_avatar_500"
    assert avatar_asset.metadata["source_blob_hash"] == source_hash

    assert {:ok, repeated_decision} =
             Assets.inspect_upload(project, %{
               "purpose" => "avatar",
               "hash" => source_hash,
               "size" => byte_size(binary),
               "width" => 1024,
               "height" => 768,
               "content_type" => "image/png",
               "filename" => "source.png"
             })

    assert repeated_decision.action == :attach_existing_variant
    assert repeated_decision.asset_id == avatar_asset.id

    assert Repo.aggregate(from(a in Asset, where: a.project_id == ^project.id), :count) == 3

    project.id
    |> Assets.list_assets()
    |> Enum.each(&Assets.storage_delete(&1.key))
  end

  test "rejects oversized files during upload inspection", %{project: project} do
    assert {:error, :too_large} =
             Assets.inspect_upload(project, %{
               "purpose" => "scene_background",
               "hash" => String.duplicate("a", 64),
               "size" => UploadPolicy.max_file_size() + 1,
               "width" => 4096,
               "height" => 2160,
               "content_type" => "image/png",
               "filename" => "huge-background.png"
             })
  end

  test "reuses an existing purpose asset when storage is already full", %{
    project: project,
    user: user
  } do
    binary = File.read!(@test_png_path)

    assert {:ok, banner, %{action: :created_variant}} =
             Assets.upload_binary_for_purpose(
               binary,
               %{filename: "source.png", content_type: "image/png", purpose: :banner},
               project,
               user
             )

    stored_assets = Assets.list_assets(project.id)
    used = Enum.sum(Enum.map(stored_assets, & &1.size))
    storage_limit = Billing.plan_limit(Billing.default_plan(), :storage_bytes_per_workspace)
    insert_filler_asset(project, user, storage_limit - used)

    assert {:ok, reused_banner, %{action: :attach_existing_variant, reused: true}} =
             Assets.upload_binary_for_purpose(
               binary,
               %{filename: "source.png", content_type: "image/png", purpose: :banner},
               project,
               user
             )

    assert reused_banner.id == banner.id
    cleanup_asset_storage(stored_assets)
  end

  test "keeps a newly persisted original when a later variant exceeds storage", %{
    project: project,
    user: user
  } do
    binary = File.read!(@test_png_path)
    source_hash = BlobStore.compute_hash(binary)
    storage_limit = Billing.plan_limit(Billing.default_plan(), :storage_bytes_per_workspace)
    insert_filler_asset(project, user, storage_limit - byte_size(binary))

    assert {:error, :limit_reached, %{resource: :storage_bytes_per_workspace}} =
             Assets.upload_binary_for_purpose(
               binary,
               %{filename: "source.png", content_type: "image/png", purpose: :banner},
               project,
               user
             )

    original = Repo.one!(from(a in Asset, where: a.project_id == ^project.id and a.blob_hash == ^source_hash))
    assert {:ok, ^binary} = Storyarn.Assets.Storage.download(original.key)

    cleanup_asset_storage([original])
  end

  defp insert_filler_asset(project, user, size) do
    %Asset{}
    |> Ecto.Changeset.change(%{
      filename: "filler.bin",
      content_type: "application/octet-stream",
      size: size,
      key: "projects/#{project.id}/assets/filler.bin",
      url: "/uploads/projects/#{project.id}/assets/filler.bin",
      project_id: project.id,
      uploaded_by_id: user.id
    })
    |> Repo.insert!()
  end

  defp cleanup_asset_storage(assets) do
    Enum.each(assets, &Assets.storage_delete(&1.key))

    assets
    |> Enum.filter(& &1.blob_hash)
    |> Enum.map(fn asset ->
      BlobStore.blob_key(asset.project_id, asset.blob_hash, BlobStore.ext_from_content_type(asset.content_type))
    end)
    |> Enum.uniq()
    |> Enum.each(&Assets.storage_delete/1)
  end
end
