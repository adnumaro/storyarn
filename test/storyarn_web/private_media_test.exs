defmodule StoryarnWeb.PrivateMediaTest do
  use StoryarnWeb.ConnCase, async: true

  alias Storyarn.Assets.Asset
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

    test "returns nil without an asset" do
      assert PrivateMedia.asset_url(nil) == nil
    end
  end

  test "project_file_url/2 encodes the storage key" do
    key = "projects/7/blobs/hash with spaces.webp"
    encoded_key = Base.url_encode64(key, padding: false)

    assert PrivateMedia.project_file_url(7, key) ==
             "/media/projects/7/files/#{encoded_key}"
  end

  test "project_url_from_stored/2 converts a legacy storage URL" do
    stored_url = "/uploads/test/projects/7/assets/image.png"

    assert PrivateMedia.project_url_from_stored(7, stored_url) ==
             PrivateMedia.project_file_url(7, "projects/7/assets/image.png")

    assert PrivateMedia.project_url_from_stored(8, stored_url) == nil
  end

  describe "project_snapshot_asset_url/2" do
    test "uses the current snapshot key" do
      key = "projects/7/blobs/banner.png"

      assert PrivateMedia.project_snapshot_asset_url(7, %{
               "key" => key,
               "url" => "/uploads/test/projects/7/assets/old.png"
             }) == PrivateMedia.project_file_url(7, key)
    end

    test "falls back to the legacy stored URL for older snapshots" do
      stored_url = "/uploads/test/projects/7/assets/legacy-banner.png"

      assert PrivateMedia.project_snapshot_asset_url(7, %{"url" => stored_url}) ==
               PrivateMedia.project_file_url(7, "projects/7/assets/legacy-banner.png")
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

    assert PrivateMedia.workspace_banner_url(workspace) ==
             "/media/workspaces/writers-room/banner"
  end
end
