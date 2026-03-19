defmodule Storyarn.Assets.DisplayUrlTest do
  use ExUnit.Case, async: true

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset

  describe "display_url/1" do
    test "returns web_url when variant exists" do
      asset = %Asset{
        url: "/original.png",
        metadata: %{"web_url" => "/optimized.webp", "web_asset_id" => 42}
      }

      assert Assets.display_url(asset) == "/optimized.webp"
    end

    test "returns original url when no variant" do
      asset = %Asset{url: "/original.png", metadata: %{}}

      assert Assets.display_url(asset) == "/original.png"
    end

    test "returns original url when metadata is nil" do
      asset = %Asset{url: "/original.png", metadata: nil}

      assert Assets.display_url(asset) == "/original.png"
    end

    test "returns nil for nil asset" do
      assert Assets.display_url(nil) == nil
    end

    test "handles plain map with url key" do
      assert Assets.display_url(%{url: "/some.png"}) == "/some.png"
    end

    test "ignores non-string web_url" do
      asset = %Asset{url: "/original.png", metadata: %{"web_url" => nil}}

      assert Assets.display_url(asset) == "/original.png"
    end

    test "returns empty string web_url as-is (truthy binary)" do
      asset = %Asset{url: "/original.png", metadata: %{"web_url" => ""}}

      # Empty string is still a binary, so the guard matches
      assert Assets.display_url(asset) == ""
    end
  end
end
