defmodule StoryarnWeb.PrivateMediaTest do
  use StoryarnWeb.ConnCase, async: true

  alias Storyarn.Projects.Assets.Asset
  alias StoryarnWeb.PrivateMedia

  describe "asset_url/1" do
    test "uses the authenticated media route" do
      asset = %Asset{id: 42, url: "https://storage.example/private.png", metadata: %{}}

      assert PrivateMedia.asset_url(asset) == "/media/assets/42"
    end

    test "prefers the optimized variant asset" do
      asset = %Asset{
        id: 42,
        url: "https://storage.example/original.png",
        metadata: %{"web_asset_id" => 84, "web_url" => "https://storage.example/web.webp"}
      }

      assert PrivateMedia.asset_url(asset) == "/media/assets/84"
    end

    test "prefers the optimized variant for consumer-owned asset-shaped records" do
      asset_record = %{
        id: 42,
        filename: "original.png",
        metadata: %{"web_asset_id" => 84}
      }

      assert PrivateMedia.asset_url(asset_record) == "/media/assets/84"
    end

    test "returns nil without an asset" do
      assert PrivateMedia.asset_url(nil) == nil
    end

    test "never falls back to a persisted storage URL" do
      assert PrivateMedia.asset_url(%{url: "https://t3.storage.dev/private/image.png"}) == nil
    end
  end

  test "project_file_url/2 encodes the storage key" do
    key = "projects/7/blobs/hash with spaces.webp"
    encoded_key = Base.url_encode64(key, padding: false)

    assert PrivateMedia.project_file_url(7, key) ==
             "/media/projects/7/files/#{encoded_key}"
  end

  test "project_url_from_stored/2 converts a persisted storage URL" do
    stored_url = "/uploads/test/projects/7/assets/image.png"

    assert PrivateMedia.project_url_from_stored(7, stored_url) ==
             PrivateMedia.project_file_url(7, "projects/7/assets/image.png")

    assert PrivateMedia.project_url_from_stored(8, stored_url) == nil
  end

  test "project media keys are limited to non-empty asset and blob paths" do
    assert PrivateMedia.project_asset_key?(7, "projects/7/assets/uuid/image.png")
    refute PrivateMedia.project_asset_key?(7, "projects/7/blobs/hash.png")

    assert PrivateMedia.project_media_key?(7, "projects/7/assets/uuid/image.png")
    assert PrivateMedia.project_media_key?(7, "projects/7/blobs/hash.png")
    refute PrivateMedia.project_media_key?(7, "projects/7/assets")
    refute PrivateMedia.project_media_key?(7, "projects/7/snapshots/project/1.json.gz")
    refute PrivateMedia.project_media_key?(7, "projects/8/assets/uuid/image.png")
    refute PrivateMedia.project_media_key?(7, "projects/7/assets/../snapshot.json.gz")
  end

  test "storage keys reject empty, malformed, and traversing paths" do
    assert PrivateMedia.valid_storage_key?("projects/7/assets/image.png")

    refute PrivateMedia.valid_storage_key?("")
    refute PrivateMedia.valid_storage_key?("/projects/7/assets/image.png")
    refute PrivateMedia.valid_storage_key?("projects//7/assets/image.png")
    refute PrivateMedia.valid_storage_key?("projects/7/assets/./image.png")
    refute PrivateMedia.valid_storage_key?("projects/7/assets/../image.png")
    refute PrivateMedia.valid_storage_key?("projects/7/assets\\image.png")
    refute PrivateMedia.valid_storage_key?("projects/7/assets/image.png" <> <<0>>)
    refute PrivateMedia.valid_storage_key?(<<255>>)
    refute PrivateMedia.valid_storage_key?(nil)
  end

  describe "project_snapshot_asset_url/2" do
    test "uses the current snapshot key" do
      key = "projects/7/blobs/banner.png"

      assert PrivateMedia.project_snapshot_asset_url(7, %{
               "key" => key,
               "url" => "/uploads/test/projects/7/assets/old.png"
             }) == PrivateMedia.project_file_url(7, key)
    end

    test "rejects snapshot metadata without a current storage key" do
      assert PrivateMedia.project_snapshot_asset_url(7, %{
               "url" => "/uploads/test/projects/7/assets/banner.png"
             }) == nil
    end

    test "rejects metadata belonging to another project" do
      metadata = %{
        "key" => "projects/8/blobs/private.png",
        "url" => "/uploads/test/projects/8/assets/private.png"
      }

      assert PrivateMedia.project_snapshot_asset_url(7, metadata) == nil
    end
  end

  test "workspace_banner_url/1 hides the persisted storage URL" do
    workspace = %{
      slug: "writers-room",
      banner_url: "https://t3.storage.dev/private-bucket/workspaces/writers-room/banner/image.png"
    }

    url = PrivateMedia.workspace_banner_url(workspace)
    uri = URI.parse(url)

    assert uri.path == "/media/workspaces/writers-room/banner"
    assert uri.query =~ ~r/\Arevision=[A-Za-z0-9_-]{16}\z/
    refute url =~ "t3.storage.dev"
    refute url =~ "private-bucket"
  end

  test "workspace_banner_url/1 changes its opaque revision when the stored banner changes" do
    workspace = %{
      slug: "writers-room",
      banner_url: "https://storage.invalid/workspaces/writers-room/banner/first.png"
    }

    first_url = PrivateMedia.workspace_banner_url(workspace)

    second_url =
      PrivateMedia.workspace_banner_url(%{
        workspace
        | banner_url: String.replace(workspace.banner_url, "first", "second")
      })

    assert first_url == PrivateMedia.workspace_banner_url(workspace)
    refute first_url == second_url
  end
end
