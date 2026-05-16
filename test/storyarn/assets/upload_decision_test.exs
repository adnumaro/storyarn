defmodule Storyarn.Assets.UploadDecisionTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
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
end
