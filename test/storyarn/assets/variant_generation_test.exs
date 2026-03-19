defmodule Storyarn.Assets.VariantGenerationTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Assets

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  @test_png_path "test/fixtures/images/quadrant_map.png"
  @test_jpg_path "test/fixtures/images/test_image.jpg"

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project, user: user}
  end

  describe "variant generation with purpose" do
    test "PNG upload with :gallery purpose triggers async variant", %{
      project: project,
      user: user
    } do
      binary = File.read!(@test_png_path)

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 binary,
                 %{filename: "scene.png", content_type: "image/png", purpose: :gallery},
                 project,
                 user
               )

      assert asset.content_type == "image/png"
      assert asset.project_id == project.id

      # Variant is generated async — wait briefly for the Task to complete
      Process.sleep(2000)

      # Reload the asset to check if metadata was updated with web_url
      updated = Assets.get_asset(project.id, asset.id)
      assert updated.metadata["web_url"] != nil
      assert updated.metadata["web_asset_id"] != nil

      # Cleanup
      Assets.storage_delete(asset.key)
      variant = Assets.get_asset(project.id, updated.metadata["web_asset_id"])
      if variant, do: Assets.storage_delete(variant.key)
    end

    test "JPEG upload with :gallery purpose skips variant", %{project: project, user: user} do
      binary = File.read!(@test_jpg_path)

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 binary,
                 %{filename: "photo.jpg", content_type: "image/jpeg", purpose: :gallery},
                 project,
                 user
               )

      # JPEG is already optimal for gallery — no variant
      Process.sleep(500)

      updated = Assets.get_asset(project.id, asset.id)
      assert updated.metadata["web_url"] == nil

      Assets.storage_delete(asset.key)
    end

    test "upload without purpose does not generate variant", %{project: project, user: user} do
      binary = File.read!(@test_png_path)

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 binary,
                 %{filename: "raw.png", content_type: "image/png"},
                 project,
                 user
               )

      Process.sleep(500)

      updated = Assets.get_asset(project.id, asset.id)
      assert updated.metadata["web_url"] == nil

      Assets.storage_delete(asset.key)
    end

    test "upload with skip_variants: true does not generate variant", %{
      project: project,
      user: user
    } do
      binary = File.read!(@test_png_path)

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 binary,
                 %{
                   filename: "skip.png",
                   content_type: "image/png",
                   purpose: :gallery,
                   skip_variants: true
                 },
                 project,
                 user
               )

      Process.sleep(500)

      updated = Assets.get_asset(project.id, asset.id)
      assert updated.metadata["web_url"] == nil

      Assets.storage_delete(asset.key)
    end

    test "PNG upload with :avatar purpose generates cropped WebP variant", %{
      project: project,
      user: user
    } do
      binary = File.read!(@test_png_path)

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 binary,
                 %{filename: "avatar.png", content_type: "image/png", purpose: :avatar},
                 project,
                 user
               )

      Process.sleep(2000)

      updated = Assets.get_asset(project.id, asset.id)
      assert updated.metadata["web_url"] != nil

      variant = Assets.get_asset(project.id, updated.metadata["web_asset_id"])
      assert variant != nil
      assert variant.content_type == "image/webp"
      assert variant.metadata["is_variant"] == true
      assert variant.metadata["original_asset_id"] == asset.id

      # Cleanup
      Assets.storage_delete(asset.key)
      Assets.storage_delete(variant.key)
    end

    test "non-image upload with purpose does not generate variant", %{
      project: project,
      user: user
    } do
      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 "fake audio content",
                 %{filename: "sound.mp3", content_type: "audio/mpeg", purpose: :gallery},
                 project,
                 user
               )

      Process.sleep(500)

      updated = Assets.get_asset(project.id, asset.id)
      assert updated.metadata["web_url"] == nil

      Assets.storage_delete(asset.key)
    end
  end
end
